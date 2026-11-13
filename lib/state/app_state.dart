import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/claude_service.dart';
import '../services/cloud_service.dart';
import '../services/email_config.dart';
import '../services/notification_service.dart';
import '../services/plan_email_service.dart';
import '../services/scheduler_engine.dart';
import '../services/storage_service.dart';
import '../services/suggestion_engine.dart';
import '../theme/app_theme.dart';

class Achievement {
  final String id, en, si, descEn, descSi;
  final IconData icon;
  final Color color;
  final bool unlocked;
  final double progress;
  const Achievement(this.id, this.en, this.si, this.descEn, this.descSi, this.icon,
      this.color, this.unlocked, this.progress);
}

class AppState extends ChangeNotifier {
  final _store = StorageService.instance;
  final _auth = AuthService.instance;
  final _cloud = CloudService.instance;

  /// Firebase is configured: Firebase login, reset emails, Firestore sync.
  bool get cloudEnabled => _cloud.enabled;
  bool get isCloudUser => cloudEnabled && user != null && !user!.isGuest;
  DateTime? get lastCloudSync => _cloud.lastSync;
  String? get cloudError => _cloud.lastError;
  bool get usesSqlite => _store.usesSqlite;
  final _engine = SchedulerEngine();
  final _notify = NotificationService.instance;

  // ── App-wide ────────────────────────────────────────────────────────────
  String language = 'EN';
  ThemeMode themeMode = ThemeMode.system;
  bool onboardingSeen = false;
  AppUser? user;

  // ── Per-user ────────────────────────────────────────────────────────────
  List<Subject> subjects = [];
  List<StudyTask> tasks = [];
  List<StudySession> sessions = [];
  List<SurveyResponse> surveys = [];
  List<DailyTask> dailyTasks = [];
  StudyPreferences prefs = StudyPreferences();
  bool setupDone = false;
  bool researchConsent = false;
  /// Plan with Claude AI through the Cloud Function (Firebase accounts only).
  bool useClaude = false;

  /// Email each applied plan to the registered address (Firebase accounts only).
  bool emailPlans = true;
  Set<String> flags = {};
  Map<SuggestionType, FeedbackStat> suggestionFeedback = {};
  Map<String, DateTime> dismissedSuggestions = {};

  PlanResult? lastPlan;
  bool planning = false;
  String? planError;

  bool get isSinhala => language == 'SI';
  String t(String en, String si) => isSinhala ? si : en;

  // ── Boot ────────────────────────────────────────────────────────────────
  Future<void> boot() async {
    final app = _store.app;
    language = app.get('language', defaultValue: 'EN');
    themeMode = ThemeMode.values[app.get('theme', defaultValue: 0)];
    onboardingSeen = app.get('onboarding', defaultValue: false);
    await _notify.init();
    // Guest session is local; otherwise Firebase's signed-in user, else a local account.
    final session = _store.app.get('session_uid') as String?;
    user = session == 'guest' ? AuthService.guestUser : (_cloud.currentUser ?? (cloudEnabled ? null : _auth.restore()));
    if (user != null) await _loadUser();
    notifyListeners();
  }

  Future<void> _loadUser() async {
    await _store.openUser(user!.id);
    // Signed-in Firebase students: merge their cloud copy into SQLite, then keep it in sync.
    if (isCloudUser) {
      await _cloud.attach(user!.id);
    } else {
      _cloud.detach();
    }
    subjects = _store.readList('subjects').map(Subject.fromJson).toList();
    tasks = _store.readList('tasks').map(StudyTask.fromJson).toList();
    sessions = _store.readList('sessions').map(StudySession.fromJson).toList();
    surveys = _store.readList('surveys').map(SurveyResponse.fromJson).toList();
    dailyTasks = _store.readList('dailyTasks').map(DailyTask.fromJson).toList();
    final p = _store.readMap('prefs');
    prefs = p == null ? StudyPreferences() : StudyPreferences.fromJson(p);
    setupDone = _store.read<bool>('setupDone') ?? false;
    researchConsent = _store.read<bool>('consent') ?? false;
    useClaude = _store.read<bool>('useClaude') ?? false;
    emailPlans = _store.read<bool>('emailPlans') ?? true;
    flags = (_store.read<String>('flags') ?? '').split(',').where((s) => s.isNotEmpty).toSet();
    final fb = _store.readMap('sugFeedback') ?? {};
    suggestionFeedback = {
      for (final e in fb.entries)
        for (final t in SuggestionType.values)
          if (t.name == e.key) t: FeedbackStat.fromJson(e.value as List),
    };
    final dm = _store.readMap('sugDismissed') ?? {};
    dismissedSuggestions = {for (final e in dm.entries) e.key: DateTime.parse(e.value as String)};
    markMissed(save: false);
    await _saveTasks();
    // Ask once for notification permission, right after the first sign-in.
    if (!(_store.read<bool>('notifAsked') ?? false)) {
      await _store.write('notifAsked', true);
      await _notify.requestPermission();
    }
  }

