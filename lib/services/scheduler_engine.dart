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

  PlanResult({
    required this.tasks,
    required this.insights,
    required this.adherence,
    required this.loadFactor,
    required this.engine,
    this.advice,
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
    List<StudySession> sessions,
  ) {
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

      final score = wUrgency * urgency +
          wDifficulty * difficulty +
          wWorkload * workload +
          wStruggle * struggle;

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
    final insights = analyse(subjects, existing, sessions);
    final adh = adherence(existing);
    // Fewer completions → lighter, more achievable plan (never below 60%).
    final loadFactor = (0.6 + 0.4 * adh).clamp(0.6, 1.0);

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
        if (eve.isNotEmpty) {
          pick = eve.first;
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
    );
  }

  double _dynamicScore(SubjectInsight i, Map<String, int> need,
      Map<String, int> dayCount, String? last, int slot) {
    final id = i.subject.id;
    final needRatio = max(need[id]!, 0) / max(i.remainingMinutes, 1);
    var s = i.score * (0.25 + needRatio);
    s /= 1 + (dayCount[id] ?? 0) * 0.7; // spread subjects across the day
    if (last == id) s *= 0.3; // interleave — avoid back-to-back repeats
    if (slot < 2) s *= 1 + 0.35 * i.difficulty; // hard subjects at peak energy
    final days = i.subject.daysToExam;
    if (days != null && days <= 3) s *= 1.6;
    return s;
  }

  /// Spaced-repetition cycle: learn → practice → review, past papers near exams.
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
