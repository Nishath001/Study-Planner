import 'dart:math';

import '../models/models.dart';

/// Why the planner weighted a subject the way it did. Shown to the student
/// so the AI's decisions are explainable, not a black box.
class SubjectInsight {
  final Subject subject;
  final double urgency; // 0–1, closer exam → higher
  final double difficulty; // 0–1
  final double workload; // 0–1, remaining hours relative to other subjects
  final double struggle; // 0–1, from missed tasks + low focus ratings
  final double score; // weighted priority
  final int remainingMinutes;
  int allocatedMinutes = 0;
  int sessions = 0;

  SubjectInsight({
    required this.subject,
    required this.urgency,
    required this.difficulty,
    required this.workload,
    required this.struggle,
    required this.score,
    required this.remainingMinutes,
  });
}

class PlanResult {
  final List<StudyTask> tasks;
  final List<SubjectInsight> insights;
  final double adherence; // 0–1 recent completion rate
  final double loadFactor; // how much of the available time was used
  final String engine;
  final String? advice;
  final DateTime createdAt;

  /// Exam focus: the subjects the plan concentrates on (empty otherwise).
  final Set<String> focusSubjectIds;

  PlanResult({
    required this.tasks,
    required this.insights,
    required this.adherence,
    required this.loadFactor,
    required this.engine,
    this.advice,
    this.focusSubjectIds = const {},
  }) : createdAt = DateTime.now();

  int get totalMinutes => tasks.fold(0, (a, t) => a + t.durationMinutes);
}

class RescheduleResult {
  final int moved;
  final int unplaced;
  const RescheduleResult(this.moved, this.unplaced);
}

/// On-device adaptive scheduling engine.
///
/// A weighted multi-criteria priority model (exam urgency, difficulty,
/// remaining workload, observed struggle) combined with a greedy slot
/// allocator and a spaced-repetition session cycle. It adapts to the student
/// by learning from history: subjects with missed tasks or low focus ratings
/// get boosted, and the daily load shrinks when the completion rate drops so
/// plans stay realistic. Runs fully offline.
class SchedulerEngine {
  static const wUrgency = 0.40;
  static const wDifficulty = 0.25;
  static const wWorkload = 0.20;
  static const wStruggle = 0.15;
  static const _dayEndHour = 23;

  /// Light week uses at most this share of the student's free time.
  static const lightLoad = 0.7;

  /// (urgency, difficulty, workload, struggle) weights per planning style.
  static (double, double, double, double) weights(PlanMode mode) => switch (mode) {
        PlanMode.examFocus => (0.65, 0.15, 0.10, 0.10),
        _ => (wUrgency, wDifficulty, wWorkload, wStruggle),
      };

  PlanMode _mode = PlanMode.balanced;
  Set<String> _focus = {};

  /// Exam focus: sessions per week each non-focus subject still gets.
  static const _maintenanceSessions = 2;

  /// Exam focus concentrates on exams in the next 14 days. With none that
  /// close, the 2 nearest exams; with no exam dates, the 2 top priorities.
  static Set<String> focusSubjects(List<SubjectInsight> insights) {
    final dated = insights.where((i) => (i.subject.daysToExam ?? -1) >= 1).toList()
      ..sort((a, b) => a.subject.daysToExam!.compareTo(b.subject.daysToExam!));
    final soon = dated.where((i) => i.subject.daysToExam! <= 14).map((i) => i.subject.id).toSet();
    if (soon.isNotEmpty) return soon;
    if (dated.isNotEmpty) return dated.take(2).map((i) => i.subject.id).toSet();
    return insights.take(2).map((i) => i.subject.id).toSet();
  }

  int _seq = 0;
  String _id() => 'ai_${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  /// Completion rate of tasks that were due in the last 14 days.
  double adherence(List<StudyTask> tasks) {
    final now = DateTime.now();
    final from = now.subtract(const Duration(days: 14));
    final due = tasks.where((t) => t.end.isBefore(now) && t.start.isAfter(from));
    if (due.length < 3) return 1.0;
    final done = due.where((t) => t.isDone).length;
    return done / due.length;
  }

