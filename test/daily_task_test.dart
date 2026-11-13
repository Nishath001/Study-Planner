import 'package:flutter_test/flutter_test.dart';
import 'package:studysync/models/models.dart';

void main() {
  final mon = DateTime(2026, 10, 12); // Monday
  DateTime day(int i) => mon.add(Duration(days: i));
  DailyTask task({Repeat repeat = Repeat.none, DateTime? date}) =>
      DailyTask(id: 'x', title: 'x', date: date ?? mon, repeat: repeat);

  test('one-off task occurs only on its day', () {
    final t = task();
    expect(t.occursOn(mon), isTrue);
    expect(t.occursOn(day(1)), isFalse);
    expect(t.occursOn(day(-1)), isFalse);
  });

  test('repeat rules', () {
    expect([for (var i = 0; i < 7; i++) task(repeat: Repeat.daily).occursOn(day(i))], everyElement(isTrue));
    final weekdays = [for (var i = 0; i < 7; i++) task(repeat: Repeat.weekdays).occursOn(day(i))];
    expect(weekdays, [true, true, true, true, true, false, false]);
    final weekly = task(repeat: Repeat.weekly);
    expect(weekly.occursOn(day(7)), isTrue);
    expect(weekly.occursOn(day(3)), isFalse);
    expect(task(repeat: Repeat.daily).occursOn(day(-1)), isFalse, reason: 'never before its start day');
  });

  test('repeating task completion is tracked per day', () {
    final t = task(repeat: Repeat.daily)..doneDates.add(dayKey(mon));
    expect(t.doneOn(mon), isTrue);
    expect(t.doneOn(day(1)), isFalse);
  });

  test('overdue only for unfinished one-off tasks from earlier days', () {
    final today = day(2);
    expect(task().isOverdue(today), isTrue);
    expect((task()..doneDates.add(dayKey(mon))).isOverdue(today), isFalse);
    expect(task(repeat: Repeat.daily).isOverdue(today), isFalse);
    expect(task(date: today).isOverdue(today), isFalse);
  });

  test('due time and JSON round trip', () {
    final t = DailyTask(
      id: 'a',
      title: 'Lab report',
      date: mon,
      dueMinutes: 17 * 60 + 30,
      priority: TaskPriority.high,
      category: TaskCategory.assignment,
      repeat: Repeat.weekly,
      subtasks: [SubTask('Write intro', {dayKey(mon)}), SubTask('References')],
    );
    expect(t.dueOn(mon), DateTime(2026, 10, 12, 17, 30));
    final c = DailyTask.fromJson(t.toJson());
    expect(c.priority, TaskPriority.high);
    expect(c.category, TaskCategory.assignment);
    expect(c.repeat, Repeat.weekly);
    expect(c.subtasksDoneOn(mon), 1);
    expect(c.dueMinutes, 17 * 60 + 30);
  });
}
