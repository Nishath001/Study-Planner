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
}
