import 'package:flutter_test/flutter_test.dart';
import 'package:studysync/models/models.dart';
import 'package:studysync/services/scheduler_engine.dart';

void main() {
  final now = DateTime.now();
  final engine = SchedulerEngine();

  List<Subject> subjects() => [
        Subject(id: 'a', name: 'Networks', colorValue: 0, icon: 'network',
            difficulty: Difficulty.hard, examDate: now.add(const Duration(days: 3)), targetHours: 20),
        Subject(id: 'b', name: 'Databases', colorValue: 0, icon: 'db',
            difficulty: Difficulty.easy, examDate: now.add(const Duration(days: 20)), targetHours: 20),
        Subject(id: 'c', name: 'Maths', colorValue: 0, icon: 'math', difficulty: Difficulty.medium),
      ];

  test('ranks the near, hard exam first', () {
    final insights = engine.analyse(subjects(), [], []);
    expect(insights.first.subject.id, 'a');
  });

  test('never exceeds daily availability', () {
    final prefs = StudyPreferences(availability: [120, 120, 120, 120, 120, 240, 0]);
    final plan = engine.generate(subjects: subjects(), existing: [], sessions: [], prefs: prefs);
    expect(plan.tasks, isNotEmpty);
    for (var d = 0; d < 7; d++) {
      final day = dateOnly(now).add(Duration(days: d));
      final used = plan.tasks.where((t) => sameDay(t.start, day)).fold<int>(0, (a, t) => a + t.durationMinutes);
      expect(used, lessThanOrEqualTo(prefs.minutesFor(day)));
    }
  });

  test('no sessions on or after a subject exam day, none overlapping', () {
    final s = subjects();
    final plan = engine.generate(subjects: s, existing: [], sessions: [], prefs: StudyPreferences());
    final examA = dateOnly(s.first.examDate!);
    for (final t in plan.tasks.where((t) => t.subjectId == 'a')) {
      expect(dateOnly(t.start).isBefore(examA), isTrue);
    }
    final sorted = [...plan.tasks]..sort((x, y) => x.start.compareTo(y.start));
    for (var i = 1; i < sorted.length; i++) {
      expect(sorted[i].start.isBefore(sorted[i - 1].end), isFalse);
    }
    expect(plan.tasks.every((t) => t.start.isAfter(now)), isTrue);
  });

  test('lower follow-through shrinks the plan', () {
    final history = List.generate(6, (i) => StudyTask(
          id: 'h$i',
          subjectId: 'b',
          title: 'old',
          start: now.subtract(Duration(days: i + 1, hours: 2)),
          durationMinutes: 50,
          aiGenerated: true,
          status: i == 0 ? TaskStatus.completed : TaskStatus.missed,
        ));
    final full = engine.generate(subjects: subjects(), existing: [], sessions: [], prefs: StudyPreferences());
    final light = engine.generate(subjects: subjects(), existing: history, sessions: [], prefs: StudyPreferences());
    expect(light.loadFactor, lessThan(1));
    expect(light.totalMinutes, lessThan(full.totalMinutes));
  });

  test('reschedules missed sessions into the future', () {
    final missed = StudyTask(
      id: 'm',
      subjectId: 'b',
      title: 'missed',
      start: now.subtract(const Duration(hours: 5)),
      durationMinutes: 50,
      status: TaskStatus.missed,
    );
    final r = engine.reschedule(all: [missed], subjects: subjects(), prefs: StudyPreferences());
    expect(r.moved, 1);
    expect(missed.status, TaskStatus.pending);
    expect(missed.start.isAfter(now), isTrue);
    expect(missed.rescheduleCount, 1);
  });

  test('light week uses at most 70% of free time', () {
    final balanced = engine.generate(subjects: subjects(), existing: [], sessions: [], prefs: StudyPreferences());
    final light = engine.generate(
        subjects: subjects(), existing: [], sessions: [], prefs: StudyPreferences(planMode: PlanMode.light));
    expect(light.loadFactor, lessThanOrEqualTo(SchedulerEngine.lightLoad));
    expect(light.totalMinutes, lessThan(balanced.totalMinutes));
    for (var d = 1; d < 7; d++) {
      final day = dateOnly(now).add(Duration(days: d));
      final used = light.tasks.where((t) => sameDay(t.start, day)).fold<int>(0, (a, t) => a + t.durationMinutes);
      expect(used, lessThanOrEqualTo(StudyPreferences().minutesFor(day) * SchedulerEngine.lightLoad + 1));
    }
  });

  test('exam focus gives the nearest exam more time', () {
    // Make the near exam the EASY subject, so only exam focus favours it strongly.
    final subs = [
      Subject(id: 'near', name: 'Near', colorValue: 0, icon: 'book', difficulty: Difficulty.easy,
          examDate: now.add(const Duration(days: 6)), targetHours: 30),
      Subject(id: 'far', name: 'Far', colorValue: 0, icon: 'book', difficulty: Difficulty.hard,
          examDate: now.add(const Duration(days: 30)), targetHours: 30),
    ];
    int nearMinutes(PlanResult p) =>
        p.tasks.where((t) => t.subjectId == 'near').fold(0, (a, t) => a + t.durationMinutes);
    final balanced = engine.generate(subjects: subs, existing: [], sessions: [], prefs: StudyPreferences());
    final focus = engine.generate(
        subjects: subs, existing: [], sessions: [], prefs: StudyPreferences(planMode: PlanMode.examFocus));
    expect(nearMinutes(focus), greaterThan(nearMinutes(balanced)));
  });

  test('planning style is saved with preferences', () {
    final p = StudyPreferences.fromJson(StudyPreferences(planMode: PlanMode.examFocus).toJson());
    expect(p.planMode, PlanMode.examFocus);
    expect(StudyPreferences.fromJson({}).planMode, PlanMode.balanced);
  });

  group('exam focus is a different strategy from balanced', () {
    List<Subject> four(List<int?> exams) => [
          for (final (i, n) in ['MC', 'CN', 'DS', 'SE'].indexed)
            Subject(id: n, name: n, colorValue: 0, icon: 'book',
                difficulty: [Difficulty.hard, Difficulty.medium, Difficulty.hard, Difficulty.easy][i],
                examDate: exams[i] == null ? null : now.add(Duration(days: exams[i]!)), targetHours: 25),
        ];
    Map<String, int> split(PlanResult r) {
      final m = <String, int>{};
      for (final t in r.tasks) {
        m[t.subjectId] = (m[t.subjectId] ?? 0) + t.durationMinutes;
      }
      return m;
    }

    for (final (label, exams, expectedFocus) in [
      ('exams soon', [12, 19, 6, 26], {'DS', 'MC'}),
      ('no exam within 2 weeks', [20, 15, 30, 40], {'CN', 'MC'}),
      ('no exam dates', [null, null, null, null], null),
    ]) {
      test(label, () {
        final subs = four(exams);
        final bal = engine.generate(subjects: subs, existing: [], sessions: [], prefs: StudyPreferences());
        final foc = engine.generate(
            subjects: subs, existing: [], sessions: [], prefs: StudyPreferences(planMode: PlanMode.examFocus));
        if (expectedFocus != null) expect(foc.focusSubjectIds, expectedFocus);
        expect(foc.focusSubjectIds, hasLength(2));

        final focMins = split(foc), total = foc.totalMinutes;
        final focusShare = foc.focusSubjectIds.fold<int>(0, (a, id) => a + (focMins[id] ?? 0)) / total;
        final balShare = foc.focusSubjectIds.fold<int>(0, (a, id) => a + (split(bal)[id] ?? 0)) / bal.totalMinutes;
        expect(focusShare, greaterThan(0.8));
        expect(focusShare, greaterThan(balShare + 0.25), reason: 'clearly more concentrated than Balanced');

        // Other subjects keep a short maintenance review, never more than 2 sessions.
        for (final t in foc.tasks.where((t) => !foc.focusSubjectIds.contains(t.subjectId))) {
          expect(t.type, SessionType.review);
        }
        for (final id in subs.map((s) => s.id).where((id) => !foc.focusSubjectIds.contains(id))) {
          expect(foc.tasks.where((t) => t.subjectId == id).length, lessThanOrEqualTo(2));
        }
        // Exam-style sessions: no new-concept study for the focus subjects.
        expect(foc.tasks.where((t) => foc.focusSubjectIds.contains(t.subjectId) && t.type == SessionType.learn), isEmpty);
        expect(bal.tasks.where((t) => t.type == SessionType.learn), isNotEmpty);
      });
    }
  });
}
