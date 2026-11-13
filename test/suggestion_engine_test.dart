import 'package:flutter_test/flutter_test.dart';
import 'package:studysync/models/models.dart';
import 'package:studysync/services/suggestion_engine.dart';

// Today at 07:00: Subject.daysToExam counts from the real clock, so tests must too.
final now = () {
  final t = DateTime.now();
  return DateTime(t.year, t.month, t.day, 7);
}();
String t(String en, String si) => en;
String label(SessionType s) => s.name;

Subject subject(String id, {int? examIn, Difficulty d = Difficulty.medium, int target = 20}) => Subject(
      id: id,
      name: 'Subject $id',
      colorValue: 0,
      icon: 'book',
      difficulty: d,
      examDate: examIn == null ? null : now.add(Duration(days: examIn)),
      targetHours: target,
    );

int _n = 0;
StudyTask task(String sid, DateTime start, {int minutes = 50, TaskStatus status = TaskStatus.pending}) =>
    StudyTask(id: 't${_n++}', subjectId: sid, title: 'task', start: start, durationMinutes: minutes, status: status);

DateTime at(int day, int hour, [int minute = 0]) => DateTime(now.year, now.month, now.day + day, hour, minute);

List<Suggestion> run({
  required List<Subject> subjects,
  List<StudyTask> tasks = const [],
  List<StudySession> sessions = const [],
  StudyPreferences? prefs,
  Map<SuggestionType, FeedbackStat> feedback = const {},
  Map<String, DateTime> dismissed = const {},
}) =>
    SuggestionEngine().generate(
      subjects: subjects,
      tasks: tasks,
      sessions: sessions,
      prefs: prefs ?? StudyPreferences(),
      feedback: feedback,
      dismissed: dismissed,
      t: t,
      typeLabel: label,
      at: now,
    );

/// Same logic as AppState.applySuggestion, without storage.
List<StudyTask> apply(List<StudyTask> tasks, Iterable<Suggestion> list) {
  final out = tasks.map((x) => x.copy()).toList();
  for (final s in list) {
    for (final a in s.actions) {
      final i = out.indexWhere((x) => x.id == a.taskId);
      if (a.kind == 'move') out[i].start = a.newStart!;
      if (a.kind == 'split') {
        out[i].durationMinutes = a.newDuration!;
        out.add(out[i].copy()
          ..start = a.splitStart!
          ..durationMinutes = a.splitDuration!);
      }
      if (a.kind == 'add') out.add(a.newTask!);
    }
  }
  return out;
}

bool noOverlaps(List<StudyTask> tasks) {
  final p = tasks.where((x) => x.status == TaskStatus.pending).toList()..sort((a, b) => a.start.compareTo(b.start));
  for (var i = 1; i < p.length; i++) {
    if (p[i].start.isBefore(p[i - 1].end)) return false;
  }
  return true;
}

/// History: strong mornings (09:00, rated 5) and weak evenings (20:00, missed).
(List<StudyTask>, List<StudySession>) history(String sid) {
  final tasks = <StudyTask>[], sessions = <StudySession>[];
  for (var d = 1; d <= 8; d++) {
    final good = task(sid, at(-d, 9), status: TaskStatus.completed);
    tasks
      ..add(good)
      ..add(task(sid, at(-d, 20), status: TaskStatus.missed));
    sessions.add(StudySession(id: 's$d', subjectId: sid, taskId: good.id, start: good.start, minutes: 50, focusRating: 5));
  }
  return (tasks, sessions);
}

