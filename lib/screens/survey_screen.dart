import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// In-app evaluation survey: System Usability Scale + items mapped to the
/// three research questions (time management, bilingual UI, schedule accuracy).
class SurveyScreen extends StatefulWidget {
  const SurveyScreen({super.key});

  @override
  State<SurveyScreen> createState() => _SurveyScreenState();
}

class _SurveyScreenState extends State<SurveyScreen> {
  final _sus = List<int>.filled(10, 0);
  final _rq = <String, int>{};
  final _comment = TextEditingController();
  SurveyResponse? _result;

  static const _susItems = [
    ('I think that I would like to use this app frequently.', 'මම මෙම යෙදුම නිතර භාවිතා කිරීමට කැමතියි.'),
    ('I found the app unnecessarily complex.', 'යෙදුම අනවශ්‍ය ලෙස සංකීර්ණ බව මට පෙනුණි.'),
    ('I thought the app was easy to use.', 'යෙදුම භාවිතා කිරීමට පහසු යැයි සිතුවෙමි.'),
    ('I would need technical support to use this app.', 'මෙම යෙදුම භාවිතයට මට තාක්ෂණික සහාය අවශ්‍ය වේ.'),
    ('The features were well integrated.', 'විශේෂාංග හොඳින් ඒකාබද්ධ කර ඇත.'),
    ('There was too much inconsistency in the app.', 'යෙදුමේ නොගැළපීම් වැඩිය.'),
    ('Most people would learn to use this app very quickly.', 'බොහෝ දෙනා මෙය ඉක්මනින් භාවිතා කිරීමට ඉගෙන ගනී.'),
    ('I found the app very cumbersome to use.', 'යෙදුම භාවිතය ඉතා අපහසු විය.'),
    ('I felt very confident using the app.', 'යෙදුම භාවිතයේදී මට විශ්වාසයක් දැනුණි.'),
    ('I needed to learn a lot before I could get going.', 'ආරම්භ කිරීමට පෙර බොහෝ දේ ඉගෙන ගැනීමට සිදුවිය.'),
  ];

  static const _rqItems = [
    ('rq1_time', 'RQ1', 'StudySync helped me manage my study time better than my usual method.',
        'මගේ සාමාන්‍ය ක්‍රමයට වඩා StudySync මගේ කාලය කළමනාකරණයට උදව් විය.'),
    ('rq1_stress', 'RQ1', 'I felt more in control and less stressed about exams.',
        'විභාග ගැන මට අඩු ආතතියක් දැනුණි.'),
    ('rq2_usability', 'RQ2', 'Having Sinhala and English made the app easier to use.',
        'සිංහල සහ ඉංග්‍රීසි තිබීම යෙදුම භාවිතය පහසු කළේය.'),
    ('rq2_motivation', 'RQ2', 'Using my preferred language motivated me to keep studying.',
        'මා කැමති භාෂාව භාවිතය දිගටම ඉගෙනීමට මා පෙලඹවීය.'),
    ('rq3_accuracy', 'RQ3', 'The AI schedule matched my real availability and workload.',
        'AI කාලසටහන මගේ සැබෑ නිදහස් කාලයට සහ වැඩ ප්‍රමාණයට ගැළපුණි.'),
    ('rq3_adaptive', 'RQ3', 'When I missed a session, the rescheduling was helpful.',
        'සැසියක් මඟ හැරුණු විට නැවත සැකසීම ප්‍රයෝජනවත් විය.'),
  ];

  bool get _complete => !_sus.contains(0) && _rq.length == _rqItems.length;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final answered = _sus.where((v) => v > 0).length + _rq.length;

