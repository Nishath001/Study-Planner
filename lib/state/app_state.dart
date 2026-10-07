import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/auth_service.dart';
import '../services/claude_service.dart';
import '../services/notification_service.dart';
import '../services/scheduler_engine.dart';
import '../services/storage_service.dart';
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
  StudyPreferences prefs = StudyPreferences();
  bool setupDone = false;
  bool researchConsent = false;
  String claudeKey = '';
  Set<String> flags = {};

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
    user = _auth.restore();
    if (user != null) await _loadUser();
    notifyListeners();
  }

  Future<void> _loadUser() async {
    await _store.openUser(user!.id);
    subjects = _store.readList('subjects').map(Subject.fromJson).toList();
    tasks = _store.readList('tasks').map(StudyTask.fromJson).toList();
    sessions = _store.readList('sessions').map(StudySession.fromJson).toList();
    surveys = _store.readList('surveys').map(SurveyResponse.fromJson).toList();
    final p = _store.readMap('prefs');
    prefs = p == null ? StudyPreferences() : StudyPreferences.fromJson(p);
    setupDone = _store.read<bool>('setupDone') ?? false;
    researchConsent = _store.read<bool>('consent') ?? false;
    claudeKey = _store.read<String>('claudeKey') ?? '';
    flags = (_store.read<String>('flags') ?? '').split(',').where((s) => s.isNotEmpty).toSet();
    markMissed(save: false);
    await _saveTasks();
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
      );

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

  Future<void> setClaudeKey(String k) async {
    claudeKey = k.trim();
    await _store.write('claudeKey', claudeKey);
    notifyListeners();
  }

  // ── Auth ────────────────────────────────────────────────────────────────
  Future<String?> signIn(String email, String password) async {
    final (u, err) = await _auth.signIn(email, password);
    if (u == null) return err;
    user = u;
    await _loadUser();
    notifyListeners();
    return null;
  }

  Future<String?> register(String name, String email, String password) async {
    final (u, err) = await _auth.register(name, email, password);
    if (u == null) return err;
    user = u;
    await _loadUser();
    notifyListeners();
    return null;
  }

  Future<void> continueAsGuest() async {
    user = await _auth.continueAsGuest();
    await _loadUser();
    notifyListeners();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    await _store.closeUser();
    user = null;
    subjects = [];
    tasks = [];
    sessions = [];
    surveys = [];
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

  List<SubjectInsight> get insights => _engine.analyse(subjects, tasks, sessions);
  double get adherence => _engine.adherence(tasks);

  /// Builds a plan preview. Nothing is saved until [applyPlan].
  Future<PlanResult?> buildPlan({bool useClaude = false}) async {
    planning = true;
    planError = null;
    notifyListeners();
    markMissed(save: false);
    try {
      PlanResult result = _engine.generate(
        subjects: subjects,
        existing: tasks,
        sessions: sessions,
        prefs: prefs,
        typeLabel: typeLabel,
      );
      if (useClaude && claudeKey.isNotEmpty && result.insights.isNotEmpty) {
        try {
          result = await ClaudeService.instance.generate(
            apiKey: claudeKey,
            insights: _engine.analyse(subjects, tasks, sessions),
            prefs: prefs,
            adherence: result.adherence,
            loadFactor: result.loadFactor,
            language: language,
            typeLabel: typeLabel,
          );
        } catch (e) {
          planError = t('Claude unavailable ($e). Showing the on-device plan.',
              'Claude ලබාගත නොහැක. උපාංගයේ සැලැස්ම පෙන්වයි.');
        }
      }
      // Give the planner a beat so the UI can show its thinking state.
      await Future.delayed(const Duration(milliseconds: 900));
      lastPlan = result;
      return result;
    } finally {
      planning = false;
      notifyListeners();
    }
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
