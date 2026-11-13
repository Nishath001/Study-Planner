import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

import '../models/models.dart';
import 'email_config.dart';
import 'scheduler_engine.dart';

class PlanEmailException implements Exception {
  final String message;
  PlanEmailException(this.message);
  @override
  String toString() => message;
}

/// Emails a study plan to the student's registered address.
///
/// Uses EmailJS straight from the app when [EmailConfig] is filled in (free,
/// works on the Firebase Spark plan); otherwise the Cloud Function
/// `emailStudyPlan` (needs the Blaze plan, see functions/index.js).
class PlanEmailService {
  PlanEmailService._();
  static final instance = PlanEmailService._();

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// The plan as plain data. Public so it can be tested.
  static Map<String, dynamic> buildRequest({
    required PlanResult plan,
    required List<Subject> subjects,
    required String name,
    required String language,
    required String Function(SessionType) typeLabel,
  }) {
    final names = {for (final s in subjects) s.id: s.name};
    final tasks = [...plan.tasks]..sort((a, b) => a.start.compareTo(b.start));
    return {
      'language': language,
      'name': name,
      'advice': plan.advice ?? '',
      'engine': plan.engine == 'claude' ? 'claude' : 'on-device',
      'sessions': [
        for (final t in tasks.take(200))
          {
            'date': '${t.start.year}-${_two(t.start.month)}-${_two(t.start.day)}',
            'start': '${_two(t.start.hour)}:${_two(t.start.minute)}',
            'minutes': t.durationMinutes,
            'subject': names[t.subjectId] ?? t.title,
            'type': typeLabel(t.type),
          }
      ],
    };
  }

  static String _esc(Object? s) => const HtmlEscape().convert('${s ?? ''}');

  static String _hours(int m) => m % 60 == 0 ? '${m ~/ 60}h' : '${m ~/ 60}h ${m % 60}m';

