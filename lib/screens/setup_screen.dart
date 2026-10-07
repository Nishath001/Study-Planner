import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/pref_editors.dart';
import '../widgets/ui.dart';

/// First-run wizard: available time, study style and research consent.
class SetupScreen extends StatefulWidget {
  const SetupScreen({super.key});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  int _step = 0;
  bool _consent = false;
  late final StudyPreferences _prefs =
      StudyPreferences.fromJson(context.read<AppState>().prefs.toJson());

  Future<void> _next() async {
    final app = context.read<AppState>();
    if (_step < 2) {
      setState(() => _step++);
      return;
    }
    await app.savePrefs(_prefs);
    await app.completeSetup(consent: _consent);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final titles = [
      (app.t('When can you study?', 'ඔබට ඉගෙනීමට හැකි කාලය?'),
          app.t('Set your free time for each day. The AI never plans beyond it.',
              'සෑම දිනකටම ඔබේ නිදහස් කාලය සකසන්න. AI එයින් ඔබ්බට සැලසුම් නොකරයි.')),
      (app.t('Your study style', 'ඔබේ අධ්‍යයන රටාව'),
          app.t('We\'ll shape sessions around how you focus best.',
              'ඔබ හොඳින්ම අවධානය යොමු කරන ආකාරයට සැසි සකසමු.')),
      (app.t('Help improve StudySync', 'StudySync වැඩිදියුණු කිරීමට උදව් වන්න'),
          app.t('Optional — part of a Horizon Campus research study.',
              'අත්‍යවශ්‍ය නැත — Horizon Campus පර්යේෂණයක කොටසකි.')),
    ];

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 20, 0),
            child: Row(children: [
              IconButton(
                onPressed: _step == 0 ? null : () => setState(() => _step--),
                icon: Icon(Icons.arrow_back_rounded, color: _step == 0 ? Colors.transparent : p.text),
              ),
              Expanded(
                child: Row(
                  children: List.generate(3, (i) => Expanded(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 300),
                          height: 6,
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          decoration: BoxDecoration(
                            gradient: i <= _step ? AppColors.brandGradient : null,
                            color: i <= _step ? null : p.border,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                      )),
                ),
              ),
              const SizedBox(width: 12),
              const LangToggle(),
            ]),
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              transitionBuilder: (c, a) => FadeTransition(
                opacity: a,
                child: SlideTransition(
                    position: Tween(begin: const Offset(0.06, 0), end: Offset.zero).animate(a), child: c),
              ),
              child: ListView(
                key: ValueKey(_step),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
                children: [
                  Text(app.t('Step ${_step + 1} of 3', 'පියවර ${_step + 1} / 3'),
                      style: ts(12.5, w: FontWeight.w800, c: AppColors.primary)),
                  const SizedBox(height: 6),
                  Text(titles[_step].$1, style: ts(26, w: FontWeight.w800, c: p.text, h: 1.2)),
                  const SizedBox(height: 8),
                  Text(titles[_step].$2, style: ts(14, c: p.textSoft, h: 1.5)),
                  const SizedBox(height: 22),
                  if (_step == 0) AvailabilityEditor(prefs: _prefs, onChanged: () => setState(() {})),
                  if (_step == 1) StudyStyleEditor(prefs: _prefs, onChanged: () => setState(() {})),
                  if (_step == 2) _consentStep(app, p),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: GradientButton(
              label: _step == 2 ? app.t('Start planning', 'සැලසුම් කිරීම අරඹන්න') : app.t('Continue', 'ඉදිරියට'),
              icon: _step == 2 ? Icons.rocket_launch_rounded : Icons.arrow_forward_rounded,
              onPressed: _prefs.weeklyMinutes == 0 ? null : _next,
            ),
          ),
        ]),
      ),
    );
  }

  Widget _consentStep(AppState app, Palette p) {
    final points = [
      (Icons.volunteer_activism_rounded, AppColors.teal, app.t('Voluntary', 'ස්වේච්ඡාවෙන්'),
          app.t('Participation is optional. You can withdraw any time in Settings.',
              'සහභාගීත්වය ස්වේච්ඡාවෙනි. ඕනෑම වේලාවක සැකසුම් තුළින් ඉවත් විය හැක.')),
      (Icons.shield_rounded, AppColors.primary, app.t('Anonymous', 'නිර්නාමිකයි'),
          app.t('No names, emails or student IDs are included in research exports.',
              'පර්යේෂණ දත්තවල නම්, ඊමේල් හෝ ශිෂ්‍ය අංක ඇතුළත් නොවේ.')),
      (Icons.phone_android_rounded, AppColors.amber, app.t('Stays on your device', 'ඔබේ උපාංගයේම පවතී'),
          app.t('Data is stored locally and only shared if you export it yourself.',
              'දත්ත දේශීයව ගබඩා වන අතර ඔබම අපනයනය කළහොත් පමණක් බෙදාගැනේ.')),
      (Icons.sentiment_satisfied_alt_rounded, AppColors.rose, app.t('Minimal risk', 'අවම අවදානම'),
          app.t('You simply use the app and share feedback through a short survey.',
              'ඔබ යෙදුම භාවිතා කර කෙටි සමීක්ෂණයක් හරහා අදහස් ලබාදීම පමණි.')),
    ];
    return Column(children: [
      for (final x in points)
        Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppCard(
            padding: const EdgeInsets.all(14),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              IconBadge(x.$1, x.$2, size: 40, radius: 12),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(x.$3, style: ts(14, w: FontWeight.w800, c: p.text)),
                  const SizedBox(height: 2),
                  Text(x.$4, style: ts(12.5, c: p.textSoft, h: 1.45)),
                ]),
              ),
            ]),
          ),
        ),
      const SizedBox(height: 6),
      AppCard(
        onTap: () => setState(() => _consent = !_consent),
        color: _consent ? AppColors.primary.withOpacity(0.08) : null,
        padding: const EdgeInsets.all(14),
        child: Row(children: [
          Checkbox(
            value: _consent,
            onChanged: (v) => setState(() => _consent = v ?? false),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              app.t('I agree to take part in the StudySync evaluation study.',
                  'StudySync ඇගයීම් අධ්‍යයනයට සහභාගී වීමට මම එකඟ වෙමි.'),
              style: ts(13.5, w: FontWeight.w700, c: p.text, h: 1.4),
            ),
          ),
        ]),
      ),
    ]);
  }
}