  // ── Persistence helpers ─────────────────────────────────────────────────
  Future<void> _saveSubjects() =>
      _store.writeList('subjects', subjects.map((s) => s.toJson()).toList());
  Future<void> _saveSessions() =>
      _store.writeList('sessions', sessions.map((s) => s.toJson()).toList());
  Future<void> _saveTasks() async {
    await _store.writeList('tasks', tasks.map((x) => x.toJson()).toList());
    await syncReminders();
  }

  Future<void> saveAll() async {
    await _saveSubjects();
    await _saveSessions();
    await _saveTasks();
  }

  Future<void> _flag(String f) async {
    if (flags.add(f)) await _store.write('flags', flags.join(','));
  }

  Future<void> syncReminders() => _notify.sync(
        tasks: tasks,
        subjects: {for (final s in subjects) s.id: s},
        prefs: prefs,
        t: t,
        daily: dailyTasks,
      );

  // ── Daily task management ───────────────────────────────────────────────
  Future<void> _saveDaily() async {
    await _store.writeList('dailyTasks', dailyTasks.map((x) => x.toJson()).toList());
    await syncReminders();
  }

  /// Tasks for a day: open ones first (high priority, then earliest due), done last.
  List<DailyTask> dailyFor(DateTime day) {
    final list = dailyTasks.where((x) => x.occursOn(day)).toList();
    int rank(DailyTask x) => x.doneOn(day) ? 1 : 0;
    list.sort((a, b) {
      final r = rank(a).compareTo(rank(b));
      if (r != 0) return r;
      final p = b.priority.index.compareTo(a.priority.index);
      if (p != 0) return p;
      return (a.dueMinutes ?? 9999).compareTo(b.dueMinutes ?? 9999);
    });
    return list;
  }

  List<DailyTask> get overdueDaily =>
      dailyTasks.where((x) => x.isOverdue(DateTime.now())).toList()
        ..sort((a, b) => b.priority.index.compareTo(a.priority.index));

  /// (done, total) for a day.
  (int, int) dailyProgress(DateTime day) {
    final list = dailyTasks.where((x) => x.occursOn(day)).toList();
    return (list.where((x) => x.doneOn(day)).length, list.length);
  }

  int get dailyDoneThisWeek {
    final today = dateOnly(DateTime.now());
    var n = 0;
    for (var i = 0; i < 7; i++) {
      n += dailyProgress(today.subtract(Duration(days: i))).$1;
    }
    return n;
  }

  Future<void> upsertDaily(DailyTask x) async {
    final i = dailyTasks.indexWhere((y) => y.id == x.id);
    i == -1 ? dailyTasks.add(x) : dailyTasks[i] = x;
    await _saveDaily();
    notifyListeners();
  }

  Future<void> addQuickDaily(String title, {DateTime? day}) async {
    final t = title.trim();
    if (t.isEmpty) return;
    await upsertDaily(DailyTask(
      id: 'd_${DateTime.now().microsecondsSinceEpoch}',
      title: t,
      date: day ?? DateTime.now(),
    ));
  }

  Future<void> deleteDaily(String id) async {
    dailyTasks.removeWhere((x) => x.id == id);
    await _saveDaily();
    notifyListeners();
  }

  Future<void> toggleDaily(DailyTask x, DateTime day) async {
    final k = dayKey(day);
    if (!x.doneDates.remove(k)) {
      x.doneDates.add(k);
      for (final s in x.subtasks) {
        s.doneDates.add(k); // finishing the task finishes its steps
      }
      await _flag('dailyTask');
    }
    await _saveDaily();
    notifyListeners();
  }

  Future<void> toggleSubtask(DailyTask x, int index, DateTime day) async {
    final k = dayKey(day);
    final s = x.subtasks[index];
    if (!s.doneDates.remove(k)) s.doneDates.add(k);
    // All steps ticked → the task is done; un-ticking one reopens it.
    if (x.subtasks.every((y) => y.doneOn(day))) {
      x.doneDates.add(k);
    } else {
      x.doneDates.remove(k);
    }
    await _saveDaily();
    notifyListeners();
  }

  Future<void> moveDailyToToday(Iterable<DailyTask> list) async {
    for (final x in list) {
      x.date = dateOnly(DateTime.now());
    }
    await _saveDaily();
    notifyListeners();
  }