  /// Subject line, HTML body and plain-text body. Public so it can be tested.
  static ({String subject, String html, String text}) buildEmail(Map<String, dynamic> req) {
    final si = req['language'] == 'SI';
    final name = '${req['name'] ?? ''}'.trim();
    final advice = '${req['advice'] ?? ''}'.trim();
    final claude = req['engine'] == 'claude';
    final sessions = [for (final s in req['sessions'] as List) Map<String, dynamic>.from(s as Map)];
    final total = sessions.fold<int>(0, (a, s) => a + (s['minutes'] as int));
    final n = sessions.length;

    final subject = si ? 'ඔබේ StudySync අධ්‍යයන සැලැස්ම · සැසි $n' : 'Your StudySync study plan · $n sessions';
    final hello = si ? (name.isEmpty ? 'ආයුබෝවන්,' : 'ආයුබෝවන් $name,') : (name.isEmpty ? 'Hi,' : 'Hi $name,');
    final intro = si ? 'ඔබ StudySync තුළ සෑදූ අධ්‍යයන සැලැස්ම මෙන්න.' : 'Here is the study plan you just created in StudySync.';
    final totals = si ? 'සැසි $n · අධ්‍යයන කාලය ${_hours(total)}' : '$n sessions · ${_hours(total)} of study';
    final by = claude
        ? (si ? 'Claude AI මගින් සැලසුම් කළා' : 'Planned by Claude AI')
        : (si ? 'StudySync AI මගින් සැලසුම් කළා' : 'Planned by StudySync AI');
    final footer = si
        ? 'ඔබ StudySync හි සැලැස්මක් යෙදූ නිසා මෙම ඊමේල් ලැබුණි. Profile → Email my study plans මගින් නවත්වන්න.'
        : 'You get this email because you applied a plan in StudySync. Turn it off in Profile → Email my study plans.';

    final byDay = <String, List<Map<String, dynamic>>>{};
    for (final s in sessions..sort((a, b) => '${a['date']}${a['start']}'.compareTo('${b['date']}${b['start']}'))) {
      byDay.putIfAbsent(s['date'] as String, () => []).add(s);
    }
    String dayTitle(String d) =>
        DateFormat('EEEE d MMMM', 'en_US').format(DateTime.parse(d)); // Sinhala dates need locale data; English is clear for both

    final html = StringBuffer()
      ..write('<div style="max-width:560px;margin:0 auto;padding:24px 16px;background:#f4f5fb;'
          'font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1f2133">')
      ..write('<div style="background:#4338ca;background:linear-gradient(135deg,#1e1b4b,#4338ca,#7c3aed);'
          'border-radius:18px;padding:22px;color:#ffffff">'
          '<div style="font-size:20px;font-weight:800">StudySync</div>'
          '<div style="opacity:.85;font-size:13px;margin-top:2px">${_esc(by)}</div>'
          '<div style="font-size:16px;font-weight:700;margin-top:14px">${_esc(totals)}</div></div>')
      ..write('<div style="background:#ffffff;border-radius:18px;padding:20px;margin-top:14px">'
          '<p style="margin:0 0 6px">${_esc(hello)}</p><p style="margin:0;color:#4b5065">${_esc(intro)}</p>');
    if (advice.isNotEmpty) {
      html.write('<p style="margin:14px 0 0;padding:12px 14px;background:#f1efff;border-radius:12px;color:#3b2f8f">'
          '“${_esc(advice)}”</p>');
    }
    for (final e in byDay.entries) {
      html.write('<h3 style="margin:22px 0 6px;font-size:15px;color:#1e1b4b">${_esc(dayTitle(e.key))}</h3>'
          '<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;font-size:14px">');
      for (final s in e.value) {
        html.write('<tr><td width="70" style="width:70px;padding:8px 10px;border-bottom:1px solid #eef0f6;white-space:nowrap;'
            'color:#4338ca;font-weight:700">${_esc(s['start'])}<br><span style="color:#8a8fa3;font-weight:400;font-size:12px">'
            '${s['minutes']} min</span></td><td style="padding:8px 10px;border-bottom:1px solid #eef0f6"><b>${_esc(s['subject'])}</b>'
            '<br><span style="color:#6b7085;font-size:13px">${_esc(s['type'])}</span></td></tr>');
      }
      html.write('</table>');
    }
    html.write('</div><p style="color:#8a8fa3;font-size:12px;line-height:1.5;margin:14px 6px">${_esc(footer)}</p></div>');

    final text = StringBuffer('$hello\n$intro\n$totals\n');
    if (advice.isNotEmpty) text.write('"$advice"\n');
    for (final e in byDay.entries) {
      text.write('\n${dayTitle(e.key)}\n');
      for (final s in e.value) {
        text.write('  ${s['start']} (${s['minutes']} min)  ${s['subject']} – ${s['type']}\n');
      }
    }
    text.write('\n$footer');
    return (subject: subject, html: html.toString(), text: text.toString());
  }

  /// Sends the email to [to] (the student's registered address); returns it.
  Future<String> send(Map<String, dynamic> request, {required String to, required String name}) async {
    if (!EmailConfig.useEmailJs) {
      final res = await FirebaseFunctions.instanceFor(region: 'asia-south1')
          .httpsCallable('emailStudyPlan', options: HttpsCallableOptions(timeout: const Duration(seconds: 60)))
          .call<dynamic>(request);
      return (Map<String, dynamic>.from(res.data as Map)['sentTo'] as String?) ?? to;
    }
    final mail = buildEmail(request);
    final res = await http
        .post(
          Uri.parse('https://api.emailjs.com/api/v1.0/email/send'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({
            'service_id': EmailConfig.serviceId,
            'template_id': EmailConfig.templateId,
            'user_id': EmailConfig.publicKey,
            'template_params': {
              'to_email': to,
              'to_name': name,
              'subject': mail.subject,
              'plan_html': mail.html,
              'plan_text': mail.text,
            },
          }),
        )
        .timeout(const Duration(seconds: 30));
    if (res.statusCode != 200) {
      throw PlanEmailException('EmailJS ${res.statusCode}: ${res.body.length > 120 ? res.body.substring(0, 120) : res.body}');
    }
    return to;
  }
}
