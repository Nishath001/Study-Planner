import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'scheduler_engine.dart';

/// Optional cloud planner. When the student adds an Anthropic API key in
/// Settings, Claude builds the timetable from the same inputs the on-device
/// engine uses; otherwise the on-device engine is used.
class ClaudeService {
  ClaudeService._();
  static final instance = ClaudeService._();

  static const _endpoint = 'https://api.anthropic.com/v1/messages';
  static const _model = 'claude-sonnet-5-5';

  Future<PlanResult> generate({
    required String apiKey,
    required List<SubjectInsight> insights,
    required StudyPreferences prefs,
    required double adherence,
    required double loadFactor,
    required String language,
    required String Function(SessionType) typeLabel,
  }) async {
    final now = DateTime.now();
    final days = List.generate(prefs.planHorizonDays, (d) {
      final day = dateOnly(now).add(Duration(days: d));
      return '{"day":$d,"weekday":"${_weekday(day)}","minutes":${(prefs.minutesFor(day) * loadFactor).round()}}';
    }).join(',');
    final subjects = insights
        .map((i) => '{"id":"${i.subject.id}","name":${jsonEncode(i.subject.name)},'
            '"difficulty":"${i.subject.difficulty.name}",'
            '"daysToExam":${i.subject.daysToExam},'
            '"remainingMinutes":${i.remainingMinutes},'
            '"priority":${i.score.toStringAsFixed(2)}}')
        .join(',');

    final prompt = '''
Build a ${prefs.planHorizonDays}-day study timetable for a Sri Lankan university student.
Current time: ${now.toIso8601String()}. Do not schedule anything earlier than now.
Preferred start hour: ${prefs.window.startHour}:00. Session length: ${prefs.sessionMinutes} min, break: ${prefs.breakMinutes} min. Nothing after 23:00.
Available minutes per day (never exceed): [$days]
Subjects (with pre-computed priority): [$subjects]
Rules: never schedule a subject on or after its exam day; the day before an exam is final revision for that subject; interleave subjects; hard subjects early in the day; follow spaced repetition (learn → practice → review, past papers close to exams).
Reply with JSON only, no prose:
{"advice":"one encouraging sentence in ${language == 'SI' ? 'Sinhala' : 'English'}","sessions":[{"day":0,"subjectId":"id","startHour":8,"startMinute":0,"minutes":50,"type":"learn|practice|review|pastPaper|finalRevision"}]}''';

    final res = await http
        .post(
          Uri.parse(_endpoint),
          headers: {
            'content-type': 'application/json',
            'x-api-key': apiKey,
            'anthropic-version': '2023-06-01',
            'anthropic-dangerous-direct-browser-access': 'true',
          },
          body: jsonEncode({
            'model': _model,
            'max_tokens': 8000,
            'messages': [
              {'role': 'user', 'content': prompt}
            ],
          }),
        )
        .timeout(const Duration(seconds: 90));

    if (res.statusCode != 200) {
      throw Exception('Claude API ${res.statusCode}');
    }
    final body = jsonDecode(utf8.decode(res.bodyBytes)) as Map<String, dynamic>;
    final text = (body['content'] as List)
        .where((c) => c['type'] == 'text')
        .map((c) => c['text'] as String)
        .join();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) throw Exception('Unexpected response');
    final data = jsonDecode(text.substring(start, end + 1)) as Map<String, dynamic>;

    final byId = {for (final i in insights) i.subject.id: i};
    final tasks = <StudyTask>[];
    var n = 0;
    for (final raw in (data['sessions'] as List? ?? [])) {
      final s = Map<String, dynamic>.from(raw);
      final insight = byId[s['subjectId']];
      if (insight == null) continue;
      final day = dateOnly(now).add(Duration(days: (s['day'] as num).toInt()));
      final start = day.add(Duration(
          hours: (s['startHour'] as num).toInt(),
          minutes: (s['startMinute'] as num? ?? 0).toInt()));
      if (start.isBefore(now)) continue;
      final type = SessionType.values.firstWhere((t) => t.name == s['type'],
          orElse: () => SessionType.learn);
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
    if (tasks.isEmpty) throw Exception('Empty plan');
    tasks.sort((a, b) => a.start.compareTo(b.start));
    return PlanResult(
      tasks: tasks,
      insights: insights,
      adherence: adherence,
      loadFactor: loadFactor,
      engine: 'claude',
      advice: data['advice'] as String?,
    );
  }

  String _weekday(DateTime d) =>
      const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][d.weekday - 1];
}