  // ── Smart suggestions ───────────────────────────────────────────────────
  final _suggester = SuggestionEngine();
  List<Suggestion>? _suggestionCache;

  @override
  void notifyListeners() {
    _styleCache = null;
    _suggestionCache = null; // recompute after any change
    super.notifyListeners();
  }

  /// Improvement suggestions for the current plan, ranked by expected
  /// benefit × how often this student accepts that kind of advice.
  List<Suggestion> get suggestions => _suggestionCache ??= user == null
      ? []
      : _suggester.generate(
          subjects: subjects,
          tasks: tasks,
          sessions: sessions,
          prefs: prefs,
          feedback: suggestionFeedback,
          dismissed: dismissedSuggestions,
          t: t,
          typeLabel: typeLabel,
        );

  Future<void> applySuggestion(Suggestion s) async {
    for (final a in s.actions) {
      final i = a.taskId == null ? -1 : tasks.indexWhere((x) => x.id == a.taskId);
      switch (a.kind) {
        case 'move' when i != -1:
          tasks[i]
            ..start = a.newStart!
            ..status = TaskStatus.pending;
        case 'split' when i != -1:
          final x = tasks[i]..durationMinutes = a.newDuration!;
          tasks.add(StudyTask.fromJson({
            ...x.toJson(),
            'id': '${x.id}_p2',
            'title': '${x.title} (2/2)',
            'start': a.splitStart!.toIso8601String(),
            'duration': a.splitDuration,
          }));
        case 'add':
          tasks.add(a.newTask!);
        case 'prefs':
          if (a.sessionMinutes != null) prefs.sessionMinutes = a.sessionMinutes!;
          if (a.window != null) prefs.window = a.window!;
          await _store.writeMap('prefs', prefs.toJson());
      }
    }
    (suggestionFeedback[s.type] ??= FeedbackStat()).accepted++;
    await _saveFeedback();
    await _saveTasks();
    await _flag('suggestion');
    notifyListeners();
  }

  Future<void> dismissSuggestion(Suggestion s) async {
    (suggestionFeedback[s.type] ??= FeedbackStat()).rejected++;
    dismissedSuggestions[s.id] = DateTime.now();
    await _saveFeedback();
    notifyListeners();
  }

  Future<void> _saveFeedback() async {
    await _store.writeMap('sugFeedback', {for (final e in suggestionFeedback.entries) e.key.name: e.value.toJson()});
    await _store.writeMap('sugDismissed',
        {for (final e in dismissedSuggestions.entries) e.key: e.value.toIso8601String()});
  }

  // ── Settings ────────────────────────────────────────────────────────────
  Future<void> setLanguage(String lang) async {
    language = lang;
    await _store.app.put('language', lang);
    notifyListeners();
    await syncReminders();
  }

  Future<void> toggleLanguage() => setLanguage(isSinhala ? 'EN' : 'SI');

  Future<void> setTheme(ThemeMode m) async {
    themeMode = m;
    await _store.app.put('theme', m.index);
    notifyListeners();
  }

  Future<void> finishOnboarding() async {
    onboardingSeen = true;
    await _store.app.put('onboarding', true);
    notifyListeners();
  }

  Future<void> savePrefs(StudyPreferences p) async {
    prefs = p;
    await _store.writeMap('prefs', p.toJson());
    notifyListeners();
    await syncReminders();
  }

  Future<void> completeSetup({required bool consent}) async {
    setupDone = true;
    researchConsent = consent;
    await _store.write('setupDone', true);
    await _store.write('consent', consent);
    await _notify.requestPermission();
    notifyListeners();
  }

  Future<void> setConsent(bool v) async {
    researchConsent = v;
    await _store.write('consent', v);
    notifyListeners();
  }

  /// Claude planning needs a signed-in Firebase account (the function checks it).
  bool get claudeAvailable => isCloudUser;

  Future<void> setUseClaude(bool v) async {
    useClaude = v;
    await _store.write('useClaude', v);
    notifyListeners();
  }

  // ── Auth ────────────────────────────────────────────────────────────────
  Future<String?> signIn(String email, String password) async {
    final (u, err) = cloudEnabled ? await _cloud.signIn(email, password) : await _auth.signIn(email, password);
    if (u == null) return err;
    if (cloudEnabled) await _store.app.delete('session_uid'); // Firebase keeps the session
    user = u;
    await _loadUser();
    notifyListeners();
    return null;
  }