  List<SubjectInsight> analyse(
    List<Subject> subjects,
    List<StudyTask> tasks,
    List<StudySession> sessions, {
    PlanMode mode = PlanMode.balanced,
  }) {
    final (wu, wd, ww, ws) = weights(mode);
    final active = subjects.where((s) => !s.examPassed).toList();
    if (active.isEmpty) return [];

    final remaining = <String, int>{};
    for (final s in active) {
      final studied = sessions
          .where((x) => x.subjectId == s.id)
          .fold<int>(0, (a, x) => a + x.minutes);
      remaining[s.id] = max(s.targetHours * 60 - studied, 60);
    }
    final maxRemaining = remaining.values.fold<int>(1, max);

    final out = <SubjectInsight>[];
    for (final s in active) {
      final days = s.daysToExam ?? 45;
      final urgency = 1 / (1 + max(days, 0) / 7);
      final difficulty = s.difficulty.weight / 3;
      final workload = remaining[s.id]! / maxRemaining;

      final history = tasks.where((t) =>
          t.subjectId == s.id && t.status != TaskStatus.pending);
      final missed = history.where((t) =>
          t.status == TaskStatus.missed || t.status == TaskStatus.skipped).length;
      final missRate = history.isEmpty ? 0.3 : missed / history.length;
      final ratings = sessions
          .where((x) => x.subjectId == s.id && x.focusRating != null)
          .map((x) => x.focusRating!)
          .toList();
      final lowFocus = ratings.isEmpty
          ? 0.3
          : (5 - ratings.reduce((a, b) => a + b) / ratings.length) / 4;
      final struggle = (missRate + lowFocus) / 2;

      final score = wu * urgency + wd * difficulty + ww * workload + ws * struggle;

      out.add(SubjectInsight(
        subject: s,
        urgency: urgency,
        difficulty: difficulty,
        workload: workload,
        struggle: struggle,
        score: score,
        remainingMinutes: remaining[s.id]!,
      ));
    }
    out.sort((a, b) => b.score.compareTo(a.score));
    return out;
  }

