import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/suggestion_engine.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/suggestion_card.dart';
import '../widgets/ui.dart';

class SuggestionsScreen extends StatelessWidget {
  const SuggestionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final list = app.suggestions;
    final profile = LearnedProfile.learn(app.tasks, app.sessions, DateTime.now());
    final peaks = profile.peakHours;

    String typeName(SuggestionType t) => switch (t) {
          SuggestionType.examCoverage => app.t('Exam revision', 'විභාග පුනරීක්ෂණ'),
          SuggestionType.rebalanceDay => app.t('Lighten busy days', 'අධික දින සැහැල්ලු කිරීම'),
          SuggestionType.moveToPeak => app.t('Best-time moves', 'හොඳම වේලාවට ගෙනයාම'),
          SuggestionType.splitLong => app.t('Split long sessions', 'දිගු සැසි බෙදීම'),
          SuggestionType.neglectedSubject => app.t('Revisit subjects', 'විෂය නැවත බැලීම'),
          SuggestionType.shorterSessions => app.t('Session length', 'සැසි දිග'),
          SuggestionType.betterWindow => app.t('Study time of day', 'ඉගෙනුම් වේලාව'),
        };

    return Scaffold(
      appBar: AppBar(title: Text(app.t('Smart suggestions', 'බුද්ධිමත් යෝජනා'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
        children: [
          Text(
            app.t('Improvements based on your plan and how you actually study. Apply what helps — dismiss what doesn\'t, and StudySync learns.',
                'ඔබේ සැලැස්ම සහ ඔබ සැබවින්ම ඉගෙන ගන්නා ආකාරය මත වැඩිදියුණු කිරීම්. උදව් වන දේ යොදන්න — නැති දේ ඉවත් කරන්න, StudySync ඉගෙන ගනී.'),
            style: ts(13, c: p.textSoft, h: 1.5),
          ),
          const SizedBox(height: 18),
          if (list.isEmpty)
            EmptyState(
              icon: Icons.verified_rounded,
              color: AppColors.green,
              title: app.t('Your plan looks great', 'ඔබේ සැලැස්ම හොඳයි'),
              subtitle: app.t('No improvements right now. Keep using the focus timer — suggestions get smarter with more data.',
                  'දැනට වැඩිදියුණු කිරීම් නැත. අවධාන ටයිමරය දිගටම භාවිතා කරන්න — වැඩි දත්ත සමඟ යෝජනා වඩා හොඳ වේ.'),
            )
          else
            for (final (i, s) in list.indexed)
              FadeSlideIn(delay: 40 * i, child: SuggestionCard(key: ValueKey(s.id), suggestion: s)),
          const SizedBox(height: 14),
          SectionHeader(app.t('What StudySync has learned', 'StudySync ඉගෙන ගත් දේ')),
          AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _fact(context, Icons.wb_sunny_rounded, AppColors.amber, app.t('Best study hours', 'හොඳම ඉගෙනුම් වේලාවන්'),
                  peaks.isEmpty
                      ? app.t('Needs a few more sessions', 'තවත් සැසි කිහිපයක් අවශ්‍යයි')
                      : peaks.map((h) => '${h.toString().padLeft(2, '0')}:00').join(' · ')),
              _fact(context, Icons.timer_outlined, AppColors.teal, app.t('Real focus span', 'සැබෑ අවධාන කාලය'),
                  profile.focusSpan == null
                      ? app.t('Use the focus timer 3+ times', 'අවධාන ටයිමරය 3+ වරක් භාවිතා කරන්න')
                      : app.t('about ${profile.focusSpan!.round()} min', 'මිනිත්තු ${profile.focusSpan!.round()} පමණ')),
              for (final s in app.subjects.where((s) => (profile.slipRate[s.id] ?? 0) >= 0.3))
                _fact(context, Icons.trending_down_rounded, AppColors.rose, s.name,
                    app.t('${((profile.slipRate[s.id] ?? 0) * 100).round()}% of sessions missed',
                        'සැසිවලින් ${((profile.slipRate[s.id] ?? 0) * 100).round()}% මඟහැරුණි')),
            ]),
          ),
          if (app.suggestionFeedback.isNotEmpty) ...[
            const SizedBox(height: 16),
            SectionHeader(app.t('Your preferences', 'ඔබේ මනාපයන්')),
            AppCard(
              child: Column(children: [
                for (final e in app.suggestionFeedback.entries)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(children: [
                      Expanded(child: Text(typeName(e.key), style: ts(13, w: FontWeight.w700, c: p.text))),
                      Text('${e.value.accepted}✓  ${e.value.rejected}✗',
                          style: ts(12, w: FontWeight.w700, c: p.textMuted)),
                      const SizedBox(width: 10),
                      SizedBox(
                        width: 70,
                        child: SoftProgressBar(
                          value: e.value.acceptance,
                          color: e.value.total >= 3 && e.value.acceptance < 0.3 ? p.textMuted : AppColors.primary,
                          height: 6,
                        ),
                      ),
                    ]),
                  ),
                const SizedBox(height: 6),
                Text(
                  app.t('Types you keep dismissing are hidden; ones you accept are shown first.',
                      'ඔබ නිතර ඉවත් කරන වර්ග සඟවයි; ඔබ පිළිගන්නා ඒවා මුලින් පෙන්වයි.'),
                  style: ts(11.5, c: p.textMuted, h: 1.4),
                ),
              ]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fact(BuildContext context, IconData icon, Color color, String label, String value) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(children: [
        IconBadge(icon, color, size: 36, radius: 11),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: ts(13, w: FontWeight.w700, c: p.text))),
        Flexible(child: Text(value, textAlign: TextAlign.right, style: ts(12.5, w: FontWeight.w600, c: p.textSoft))),
      ]),
    );
  }
}