  /// Creates the account only. The student is sent to Sign in afterwards.
  Future<String?> register(String name, String email, String password,
      {int? questionId, String answer = ''}) async {
    if (cloudEnabled) return _cloud.register(name, email, password);
    final (u, err) = await _auth.register(name, email, password, questionId: questionId, answer: answer);
    return u == null ? err : null;
  }

  // Forgot password — see AuthService for error codes.
  (int?, String?) recoveryQuestion(String email) => _auth.recoveryQuestion(email);
  Future<String?> resetPassword(String email, String answer, String newPassword) =>
      _auth.resetPassword(email, answer, newPassword);
  bool get hasRecovery => user != null && !user!.isGuest && _auth.hasRecovery(user!.email);
  int? get recoveryQuestionId => user == null || user!.isGuest ? null : _auth.questionOf(user!.email);

  Future<String?> setRecovery(String password, int questionId, String answer) async {
    final err = await _auth.setRecovery(user!.email, password, questionId, answer);
    notifyListeners();
    return err;
  }

  /// Bilingual security questions (index = stored question id).
  String securityQuestion(int id) => switch (id) {
        0 => t('What was the name of your first school?', 'ඔබේ පළමු පාසලේ නම කුමක්ද?'),
        1 => t("What is your favourite teacher's name?", 'ඔබේ ප්‍රියතම ගුරුවරයාගේ නම කුමක්ද?'),
        2 => t('In which city were you born?', 'ඔබ ඉපදුණු නගරය කුමක්ද?'),
        3 => t('What was the name of your first pet?', 'ඔබේ පළමු සුරතල් සතාගේ නම කුමක්ද?'),
        4 => t("What is your mother's maiden name?", 'ඔබේ මවගේ විවාහයට පෙර වාසගම කුමක්ද?'),
        _ => t('What is your favourite food?', 'ඔබේ ප්‍රියතම ආහාරය කුමක්ද?'),
      };

  Future<void> continueAsGuest() async {
    user = await _auth.continueAsGuest();
    await _loadUser();
    notifyListeners();
  }

  /// Firebase mode: sends a password-reset email.
  Future<String?> sendPasswordReset(String email) => _cloud.sendPasswordReset(email);

  Future<void> syncNow() async {
    await _cloud.pull();
    if (user != null) await _loadUser();
    notifyListeners();
  }

  Future<void> signOut() async {
    await _cloud.signOut();
    await _auth.signOut();
    await _store.closeUser();
    user = null;
    subjects = [];
    tasks = [];
    sessions = [];
    surveys = [];
    dailyTasks = [];
    lastPlan = null;
    notifyListeners();
  }

  Future<void> resetData() async {
    await _store.clearUser();
    await _loadUser();
    lastPlan = null;
    notifyListeners();
  }

  // ── Subjects ────────────────────────────────────────────────────────────
  Subject? subject(String id) {
    for (final s in subjects) {
      if (s.id == id) return s;
    }
    return null;
  }

  Color subjectColor(String id) => subject(id)?.color ?? AppColors.primary;

  Future<void> upsertSubject(Subject s) async {
    final i = subjects.indexWhere((x) => x.id == s.id);
    i == -1 ? subjects.add(s) : subjects[i] = s;
    await _saveSubjects();
    notifyListeners();
  }

  Future<void> deleteSubject(String id) async {
    subjects.removeWhere((s) => s.id == id);
    tasks.removeWhere((x) => x.subjectId == id && x.status == TaskStatus.pending);
    await _saveSubjects();
    await _saveTasks();
    notifyListeners();
  }

  Future<void> addSampleSubjects() async {
    final now = DateTime.now();
    const c = AppColors.subjectPalette;
    subjects.addAll([
      Subject(id: 's1', name: 'Mobile Computing', colorValue: c[0].value, icon: 'phone',
          difficulty: Difficulty.hard, examDate: now.add(const Duration(days: 12)), targetHours: 30),
      Subject(id: 's2', name: 'Computer Networks', colorValue: c[1].value, icon: 'network',
          difficulty: Difficulty.medium, examDate: now.add(const Duration(days: 19)), targetHours: 25),
      Subject(id: 's3', name: 'Data Structures', colorValue: c[2].value, icon: 'code',
          difficulty: Difficulty.hard, examDate: now.add(const Duration(days: 6)), targetHours: 20),
      Subject(id: 's4', name: 'Software Engineering', colorValue: c[3].value, icon: 'gear',
          difficulty: Difficulty.easy, examDate: now.add(const Duration(days: 26)), targetHours: 15),
    ]);
    await _saveSubjects();
    notifyListeners();
  }

