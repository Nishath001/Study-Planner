import 'package:flutter_test/flutter_test.dart';
import 'package:studysync/models/models.dart';
import 'package:studysync/services/plan_email_service.dart';
import 'package:studysync/services/scheduler_engine.dart';

void main() {
  test('email request lists sessions in time order with subject names', () {
    StudyTask task(String id, DateTime start, SessionType type) =>
        StudyTask(id: id, subjectId: 'net', title: 'x', start: start, durationMinutes: 50, type: type, aiGenerated: true);
    final plan = PlanResult(
      tasks: [
        task('b', DateTime(2026, 11, 17, 9, 5), SessionType.practice),
        task('a', DateTime(2026, 11, 16, 8, 0), SessionType.learn),
      ],
      insights: const [],
      adherence: 1,
      loadFactor: 1,
      engine: 'claude',
      advice: 'Keep going',
    );
    final req = PlanEmailService.buildRequest(
      plan: plan,
      subjects: [Subject(id: 'net', name: 'Networks', colorValue: 0, icon: 'book')],
      name: 'Nimal',
      language: 'EN',
      typeLabel: (t) => t.name,
    );
    expect(req['engine'], 'claude');
    expect(req['advice'], 'Keep going');
    final s = req['sessions'] as List;
    expect(s.first, {'date': '2026-11-16', 'start': '08:00', 'minutes': 50, 'subject': 'Networks', 'type': 'learn'});
    expect(s.last['start'], '09:05');
  });

  test('email body groups by day, escapes names and totals time', () {
    final mail = PlanEmailService.buildEmail({
      'language': 'EN',
      'name': 'Nimal',
      'advice': 'Start with Networks.',
      'engine': 'on-device',
      'sessions': [
        {'date': '2026-11-17', 'start': '09:00', 'minutes': 50, 'subject': 'Databases', 'type': 'Practice'},
        {'date': '2026-11-16', 'start': '08:00', 'minutes': 40, 'subject': '<b>Nets</b>', 'type': 'Learn'},
      ],
    });
    expect(mail.subject, 'Your StudySync study plan · 2 sessions');
    expect(mail.html, contains('2 sessions · 1h 30m of study'));
    expect(mail.html, isNot(contains('<b>Nets</b>')));
    expect(mail.html.indexOf('Monday 16 November'), lessThan(mail.html.indexOf('Tuesday 17 November')));
    expect(mail.text, contains('Hi Nimal,'));
  });
}