void main() {
  test('close exam with little planned → adds revision before the exam', () {
    final s = subject('a', examIn: 5);
    final out = run(subjects: [s]);
    final cov = out.where((x) => x.type == SuggestionType.examCoverage).toList();
    expect(cov, hasLength(1));
    final added = cov.first.actions.map((a) => a.newTask!).toList();
    expect(added, hasLength(2));
    for (final x in added) {
      expect(x.start.isAfter(now), isTrue);
      expect(x.start.isBefore(dateOnly(s.examDate!)), isTrue);
    }
    expect(noOverlaps(added), isTrue);
  });

  test('overbooked day → moves a session to a lighter day', () {
    final s = subject('a', examIn: 20);
    final tasks = [task('a', at(1, 8), minutes: 90), task('a', at(1, 10), minutes: 90), task('a', at(1, 12), minutes: 90)];
    final out = run(subjects: [s], tasks: tasks, prefs: StudyPreferences(availability: List.filled(7, 120)));
    final r = out.where((x) => x.type == SuggestionType.rebalanceDay).toList();
    expect(r, isNotEmpty);
    expect(sameDay(r.first.actions.first.newStart!, at(1, 0)), isFalse);
  });

  test('learns best hours and moves important work there', () {
    final (hist, sessions) = history('a');
    final s = subject('a', examIn: 9, d: Difficulty.hard);
    final evening = task('a', at(1, 20));
    final out = run(subjects: [s], tasks: [...hist, evening], sessions: sessions);
    final peak = out.where((x) => x.type == SuggestionType.moveToPeak).toList();
    expect(peak, hasLength(1));
    expect(peak.first.actions.first.taskId, evening.id);
    expect(peak.first.actions.first.newStart!.hour, 9);
  });

  test('learns real focus span → splits long sessions and suggests shorter ones', () {
    final s = subject('a', examIn: 30);
    final sessions = [
      for (var i = 1; i <= 5; i++)
        StudySession(id: 'f$i', subjectId: 'a', start: at(-i, 9), minutes: 30, focusRating: 4),
    ];
    final long = task('a', at(1, 8), minutes: 120);
    final out = run(subjects: [s], tasks: [long], sessions: sessions);
    final split = out.firstWhere((x) => x.type == SuggestionType.splitLong);
    expect(split.actions.first.newDuration, 30);
    expect(split.actions.first.splitDuration, 90);
    expect(noOverlaps(apply([long], [split])), isTrue);
    final shorter = out.firstWhere((x) => x.type == SuggestionType.shorterSessions);
    expect(shorter.actions.first.sessionMinutes, 25);
  });

  test('learns better time of day from history', () {
    final (hist, sessions) = history('a');
    final out = run(subjects: [subject('a')], tasks: hist, sessions: sessions,
        prefs: StudyPreferences(window: StudyWindow.night));
    final w = out.firstWhere((x) => x.type == SuggestionType.betterWindow);
    expect(w.actions.first.window, StudyWindow.morning);
  });

  test('suggestions never collide with each other or the plan', () {
    final (hist, sessions) = history('a');
    final subjects = [subject('a', examIn: 4, d: Difficulty.hard), subject('b', examIn: 6)];
    final plan = [for (var d = 0; d < 4; d++) task('a', at(d, 20)), task('b', at(1, 8), minutes: 120)];
    final out = run(subjects: subjects, tasks: [...hist, ...plan], sessions: sessions);
    expect(out.length, greaterThan(2));
    expect(noOverlaps(apply(plan, out)), isTrue);
  });

  test('dismissed suggestion stays hidden for a week', () {
    final s = subject('a', examIn: 5);
    final first = run(subjects: [s]).first;
    final again = run(subjects: [s], dismissed: {first.id: now.subtract(const Duration(days: 1))});
    expect(again.any((x) => x.id == first.id), isFalse);
  });

  test('learns from feedback: rejected types are hidden, accepted types rank higher', () {
    final s = subject('a', examIn: 5);
    expect(run(subjects: [s], feedback: {SuggestionType.examCoverage: FeedbackStat(0, 3)}), isEmpty);

    final (hist, sessions) = history('a');
    final both = [subject('a', examIn: 9, d: Difficulty.hard), subject('b', examIn: 5)];
    final tasks = [...hist, task('a', at(1, 20))];
    final liked = run(subjects: both, tasks: tasks, sessions: sessions,
        feedback: {SuggestionType.moveToPeak: FeedbackStat(8, 0), SuggestionType.examCoverage: FeedbackStat(1, 2)});
    expect(liked.first.type, SuggestionType.moveToPeak);
  });

  test('split never pushes a day past its free time', () {
    final s = subject('a', examIn: 30);
    final sessions = [
      for (var i = 1; i <= 5; i++) StudySession(id: 'f$i', subjectId: 'a', start: at(-i, 9), minutes: 40, focusRating: 4),
    ];
    final prefs = StudyPreferences(availability: List.filled(7, 180));
    final long = task('a', at(1, 8), minutes: 120);
    final filler = task('a', at(1, 11), minutes: 50);
    final out = run(subjects: [s], tasks: [long, filler], sessions: sessions, prefs: prefs);
    final split = out.firstWhere((x) => x.type == SuggestionType.splitLong);
    final after = apply([long, filler], [split]);
    for (var d = 0; d < 8; d++) {
      final used = after.where((x) => sameDay(x.start, at(d, 0))).fold<int>(0, (a, x) => a + x.durationMinutes);
      expect(used, lessThanOrEqualTo(180));
    }
    expect(noOverlaps(after), isTrue);
  });
}