  // ── Tasks ───────────────────────────────────────────────────────────────
  List<StudyTask> tasksOn(DateTime d) =>
      tasks.where((x) => sameDay(x.start, d)).toList()
        ..sort((a, b) => a.start.compareTo(b.start));

  List<StudyTask> get todayTasks => tasksOn(DateTime.now());
  List<StudyTask> get missedTasks =>
      tasks.where((x) => x.status == TaskStatus.missed).toList();

  StudyTask? get nextTask {
    final now = DateTime.now();
    final up = tasks
        .where((x) => x.status == TaskStatus.pending && x.end.isAfter(now))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    return up.isEmpty ? null : up.first;
  }

  /// Pending tasks whose time has passed become "missed" (feeds the adaptive engine).
  bool markMissed({bool save = true}) {
    final now = DateTime.now();
    var changed = false;
    for (final x in tasks) {
      if (x.status == TaskStatus.pending &&
          x.end.add(const Duration(minutes: 30)).isBefore(now)) {
        x.status = TaskStatus.missed;
        changed = true;
      }
    }
    if (changed && save) {
      _saveTasks();
      notifyListeners();
    }
    return changed;
  }

  Future<void> upsertTask(StudyTask x) async {
    final i = tasks.indexWhere((y) => y.id == x.id);
    i == -1 ? tasks.add(x) : tasks[i] = x;
    await _saveTasks();
    notifyListeners();
  }

  Future<void> deleteTask(String id) async {
    tasks.removeWhere((x) => x.id == id);
    sessions.removeWhere((s) => s.taskId == id);
    await _saveTasks();
    await _saveSessions();
    notifyListeners();
  }

  Future<void> setTaskStatus(StudyTask x, TaskStatus status) async {
    final wasDone = x.isDone;
    x.status = status;
    if (status == TaskStatus.completed && !wasDone) {
      x.completedAt = DateTime.now();
      if (!sessions.any((s) => s.taskId == x.id)) {
        sessions.add(StudySession(
          id: 'ses_${DateTime.now().microsecondsSinceEpoch}',
          subjectId: x.subjectId,
          taskId: x.id,
          start: x.start.isAfter(DateTime.now()) ? DateTime.now() : x.start,
          minutes: x.durationMinutes,
        ));
      }
    } else if (status != TaskStatus.completed && wasDone) {
      x.completedAt = null;
      sessions.removeWhere((s) => s.taskId == x.id);
    }
    await _saveTasks();
    await _saveSessions();
    notifyListeners();
  }

  Future<void> toggleTask(StudyTask x) =>
      setTaskStatus(x, x.isDone ? TaskStatus.pending : TaskStatus.completed);

  // ── Focus sessions ──────────────────────────────────────────────────────
  Future<void> logFocusSession({
    required String subjectId,
    required int minutes,
    required int rating,
    StudyTask? task,
  }) async {
    sessions.add(StudySession(
      id: 'ses_${DateTime.now().microsecondsSinceEpoch}',
      subjectId: subjectId,
      taskId: task?.id,
      start: DateTime.now().subtract(Duration(minutes: minutes)),
      minutes: minutes,
      focusRating: rating,
    ));
    if (task != null && !task.isDone) {
      task
        ..status = TaskStatus.completed
        ..completedAt = DateTime.now();
      await _saveTasks();
    }
    await _saveSessions();
    await _flag('focus');
    notifyListeners();
  }

  // ── AI planning ─────────────────────────────────────────────────────────
  String typeLabel(SessionType s) => switch (s) {
        SessionType.learn => t('Concept study', 'සංකල්ප අධ්‍යයනය'),
        SessionType.practice => t('Practice problems', 'අභ්‍යාස ගැටලු'),
        SessionType.review => t('Active recall review', 'පුනරීක්ෂණය'),
        SessionType.pastPaper => t('Past paper', 'පසුගිය ප්‍රශ්න පත්‍ර'),
        SessionType.finalRevision => t('Final revision', 'අවසන් පුනරීක්ෂණය'),
        SessionType.custom => t('Study session', 'අධ්‍යයන සැසිය'),
      };

  String difficultyLabel(Difficulty d) => switch (d) {
        Difficulty.easy => t('Easy', 'පහසු'),
        Difficulty.medium => t('Medium', 'මධ්‍යම'),
        Difficulty.hard => t('Hard', 'අපහසු'),
      };

  List<SubjectInsight> get insights => _engine.analyse(subjects, tasks, sessions, mode: prefs.planMode);

  Future<void> setPlanMode(PlanMode m) async {
    prefs.planMode = m;
    await savePrefs(prefs);
  }

  Map<PlanMode, PlanResult>? _styleCache;

