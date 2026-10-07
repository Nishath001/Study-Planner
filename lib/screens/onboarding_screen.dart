import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pc = PageController();
  int _page = 0;

  @override
  void dispose() {
    _pc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final slides = [
      (
        Icons.auto_awesome_rounded,
        AppColors.aiGradient,
        app.t('Your AI study planner', 'ඔබේ AI අධ්‍යයන සැලසුම්කරු'),
        app.t('Tell StudySync your subjects, exam dates and free time. It builds a personalised timetable that puts the right subject at the right time.',
            'ඔබේ විෂයයන්, විභාග දින සහ නිදහස් කාලය StudySync ට කියන්න. එය ඔබටම ගැලපෙන කාලසටහනක් සාදයි.'),
      ),
      (
        Icons.notifications_active_rounded,
        const LinearGradient(colors: [Color(0xFF0EA5E9), Color(0xFF14B8A6)]),
        app.t('Reminders that adapt', 'අනුවර්තනය වන සිහිකැඳවීම්'),
        app.t('Get reminded before every session. Missed one? The planner reschedules it into your next free slot automatically.',
            'සෑම සැසියකටම පෙර සිහිකැඳවීමක් ලැබේ. එකක් මඟ හැරුණාද? සැලසුම්කරු එය ඊළඟ නිදහස් වේලාවට ස්වයංක්‍රීයව යොදයි.'),
      ),
      (
        Icons.insights_rounded,
        const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFF43F5E)]),
        app.t('Track progress, stay motivated', 'ප්‍රගතිය බලන්න, උනන්දුවෙන් සිටින්න'),
        app.t('Focus timer, streaks, achievements and clear insights — in English or සිංහල.',
            'අවධාන ටයිමරය, අඛණ්ඩ දින, ජයග්‍රහණ සහ පැහැදිලි විශ්ලේෂණ — සිංහලෙන් හෝ English වලින්.'),
      ),
    ];
    final last = _page == slides.length - 1;

    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 12, 0),
            child: Row(children: [
              const LangToggle(),
              const Spacer(),
              if (!last)
                TextButton(
                  onPressed: () => _pc.animateToPage(slides.length - 1,
                      duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic),
                  child: Text(app.t('Skip', 'මඟහරින්න'), style: ts(14, w: FontWeight.w700, c: p.textSoft)),
                ),
            ]),
          ),
          Expanded(
            child: PageView.builder(
              controller: _pc,
              itemCount: slides.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (_, i) {
                final s = slides[i];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    _Hero(icon: s.$1, gradient: s.$2),
                    const SizedBox(height: 44),
                    Text(s.$3, textAlign: TextAlign.center,
                        style: ts(26, w: FontWeight.w800, c: p.text, h: 1.25)),
                    const SizedBox(height: 14),
                    Text(s.$4, textAlign: TextAlign.center, style: ts(15, c: p.textSoft, h: 1.6)),
                  ]),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Row(children: [
              Row(
                children: List.generate(slides.length, (i) => AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(right: 6),
                      width: i == _page ? 26 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: i == _page ? AppColors.primary : p.border,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    )),
              ),
              const Spacer(),
              SizedBox(
                width: last ? 180 : 64,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: last
                      ? GradientButton(
                          key: const ValueKey('start'),
                          label: app.t('Get started', 'ආරම්භ කරන්න'),
                          icon: Icons.arrow_forward_rounded,
                          onPressed: app.finishOnboarding,
                        )
                      : SizedBox(
                          key: const ValueKey('next'),
                          height: 56,
                          child: FilledButton(
                            onPressed: () => _pc.nextPage(
                                duration: const Duration(milliseconds: 400), curve: Curves.easeOutCubic),
                            style: FilledButton.styleFrom(padding: EdgeInsets.zero,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18))),
                            child: const Icon(Icons.arrow_forward_rounded),
                          ),
                        ),
                ),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  final IconData icon;
  final Gradient gradient;
  const _Hero({required this.icon, required this.gradient});

  @override
  Widget build(BuildContext context) {
    final c = gradient.colors.first;
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(alignment: Alignment.center, children: [
        Container(
          width: 240,
          height: 240,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(0.07)),
        ),
        Container(
          width: 180,
          height: 180,
          decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(0.10)),
        ),
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.6, end: 1),
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOutBack,
          builder: (_, v, child) => Transform.scale(scale: v, child: child),
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              gradient: gradient,
              borderRadius: BorderRadius.circular(38),
              boxShadow: [BoxShadow(color: c.withOpacity(0.45), blurRadius: 30, offset: const Offset(0, 14))],
            ),
            child: Icon(icon, color: Colors.white, size: 56),
          ),
        ),
        Positioned(top: 34, left: 30, child: _dot(14, gradient.colors.last)),
        Positioned(bottom: 40, right: 26, child: _dot(20, c)),
        Positioned(top: 54, right: 40, child: _dot(8, gradient.colors.last)),
      ]),
    );
  }

  Widget _dot(double s, Color c) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(shape: BoxShape.circle, color: c.withOpacity(0.6)),
      );
}
