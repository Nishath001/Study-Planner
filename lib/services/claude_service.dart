import 'package:cloud_functions/cloud_functions.dart';

import '../models/models.dart';
import 'scheduler_engine.dart';

/// Claude AI planning through the Firebase Cloud Function `generateStudyPlan`.
///
/// The app never holds an Anthropic API key: it sends the plan inputs to the
/// function (signed-in Firebase users only), the function asks Claude and
/// returns a checked timetable. See functions/index.js.
class ClaudeService {
  ClaudeService._();
  static final instance = ClaudeService._();

  /// Same region as the Firestore database and the deployed function.
  static const region = 'asia-south1';

  HttpsCallable get _call => FirebaseFunctions.instanceFor(region: region).httpsCallable(
        'generateStudyPlan',
        options: HttpsCallableOptions(timeout: const Duration(minutes: 3)),
      );

  /// Builds the request sent to the function. Public so it can be tested.
  static Map<String, dynamic> buildRequest({
    required DateTime now,
    required List<SubjectInsight> insights,
    required List<StudyTask> keep,
    required StudyPreferences prefs,
    required double adherence,
    required double loadFactor,
    required String language,
  }) {
    final today = dateOnly(now);
    final days = List.generate(prefs.planHorizonDays, (d) {
      final day = today.add(Duration(days: d));
      var startMinute = prefs.window.startHour * 60;
      if (d == 0) {
        // Not earlier than 15 minutes from now, rounded up to 5 minutes.
        final soon = now.hour * 60 + now.minute + 15;
        startMinute = startMinute > soon ? startMinute : ((soon + 4) ~/ 5) * 5;
      }
      final busy = [
        for (final t in keep.where((t) => sameDay(t.start, day) && t.status != TaskStatus.skipped))
          [t.start.hour * 60 + t.start.minute, (t.start.hour * 60 + t.start.minute + t.durationMinutes).clamp(0, 1440)],
      ];
      return {
        'weekday': const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][day.weekday - 1],
        'startMinute': startMinute.clamp(0, 1440),
        'minutes': (prefs.minutesFor(day) * loadFactor).round().clamp(0, 960),
        'busy': busy,
      };
    });
    return {
      'language': language,
      'mode': prefs.planMode.name,
      'sessionMinutes': prefs.sessionMinutes.clamp(15, 180),
      'breakMinutes': prefs.breakMinutes.clamp(0, 60),
      'adherence': adherence,
      'days': days,
      'subjects': [
        for (final i in insights.take(30))
          {
            'id': i.subject.id,
            'name': i.subject.name,
            'difficulty': i.subject.difficulty.name,
            'daysToExam': i.subject.daysToExam,
            'remainingMinutes': i.remainingMinutes,
            'priority': i.score,
          }
      ],
    };
  }

  /// Turns the function's reply into study tasks. Public so it can be tested.
  static PlanResult parseReply({
    required Map<String, dynamic> data,
    required DateTime now,
    required List<SubjectInsight> insights,
    required double adherence,
    required double loadFactor,
    required String Function(SessionType) typeLabel,
  }) {
    final byId = {for (final i in insights) i.subject.id: i..allocatedMinutes = 0..sessions = 0};
    final tasks = <StudyTask>[];
    var n = 0;
    for (final raw in (data['sessions'] as List? ?? const [])) {
      final s = Map<String, dynamic>.from(raw as Map);
      final insight = byId[s['subjectId']];
      if (insight == null) continue;
      final start = dateOnly(now).add(Duration(
        days: (s['day'] as num).toInt(),
        hours: (s['startHour'] as num).toInt(),
        minutes: (s['startMinute'] as num? ?? 0).toInt(),
      ));
      if (start.isBefore(now)) continue;
      final type = SessionType.values.firstWhere((t) => t.name == s['type'], orElse: () => SessionType.learn);
      final minutes = (s['minutes'] as num).toInt().clamp(15, 180);
      tasks.add(StudyTask(
        id: 'claude_${now.millisecondsSinceEpoch}_${n++}',
        subjectId: insight.subject.id,
        title: '${insight.subject.name} · ${typeLabel(type)}',
        type: type,
        start: start,
        durationMinutes: minutes,
        aiGenerated: true,
      ));
      insight
        ..allocatedMinutes += minutes
        ..sessions += 1;
    }
    tasks.sort((a, b) => a.start.compareTo(b.start));
    final advice = (data['advice'] as String?)?.trim();
    return PlanResult(
      tasks: tasks,
      insights: insights,
      adherence: adherence,
      loadFactor: loadFactor,
      engine: 'claude',
      advice: advice == null || advice.isEmpty ? null : advice,
    );
  }

  Future<PlanResult> generate({
    required List<SubjectInsight> insights,
    required List<StudyTask> keep,
    required StudyPreferences prefs,
    required double adherence,
    required double loadFactor,
    required String language,
    required String Function(SessionType) typeLabel,
  }) async {
    final now = DateTime.now();
    final res = await _call.call<dynamic>(buildRequest(
      now: now,
      insights: insights,
      keep: keep,
      prefs: prefs,
      adherence: adherence,
      loadFactor: loadFactor,
      language: language,
    ));
    final plan = parseReply(
      data: Map<String, dynamic>.from(res.data as Map),
      now: now,
      insights: insights,
      adherence: adherence,
      loadFactor: loadFactor,
      typeLabel: typeLabel,
    );
    if (plan.tasks.isEmpty) throw Exception('Claude returned an empty plan');
    return plan;
  }
}