  /// What each planning style would produce right now, so the student can
  /// compare them before generating. Recomputed after any change.
  Map<PlanMode, PlanResult> get stylePreviews => _styleCache ??= {
        for (final m in PlanMode.values)
          m: _engine.generate(
            subjects: subjects,
            existing: tasks,
            sessions: sessions,
            prefs: StudyPreferences.fromJson({...prefs.toJson(), 'mode': m.name}),
            typeLabel: typeLabel,
          ),
      };

  /// Minutes per subject in a plan, largest first.
  List<(Subject, int, int)> minutesBySubject(PlanResult plan) {
    final mins = <String, int>{}, count = <String, int>{};
    for (final x in plan.tasks) {
      mins[x.subjectId] = (mins[x.subjectId] ?? 0) + x.durationMinutes;
      count[x.subjectId] = (count[x.subjectId] ?? 0) + 1;
    }
    final out = [
      for (final s in subjects.where((s) => !s.examPassed)) (s, mins[s.id] ?? 0, count[s.id] ?? 0),
    ]..sort((a, b) => b.$2.compareTo(a.$2));
    return out;
  }

  String planModeLabel(PlanMode m) => switch (m) {
        PlanMode.balanced => t('Balanced', 'සමබර'),
        PlanMode.examFocus => t('Exam focus', 'විභාග අවධානය'),
        PlanMode.light => t('Light week', 'සැහැල්ලු සතිය'),
      };
  double get adherence => _engine.adherence(tasks);

  /// Builds a plan preview. Nothing is saved until [applyPlan].
  Future<PlanResult?> buildPlan() async {
    planning = true;
    planError = null;
    notifyListeners();
    markMissed(save: false);
    try {
      var result = _engine.generate(
        subjects: subjects,
        existing: tasks,
        sessions: sessions,
        prefs: prefs,
        typeLabel: typeLabel,
      );
      if (useClaude && claudeAvailable && result.insights.isNotEmpty) {
        // Claude plans from the same priorities; anything it can't do falls back to on-device.
        final now = DateTime.now();
        try {
          result = await ClaudeService.instance.generate(
            insights: result.insights,
            keep: tasks
                .where((x) => !(x.aiGenerated && x.status == TaskStatus.pending && x.start.isAfter(now)))
                .toList(),
            prefs: prefs,
            adherence: result.adherence,
            loadFactor: result.loadFactor,
            language: language,
            typeLabel: typeLabel,
          );
        } catch (e) {
          debugPrint('Claude planning failed: $e');
          planError = t('Claude AI unavailable (${_claudeError(e)}). Showing the on-device plan.',
              'Claude AI ලබාගත නොහැක (${_claudeError(e)}). උපාංගයේ සැලැස්ම පෙන්වයි.');
        }
      } else {
        // Give the planner a beat so the UI can show its thinking state.
        await Future.delayed(const Duration(milliseconds: 900));
      }
      lastPlan = result;
      return result;
    } finally {
      planning = false;
      notifyListeners();
    }
  }

  Future<void> setEmailPlans(bool v) async {
    emailPlans = v;
    await _store.write('emailPlans', v);
    notifyListeners();
  }

  /// Plan emails work for registered accounts: via EmailJS from the app,
  /// or the Cloud Function for Firebase accounts.
  bool get canEmailPlans =>
      user != null && !user!.isGuest && user!.email.isNotEmpty && (EmailConfig.useEmailJs || isCloudUser);

  /// Emails [plan] to the student's registered address.
  /// Returns (address, null) on success or (null, message) on failure.
  Future<(String?, String?)> emailPlan(PlanResult plan) async {
    if (!canEmailPlans) {
      return (null, t('Sign in with an account to get plans by email.', 'ඊමේල් ලබා ගැනීමට ගිණුමකින් පුරනය වන්න.'));
    }
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final parts = (_store.read<String>('emailCount') ?? '').split('|');
    final sentToday = parts.length == 2 && parts[0] == today ? int.tryParse(parts[1]) ?? 0 : 0;
    if (sentToday >= EmailConfig.dailyLimit) {
      return (null, t('daily limit of ${EmailConfig.dailyLimit} emails reached', 'දිනකට ඊමේල් ${EmailConfig.dailyLimit} සීමාව ඉක්මවා ඇත'));
    }
    try {
      final to = await PlanEmailService.instance.send(
        PlanEmailService.buildRequest(
          plan: plan,
          subjects: subjects,
          name: user!.name,
          language: language,
          typeLabel: typeLabel,
        ),
        to: user!.email,
        name: user!.name,
      );
      await _store.write('emailCount', '$today|${sentToday + 1}');
      return (to, null);
    } catch (e) {
      debugPrint('Plan email failed: $e');
      return (null, e is PlanEmailException ? e.message : _claudeError(e));
    }
  }