    return Scaffold(
      appBar: AppBar(
        title: Text(app.t('Research survey', 'පර්යේෂණ සමීක්ෂණය')),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(6),
          child: LinearProgressIndicator(
            value: answered / 16,
            minHeight: 4,
            backgroundColor: p.border,
            color: AppColors.teal,
          ),
        ),
      ),
      body: _result != null
          ? _thanks(app, p)
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
              children: [
                if (!app.researchConsent)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: AppCard(
                      color: AppColors.amber.withOpacity(0.1),
                      child: Row(children: [
                        const Icon(Icons.info_outline_rounded, color: AppColors.amber),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            app.t('You haven\'t joined the study. Your answers stay on this device unless you export them.',
                                'ඔබ අධ්‍යයනයට එක් වී නැත. ඔබ අපනයනය නොකරන්නේ නම් පිළිතුරු මෙම උපාංගයේම පවතී.'),
                            style: ts(12.5, c: p.textSoft, h: 1.45),
                          ),
                        ),
                      ]),
                    ),
                  ),
                Text(app.t('Part A · Usability', 'A කොටස · භාවිතයේ පහසුව'), style: ts(16, w: FontWeight.w800, c: p.text)),
                Text(app.t('1 = Strongly disagree · 5 = Strongly agree', '1 = දැඩි ලෙස එකඟ නැත · 5 = දැඩි ලෙස එකඟයි'),
                    style: ts(12, c: p.textMuted)),
                const SizedBox(height: 12),
                for (var i = 0; i < _susItems.length; i++)
                  _Question(
                    number: i + 1,
                    text: app.t(_susItems[i].$1, _susItems[i].$2),
                    value: _sus[i],
                    onChanged: (v) => setState(() => _sus[i] = v),
                  ),
                const SizedBox(height: 14),
                Text(app.t('Part B · Your experience', 'B කොටස · ඔබේ අත්දැකීම'), style: ts(16, w: FontWeight.w800, c: p.text)),
                const SizedBox(height: 12),
                for (final (i, q) in _rqItems.indexed)
                  _Question(
                    number: 11 + i,
                    tag: q.$2,
                    text: app.t(q.$3, q.$4),
                    value: _rq[q.$1] ?? 0,
                    onChanged: (v) => setState(() => _rq[q.$1] = v),
                  ),
                const SizedBox(height: 8),
                TextField(
                  controller: _comment,
                  maxLines: 4,
                  minLines: 3,
                  decoration: InputDecoration(
                    hintText: app.t('What worked well? What should we improve? (optional)',
                        'හොඳින් ක්‍රියා කළේ මොනවාද? වැඩිදියුණු කළ යුත්තේ කුමක්ද?'),
                  ),
                ),
                const SizedBox(height: 20),
                GradientButton(
                  label: _complete
                      ? app.t('Submit', 'ඉදිරිපත් කරන්න')
                      : app.t('Answer all questions ($answered/16)', 'සියලු ප්‍රශ්නවලට පිළිතුරු දෙන්න ($answered/16)'),
                  icon: Icons.send_rounded,
                  gradient: const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF0EA5E9)]),
                  onPressed: _complete
                      ? () async {
                          final r = SurveyResponse(
                            id: 'sv_${DateTime.now().millisecondsSinceEpoch}',
                            date: DateTime.now(),
                            sus: List.of(_sus),
                            research: Map.of(_rq),
                            language: app.language,
                            comment: _comment.text.trim(),
                          );
                          await app.addSurvey(r);
                          setState(() => _result = r);
                        }
                      : null,
                ),
              ],
            ),
    );
  }

  Widget _thanks(AppState app, Palette p) {
    final score = _result!.susScore;
    final grade = score >= 80
        ? app.t('Excellent', 'විශිෂ්ටයි')
        : score >= 68
            ? app.t('Good', 'හොඳයි')
            : score >= 51
                ? app.t('OK', 'සාමාන්‍යයි')
                : app.t('Needs work', 'වැඩිදියුණු විය යුතුයි');
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ProgressRing(
            value: score / 100,
            size: 150,
            stroke: 14,
            colors: const [AppColors.teal, AppColors.sky],
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(score.toStringAsFixed(1), style: ts(32, w: FontWeight.w800, c: p.text)),
              Text('SUS', style: ts(12, w: FontWeight.w700, c: p.textMuted)),
            ]),
          ),
          const SizedBox(height: 22),
          Text(app.t('Thank you!', 'ස්තූතියි!'), style: ts(24, w: FontWeight.w800, c: p.text)),
          const SizedBox(height: 8),
          Text(
            app.t('Your usability rating: $grade. Your response is saved anonymously and can be exported from Settings.',
                'ඔබේ ශ්‍රේණිගත කිරීම: $grade. ඔබේ ප්‍රතිචාරය නිර්නාමිකව සුරකින ලද අතර සැකසුම් වලින් අපනයනය කළ හැක.'),
            textAlign: TextAlign.center,
            style: ts(14, c: p.textSoft, h: 1.5),
          ),
          const SizedBox(height: 26),
          SizedBox(
            width: 220,
            child: GradientButton(label: app.t('Done', 'අවසන්'), onPressed: () => Navigator.pop(context)),
          ),
        ]),
      ),
    );
  }
}

class _Question extends StatelessWidget {
  final int number;
  final String text;
  final String? tag;
  final int value;
  final ValueChanged<int> onChanged;
  const _Question({required this.number, required this.text, required this.value, required this.onChanged, this.tag});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: AppCard(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('$number.', style: ts(13.5, w: FontWeight.w800, c: AppColors.teal)),
            const SizedBox(width: 8),
            Expanded(child: Text(text, style: ts(13.5, w: FontWeight.w600, c: p.text, h: 1.45))),
            if (tag != null) ...[const SizedBox(width: 6), Pill(tag!, AppColors.violet)],
          ]),
          const SizedBox(height: 12),
          Row(children: [
            for (var v = 1; v <= 5; v++)
              Expanded(
                child: GestureDetector(
                  onTap: () => onChanged(v),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    height: 40,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      color: value == v ? AppColors.teal : p.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text('$v', style: ts(14, w: FontWeight.w800, c: value == v ? Colors.white : p.textSoft)),
                    ),
                  ),
                ),
              ),
          ]),
        ]),
      ),
    );
  }
}