  PlanResult generate({
    required List<Subject> subjects,
    required List<StudyTask> existing,
    required List<StudySession> sessions,
    required StudyPreferences prefs,
    String Function(SessionType)? typeLabel,
  }) {
    _mode = prefs.planMode;
    final insights = analyse(subjects, existing, sessions, mode: _mode);
    final adh = adherence(existing);
    // Fewer completions → lighter, more achievable plan (never below 60%).
    var loadFactor = (0.6 + 0.4 * adh).clamp(0.6, 1.0).toDouble();
    if (_mode == PlanMode.light) loadFactor = min(loadFactor, lightLoad);
    // Exam focus is a push: use more of the free time (never above 100%).
    if (_mode == PlanMode.examFocus) loadFactor = min(1.0, loadFactor + 0.15);
    _focus = _mode == PlanMode.examFocus ? focusSubjects(insights) : {};

    final tasks = <StudyTask>[];
    if (insights.isEmpty) {
      return PlanResult(
          tasks: tasks, insights: insights, adherence: adh,
          loadFactor: loadFactor, engine: 'on-device');
    }

    final need = {for (final i in insights) i.subject.id: i.remainingMinutes};
    final planned = {for (final i in insights) i.subject.id: 0};
    final byId = {for (final i in insights) i.subject.id: i};
    final label = typeLabel ?? (t) => t.name;

    // Fixed tasks the plan must work around: manual tasks + already completed.
    final fixed = existing
        .where((t) => !t.aiGenerated || t.status != TaskStatus.pending)
        .toList();

    final now = DateTime.now();
    for (var d = 0; d < prefs.planHorizonDays; d++) {
      final day = dateOnly(now).add(Duration(days: d));
      final fixedToday = fixed
          .where((t) => sameDay(t.start, day) && t.status == TaskStatus.pending)
          .toList();
      final busy = fixedToday.fold<int>(0, (a, t) => a + t.durationMinutes);
      var capacity = (prefs.minutesFor(day) * loadFactor).round() - busy;
      if (capacity < prefs.sessionMinutes * 0.6) continue;

      var cursor = day.add(Duration(hours: prefs.window.startHour));
      if (d == 0) {
        final soon = _roundUp(now.add(const Duration(minutes: 15)));
        if (soon.isAfter(cursor)) cursor = soon;
      }
      // Late at night "today" has no time left — don't spill into tomorrow.
      if (!sameDay(cursor, day)) continue;

      final dayCount = <String, int>{};
      String? last;
      var slot = 0;

      // Day before an exam → open with final revision for that subject.
      final eveOfExam = insights
          .where((i) => i.subject.daysToExam != null &&
              sameDay(i.subject.examDate!, day.add(const Duration(days: 1))))
          .map((i) => i.subject.id)
          .toSet();

      while (capacity >= prefs.sessionMinutes * 0.6) {
        final len = min(prefs.sessionMinutes, capacity);
        final start = _nextFree(cursor, len, [...fixedToday, ...tasks]);
        if (start == null) break;

        final eligible = insights.where((i) {
          final exam = i.subject.examDate;
          return exam == null || dateOnly(exam).isAfter(day);
        }).toList();
        if (eligible.isEmpty) break;

        SubjectInsight pick;
        final eve = eligible.where((i) =>
            eveOfExam.contains(i.subject.id) && (dayCount[i.subject.id] ?? 0) < 2);
        // Exam focus: the first session every third day keeps another subject ticking over.
        final maintenance = _mode == PlanMode.examFocus && slot == 0 && d % 3 == 1
            ? eligible.where((i) =>
                !_focus.contains(i.subject.id) && planned[i.subject.id]! < _maintenanceSessions).toList()
            : <SubjectInsight>[];
        if (eve.isNotEmpty) {
          pick = eve.first;
        } else if (maintenance.isNotEmpty) {
          // Rotate: the subject with the fewest sessions so far, then the higher priority.
          pick = maintenance.reduce((a, b) {
            final pa = planned[a.subject.id]!, pb = planned[b.subject.id]!;
            if (pa != pb) return pa < pb ? a : b;
            return a.score >= b.score ? a : b;
          });
        } else {
          pick = eligible.reduce((a, b) =>
              _dynamicScore(a, need, dayCount, last, slot) >=
                      _dynamicScore(b, need, dayCount, last, slot)
                  ? a
                  : b);
        }

        final sid = pick.subject.id;
        final type = eveOfExam.contains(sid)
            ? SessionType.finalRevision
            : _focus.contains(sid)
                ? _examType(planned[sid]!, pick.subject.daysToExam)
                : _mode == PlanMode.examFocus
                    ? SessionType.review // maintenance
                    : _sessionType(planned[sid]!, pick.subject.daysToExam);

        tasks.add(StudyTask(
          id: _id(),
          subjectId: sid,
          title: '${pick.subject.name} · ${label(type)}',
          type: type,
          start: start,
          durationMinutes: len,
          aiGenerated: true,
        ));

        need[sid] = need[sid]! - len;
        planned[sid] = planned[sid]! + 1;
        dayCount[sid] = (dayCount[sid] ?? 0) + 1;
        byId[sid]!
          ..allocatedMinutes += len
          ..sessions += 1;
        last = sid;
        slot++;
        capacity -= len;
        cursor = start.add(Duration(minutes: len + prefs.breakMinutes));
      }
    }

    tasks.sort((a, b) => a.start.compareTo(b.start));
    return PlanResult(
      tasks: tasks,
      insights: insights,
      adherence: adh,
      loadFactor: loadFactor,
      engine: 'on-device',
      focusSubjectIds: _focus,
    );
  }

  double _dynamicScore(SubjectInsight i, Map<String, int> need,
      Map<String, int> dayCount, String? last, int slot) {
    final id = i.subject.id;
    final needRatio = max(need[id]!, 0) / max(i.remainingMinutes, 1);
    var s = i.score * (0.25 + needRatio);
    final days = i.subject.daysToExam;
    if (_mode == PlanMode.examFocus) {
      // Concentrate on the next exams in longer blocks; others get maintenance only.
      if (_focus.contains(id)) {
        s *= 3.0;
        if (days != null && days <= 7) s *= 1.5;
        s /= 1 + (dayCount[id] ?? 0) * 0.25;
        if (last == id) s *= 0.85;
      } else {
        return 0; // other subjects only get the reserved maintenance sessions
      }
      return s;
    }
    s /= 1 + (dayCount[id] ?? 0) * 0.7; // spread subjects across the day
    if (last == id) s *= 0.3; // interleave — avoid back-to-back repeats
    if (slot < 2) s *= 1 + 0.35 * i.difficulty; // hard subjects at peak energy
    if (days != null && days <= 3) s *= 1.6;
    return s;
  }

