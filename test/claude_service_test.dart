import 'package:flutter_test/flutter_test.dart';
import 'package:studysync/models/models.dart';
import 'package:studysync/services/claude_service.dart';
import 'package:studysync/services/scheduler_engine.dart';

/// Request/response handling for the Claude Cloud Function (no network).
void main() {
  final now = DateTime(2026, 11, 16, 9, 7); // Monday 09:07
  final subject = Subject(
    id: 'net',
    name: 'Networks',
    colorValue: 0,
    icon: 'book',
    difficulty: Difficulty.hard,
    examDate: DateTime(2026, 11, 20),
  );
  SubjectInsight insight() => SubjectInsight(
        subject: subject,
        urgency: 0.8,
        difficulty: 1,
        workload: 0.5,
        struggle: 0,
        score: 0.77,
        remainingMinutes: 600,
      );

  test('request carries free time, busy slots, style and subjects', () {
    final prefs = StudyPreferences(planHorizonDays: 3, planMode: PlanMode.examFocus);
    final keep = [
      StudyTask(
        id: 'm',
        subjectId: 'net',
        title: 'Manual',
        type: SessionType.review,
        start: DateTime(2026, 11, 17, 7, 0),
        durationMinutes: 45,
      ),
    ];
    final req = ClaudeService.buildRequest(
      now: now,
      insights: [insight()],
      keep: keep,
      prefs: prefs,
      adherence: 0.9,
      loadFactor: 0.5,
      language: 'SI',
    );
    final days = req['days'] as List;
    expect(days, hasLength(3));
    expect(days[0]['weekday'], 'Mon');
    expect(days[0]['startMinute'], 9 * 60 + 25, reason: 'today starts 15+ min from now, rounded to 5');
    expect(days[1]['startMinute'], 6 * 60, reason: 'later days start at the preferred window');
    expect(days[0]['minutes'], 90, reason: 'Monday 180 min × load 0.5');
    expect(days[1]['busy'], [
      [420, 465]
    ]);
    expect(req['mode'], 'examFocus');
    expect(req['language'], 'SI');
    final s = (req['subjects'] as List).single;
    expect(s['id'], 'net');
    expect(s['daysToExam'], isNotNull);
  });

  test('reply becomes AI tasks; past and unknown sessions are dropped', () {
    final plan = ClaudeService.parseReply(
      data: {
        'advice': 'Focus on Networks first.',
        'sessions': [
          {'day': 1, 'subjectId': 'net', 'startHour': 8, 'startMinute': 0, 'minutes': 50, 'type': 'pastPaper'},
          {'day': 0, 'subjectId': 'net', 'startHour': 8, 'startMinute': 0, 'minutes': 50, 'type': 'learn'}, // past
          {'day': 0, 'subjectId': 'zzz', 'startHour': 12, 'startMinute': 0, 'minutes': 50, 'type': 'learn'},
          {'day': 0, 'subjectId': 'net', 'startHour': 18, 'startMinute': 30, 'minutes': 40, 'type': 'review'},
        ],
      },
      now: now,
      insights: [insight()],
      adherence: 1,
      loadFactor: 1,
      typeLabel: (t) => t.name,
    );
    expect(plan.engine, 'claude');
    expect(plan.advice, 'Focus on Networks first.');
    expect(plan.tasks.map((t) => t.start), [DateTime(2026, 11, 16, 18, 30), DateTime(2026, 11, 17, 8, 0)]);
    expect(plan.tasks.every((t) => t.aiGenerated), isTrue);
    expect(plan.tasks.last.type, SessionType.pastPaper);
    expect(plan.insights.single.allocatedMinutes, 90);
  });
}