  String _claudeError(Object e) {
    if (e is FirebaseFunctionsException) {
      return switch (e.code) {
        'not-found' => t('function not deployed', 'function එක deploy කර නැත'),
        'unauthenticated' => t('sign in again', 'නැවත පුරනය වන්න'),
        'deadline-exceeded' => t('took too long', 'වැඩි කාලයක් ගත විය'),
        'unavailable' || 'internal' when (e.message ?? '').isEmpty => t('no connection', 'සම්බන්ධතාවය නැත'),
        _ => e.message ?? e.code,
      };
    }
    return t('no connection', 'සම්බන්ධතාවය නැත');
  }

  /// Replaces future, still-pending AI tasks with the new plan.
  Future<void> applyPlan(PlanResult plan) async {
    final now = DateTime.now();
    tasks.removeWhere((x) =>
        x.aiGenerated && x.status == TaskStatus.pending && x.start.isAfter(now));
    tasks.addAll(plan.tasks);
    await _saveTasks();
    await _flag('planner');
    notifyListeners();
  }

  Future<RescheduleResult> rescheduleMissed() async {
    final r = _engine.reschedule(all: tasks, subjects: subjects, prefs: prefs);
    await _saveTasks();
    if (r.moved > 0) await _flag('comeback');
    notifyListeners();
    return r;
  }

  // ── Analytics ───────────────────────────────────────────────────────────
  int minutesOn(DateTime d) =>
      sessions.where((s) => sameDay(s.start, d)).fold(0, (a, s) => a + s.minutes);

  int get totalMinutes => sessions.fold(0, (a, s) => a + s.minutes);

  int minutesForSubject(String id) =>
      sessions.where((s) => s.subjectId == id).fold(0, (a, s) => a + s.minutes);

  double subjectProgress(Subject s) =>
      s.targetHours == 0 ? 0 : (minutesForSubject(s.id) / (s.targetHours * 60)).clamp(0.0, 1.0);

  /// Minutes studied for each of the last 7 days (oldest first).
  List<int> get last7Days {
    final today = dateOnly(DateTime.now());
    return List.generate(7, (i) => minutesOn(today.subtract(Duration(days: 6 - i))));
  }

  /// Planned minutes for each of the last 7 days (oldest first).
  List<int> get planned7Days {
    final today = dateOnly(DateTime.now());
    return List.generate(7, (i) {
      final d = today.subtract(Duration(days: 6 - i));
      return tasks
          .where((x) => sameDay(x.start, d) && x.status != TaskStatus.skipped)
          .fold(0, (a, x) => a + x.durationMinutes);
    });
  }

  int get weekMinutes => last7Days.fold(0, (a, b) => a + b);

  int get streak {
    var day = dateOnly(DateTime.now());
    if (minutesOn(day) == 0) day = day.subtract(const Duration(days: 1));
    var n = 0;
    while (minutesOn(day) > 0) {
      n++;
      day = day.subtract(const Duration(days: 1));
    }
    return n;
  }

  int get bestStreak {
    if (sessions.isEmpty) return 0;
    final days = sessions.map((s) => dateOnly(s.start)).toSet().toList()..sort();
    var best = 1, cur = 1;
    for (var i = 1; i < days.length; i++) {
      cur = days[i].difference(days[i - 1]).inDays == 1 ? cur + 1 : 1;
      if (cur > best) best = cur;
    }
    return best;
  }

  double get todayGoalProgress =>
      (minutesOn(DateTime.now()) / prefs.dailyGoalMinutes).clamp(0.0, 1.0);

  double get completionRate {
    final due = tasks.where((x) => x.status != TaskStatus.pending).toList();
    if (due.isEmpty) return 0;
    return due.where((x) => x.isDone).length / due.length;
  }

  double? get avgFocus {
    final r = sessions.where((s) => s.focusRating != null).map((s) => s.focusRating!).toList();
    if (r.isEmpty) return null;
    return r.reduce((a, b) => a + b) / r.length;
  }

  /// Best hour of day by average focus rating (needs some data).
  int? get peakHour {
    final rated = sessions.where((s) => s.focusRating != null).toList();
    if (rated.length < 3) return null;
    final sum = <int, int>{}, cnt = <int, int>{};
    for (final s in rated) {
      sum[s.start.hour] = (sum[s.start.hour] ?? 0) + s.focusRating!;
      cnt[s.start.hour] = (cnt[s.start.hour] ?? 0) + 1;
    }
    return sum.keys.reduce((a, b) => sum[a]! / cnt[a]! >= sum[b]! / cnt[b]! ? a : b);
  }

