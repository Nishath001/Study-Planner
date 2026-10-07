import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Available study time per weekday + preferred part of the day.
class AvailabilityEditor extends StatelessWidget {
  final StudyPreferences prefs;
  final VoidCallback onChanged;
  const AvailabilityEditor({super.key, required this.prefs, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final days = app.isSinhala
        ? ['සඳුදා', 'අඟහරු', 'බදාදා', 'බ්‍රහස්', 'සිකුරා', 'සෙනසු', 'ඉරිදා']
        : ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final windows = [
      (StudyWindow.morning, Icons.wb_twilight_rounded, app.t('Morning', 'උදෑසන'), '6 AM'),
      (StudyWindow.afternoon, Icons.wb_sunny_rounded, app.t('Afternoon', 'දහවල්'), '1 PM'),
      (StudyWindow.evening, Icons.wb_cloudy_rounded, app.t('Evening', 'සවස'), '5 PM'),
      (StudyWindow.night, Icons.nights_stay_rounded, app.t('Night', 'රාත්‍රී'), '8 PM'),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(children: [
          Row(children: [
            Text(app.t('Weekly total', 'සතියේ මුළු කාලය'), style: ts(13, w: FontWeight.w700, c: p.textSoft)),
            const Spacer(),
            Pill(fmtMinutes(prefs.weeklyMinutes), AppColors.primary, icon: Icons.schedule_rounded),
          ]),
          const SizedBox(height: 6),
          for (var i = 0; i < 7; i++)
            Row(children: [
              SizedBox(width: 52, child: Text(days[i], style: ts(13, w: FontWeight.w700, c: p.text))),
              Expanded(
                child: Slider(
                  value: prefs.availability[i].toDouble(),
                  min: 0,
                  max: 600,
                  divisions: 20,
                  onChanged: (v) {
                    prefs.availability[i] = v.round();
                    onChanged();
                  },
                ),
              ),
              SizedBox(
                width: 54,
                child: Text(
                  prefs.availability[i] == 0 ? app.t('Off', 'නැත') : fmtMinutes(prefs.availability[i]),
                  textAlign: TextAlign.right,
                  style: ts(12.5, w: FontWeight.w800,
                      c: prefs.availability[i] == 0 ? p.textMuted : AppColors.primary),
                ),
              ),
            ]),
        ]),
      ),
      const SizedBox(height: 20),
      Text(app.t('Best time for you to study', 'ඔබට ඉගෙනීමට හොඳම කාලය'),
          style: ts(14, w: FontWeight.w800, c: p.text)),
      const SizedBox(height: 10),
      GridView.count(
              padding: EdgeInsets.zero,
        crossAxisCount: 2,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 2.5,
        children: [
          for (final w in windows)
            _ChoiceTile(
              icon: w.$2,
              title: w.$3,
              subtitle: app.t('from ${w.$4}', '${w.$4} සිට'),
              selected: prefs.window == w.$1,
              onTap: () {
                prefs.window = w.$1;
                onChanged();
              },
            ),
        ],
      ),
    ]);
  }
}

/// Session length, breaks, daily goal and planning horizon.
class StudyStyleEditor extends StatelessWidget {
  final StudyPreferences prefs;
  final VoidCallback onChanged;
  const StudyStyleEditor({super.key, required this.prefs, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;

    Widget chips(List<int> values, int current, ValueChanged<int> set, String Function(int) label) => Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final v in values)
              ChoiceChip(
                label: Text(label(v)),
                selected: current == v,
                showCheckmark: false,
                selectedColor: AppColors.primary,
                labelStyle: ts(13, w: FontWeight.w700, c: current == v ? Colors.white : p.textSoft),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                onSelected: (_) {
                  set(v);
                  onChanged();
                },
              ),
          ],
        );

    Widget block(IconData icon, Color color, String title, String sub, Widget child) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: AppCard(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                IconBadge(icon, color, size: 38, radius: 12),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: ts(14, w: FontWeight.w800, c: p.text)),
                    Text(sub, style: ts(12, c: p.textMuted)),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              child,
            ]),
          ),
        );

    return Column(children: [
      block(Icons.timer_outlined, AppColors.primary, app.t('Session length', 'සැසියක දිග'),
          app.t('How long you can focus in one go', 'එක වරකට අවධානය යොමු කළ හැකි කාලය'),
          chips([25, 45, 50, 60, 90], prefs.sessionMinutes, (v) => prefs.sessionMinutes = v, (v) => '$v min')),
      block(Icons.free_breakfast_outlined, AppColors.teal, app.t('Break between sessions', 'සැසි අතර විවේකය'),
          app.t('Short breaks improve retention', 'කෙටි විවේක මතකය වැඩි කරයි'),
          chips([5, 10, 15, 20], prefs.breakMinutes, (v) => prefs.breakMinutes = v, (v) => '$v min')),
      block(Icons.flag_outlined, AppColors.amber, app.t('Daily study goal', 'දෛනික ඉලක්කය'),
          app.t('Used for your progress ring', 'ප්‍රගති වළල්ල සඳහා භාවිතා වේ'),
          Row(children: [
            Expanded(
              child: Slider(
                value: prefs.dailyGoalMinutes.toDouble(),
                min: 30,
                max: 480,
                divisions: 15,
                onChanged: (v) {
                  prefs.dailyGoalMinutes = v.round();
                  onChanged();
                },
              ),
            ),
            Pill(fmtMinutes(prefs.dailyGoalMinutes), AppColors.amber),
          ])),
      block(Icons.date_range_outlined, AppColors.violet, app.t('Plan ahead', 'ඉදිරියට සැලසුම් කරන්න'),
          app.t('How many days the AI plans at once', 'AI එක වරකට සැලසුම් කරන දින ගණන'),
          chips([7, 14], prefs.planHorizonDays, (v) => prefs.planHorizonDays = v,
              (v) => app.t('$v days', 'දින $v'))),
    ]);
  }
}

class _ChoiceTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final bool selected;
  final VoidCallback onTap;
  const _ChoiceTile({required this.icon, required this.title, required this.subtitle, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withOpacity(0.1) : p.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? AppColors.primary : p.border, width: selected ? 1.8 : 1),
        ),
        child: Row(children: [
          Icon(icon, color: selected ? AppColors.primary : p.textMuted, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: ts(13, w: FontWeight.w800, c: selected ? AppColors.primary : p.text)),
              Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(11, c: p.textMuted)),
            ]),
          ),
        ]),
      ),
    );
  }
}