  /// Spaced-repetition cycle: learn → practice → review, past papers near exams.
  /// Exam focus: exam-style practice — past papers and active recall.
  SessionType _examType(int n, int? daysToExam) {
    if (daysToExam != null && daysToExam <= 3) {
      return n.isEven ? SessionType.pastPaper : SessionType.review;
    }
    return const [SessionType.review, SessionType.pastPaper, SessionType.practice][n % 3];
  }

  SessionType _sessionType(int n, int? daysToExam) {
    if (daysToExam != null && daysToExam <= 3) {
      return n.isEven ? SessionType.pastPaper : SessionType.review;
    }
    if (daysToExam != null && daysToExam <= 14 && n % 4 == 3) {
      return SessionType.pastPaper;
    }
    return const [SessionType.learn, SessionType.practice, SessionType.review][n % 3];
  }

  /// Moves missed tasks into the earliest free slots that respect the
  /// student's availability and come before the subject's exam.
  RescheduleResult reschedule({
    required List<StudyTask> all,
    required List<Subject> subjects,
    required StudyPreferences prefs,
  }) {
    final missed = all.where((t) => t.status == TaskStatus.missed).toList();
    final subjectById = {for (final s in subjects) s.id: s};
    // Most urgent exams first.
    missed.sort((a, b) {
      final da = subjectById[a.subjectId]?.daysToExam ?? 999;
      final db = subjectById[b.subjectId]?.daysToExam ?? 999;
      return da.compareTo(db);
    });

    var moved = 0, unplaced = 0;
    final now = DateTime.now();
    for (final t in missed) {
      final exam = subjectById[t.subjectId]?.examDate;
      DateTime? slot;
      for (var d = 0; d < 14 && slot == null; d++) {
        final day = dateOnly(now).add(Duration(days: d));
        if (exam != null && !dateOnly(exam).isAfter(day)) break;
        final dayTasks = all
            .where((x) => sameDay(x.start, day) &&
                x.status == TaskStatus.pending && x.id != t.id)
            .toList();
        final used = dayTasks.fold<int>(0, (a, x) => a + x.durationMinutes);
        if (used + t.durationMinutes > prefs.minutesFor(day) + 30) continue;
        var cursor = day.add(Duration(hours: prefs.window.startHour));
        if (d == 0) {
          final soon = _roundUp(now.add(const Duration(minutes: 15)));
          if (soon.isAfter(cursor)) cursor = soon;
        }
        if (!sameDay(cursor, day)) continue;
        slot = _nextFree(cursor, t.durationMinutes, dayTasks, gap: prefs.breakMinutes);
      }
      if (slot == null) {
        unplaced++;
        continue;
      }
      t
        ..start = slot
        ..status = TaskStatus.pending
        ..rescheduleCount += 1;
      moved++;
    }
    return RescheduleResult(moved, unplaced);
  }

  /// First start ≥ [from] where a block of [minutes] fits without overlapping
  /// [taken] and ends before 23:00 the same day.
  DateTime? _nextFree(DateTime from, int minutes, List<StudyTask> taken, {int gap = 0}) {
    var cursor = from;
    final dayEnd = dateOnly(from).add(const Duration(hours: _dayEndHour));
    final sorted = taken.where((t) => sameDay(t.start, from)).toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    for (final t in sorted) {
      final end = cursor.add(Duration(minutes: minutes));
      if (!end.isAfter(t.start) || !cursor.isBefore(t.end.add(Duration(minutes: gap)))) {
        if (!end.isAfter(t.start)) break;
        continue;
      }
      cursor = t.end.add(Duration(minutes: gap));
    }
    if (cursor.add(Duration(minutes: minutes)).isAfter(dayEnd)) return null;
    return cursor;
  }

  DateTime _roundUp(DateTime t) {
    final m = (t.minute / 15).ceil() * 15;
    return DateTime(t.year, t.month, t.day, t.hour).add(Duration(minutes: m));
  }
}