  List<Achievement> get achievements {
    final hours = totalMinutes / 60;
    final done = tasks.where((x) => x.isDone).length;
    final s = bestStreak;
    return [
      Achievement('first', 'First Step', 'පළමු පියවර', 'Complete your first session',
          'පළමු සැසිය සම්පූර්ණ කරන්න', Icons.flag_rounded, AppColors.teal,
          done >= 1, (done / 1).clamp(0, 1).toDouble()),
      Achievement('planner', 'AI Planner', 'AI සැලසුම්කරු', 'Generate an AI study plan',
          'AI සැලැස්මක් සාදන්න', Icons.auto_awesome_rounded, AppColors.violet,
          flags.contains('planner'), flags.contains('planner') ? 1 : 0),
      Achievement('streak3', 'On Fire', 'ගිනිගත්', '3-day study streak',
          'දින 3ක අඛණ්ඩ අධ්‍යයනය', Icons.local_fire_department_rounded, AppColors.amber,
          s >= 3, (s / 3).clamp(0, 1).toDouble()),
      Achievement('streak7', 'Unstoppable', 'නොනවතින', '7-day study streak',
          'දින 7ක අඛණ්ඩ අධ්‍යයනය', Icons.bolt_rounded, AppColors.rose,
          s >= 7, (s / 7).clamp(0, 1).toDouble()),
      Achievement('focus', 'Deep Focus', 'ගැඹුරු අවධානය', 'Finish a focus timer session',
          'අවධාන කාල සැසියක් අවසන් කරන්න', Icons.timer_rounded, AppColors.sky,
          flags.contains('focus'), flags.contains('focus') ? 1 : 0),
      Achievement('hours10', '10 Hours', 'පැය 10', 'Study for 10 hours in total',
          'මුළු පැය 10ක් ඉගෙන ගන්න', Icons.hourglass_bottom_rounded, AppColors.primary,
          hours >= 10, (hours / 10).clamp(0, 1).toDouble()),
      Achievement('comeback', 'Comeback', 'නැවත පැමිණීම', 'Reschedule missed sessions',
          'මඟහැරුණු සැසි නැවත සකසන්න', Icons.replay_rounded, AppColors.green,
          flags.contains('comeback'), flags.contains('comeback') ? 1 : 0),
      Achievement('voice', 'Researcher', 'පර්යේෂක', 'Share feedback in the survey',
          'සමීක්ෂණයට ප්‍රතිචාර දෙන්න', Icons.science_rounded, AppColors.rose,
          surveys.isNotEmpty, surveys.isNotEmpty ? 1 : 0),
    ];
  }

  // ── Research / evaluation ───────────────────────────────────────────────
  Future<void> addSurvey(SurveyResponse r) async {
    surveys.add(r);
    await _store.writeList('surveys', surveys.map((s) => s.toJson()).toList());
    notifyListeners();
  }

  /// Anonymised export for the evaluation study — no name, email or IDs.
  String exportResearchData() {
    final subjectIndex = {for (var i = 0; i < subjects.length; i++) subjects[i].id: 'S${i + 1}'};
    return const JsonEncoder.withIndent('  ').convert({
      'app': 'StudySync',
      'exportedAt': DateTime.now().toIso8601String(),
      'language': language,
      'consent': researchConsent,
      'metrics': {
        'totalStudyMinutes': totalMinutes,
        'tasksPlanned': tasks.length,
        'tasksCompleted': tasks.where((x) => x.isDone).length,
        'tasksMissed': tasks.where((x) => x.status == TaskStatus.missed).length,
        'tasksRescheduled': tasks.where((x) => x.rescheduleCount > 0).length,
        'aiTasks': tasks.where((x) => x.aiGenerated).length,
        'completionRate': double.parse(completionRate.toStringAsFixed(3)),
        'adherence14d': double.parse(adherence.toStringAsFixed(3)),
        'bestStreak': bestStreak,
        'avgFocus': avgFocus,
        'dailyTasks': dailyTasks.length,
        'dailyTasksDoneThisWeek': dailyDoneThisWeek,
      },
      'subjects': subjects
          .map((s) => {
                'id': subjectIndex[s.id],
                'difficulty': s.difficulty.name,
                'daysToExam': s.daysToExam,
                'targetHours': s.targetHours,
                'studiedMinutes': minutesForSubject(s.id),
              })
          .toList(),
      'surveys': surveys.map((s) => s.toJson()).toList(),
    });
  }
}
