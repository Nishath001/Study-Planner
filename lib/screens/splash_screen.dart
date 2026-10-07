import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/ui.dart';

class SplashScreen extends StatefulWidget {
  final Widget next;
  final bool hold; // stay on the splash (demo / screenshots)
  const SplashScreen({super.key, required this.next, this.hold = false});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))
    ..forward();
  bool _done = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1700), () {
      if (mounted && !widget.hold) setState(() => _done = true);
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 500),
      child: _done ? widget.next : _splash(),
    );
  }

  Widget _splash() {
    final logo = CurvedAnimation(parent: _c, curve: const Interval(0, 0.55, curve: Curves.easeOutBack));
    final text = CurvedAnimation(parent: _c, curve: const Interval(0.35, 0.85, curve: Curves.easeOut));
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFF1E1B4B), Color(0xFF4338CA), Color(0xFF7C3AED)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(children: [
          Positioned(top: -80, right: -60, child: _orb(260, Colors.white.withOpacity(0.08))),
          Positioned(bottom: -100, left: -70, child: _orb(300, const Color(0xFFEC4899).withOpacity(0.18))),
          Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              ScaleTransition(
                scale: logo,
                child: const AppLogo(size: 104),
              ),
              const SizedBox(height: 26),
              FadeTransition(
                opacity: text,
                child: SlideTransition(
                  position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(text),
                  child: Column(children: [
                    Text('StudySync', style: ts(36, w: FontWeight.w800, c: Colors.white)),
                    const SizedBox(height: 6),
                    Text('AI-POWERED STUDY PLANNER',
                        style: AppTheme.font(size: 11.5, weight: FontWeight.w700,
                            color: Colors.white70, spacing: 2.4)),
                  ]),
                ),
              ),
            ]),
          ),
          Positioned(
            bottom: 48,
            left: 0,
            right: 0,
            child: FadeTransition(
              opacity: text,
              child: Text('Horizon Campus · BIT (Hons) NMC',
                  textAlign: TextAlign.center, style: ts(11.5, c: Colors.white54)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _orb(double s, Color c) => Container(
        width: s,
        height: s,
        decoration: BoxDecoration(shape: BoxShape.circle,
            gradient: RadialGradient(colors: [c, c.withOpacity(0)])),
      );
}

/// Brand mark: a rounded tile with a sparkle-book glyph.
class AppLogo extends StatelessWidget {
  final double size;
  const AppLogo({super.key, this.size = 80});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(size * 0.3),
          gradient: const LinearGradient(
            colors: [Color(0xFF818CF8), Color(0xFF6366F1), Color(0xFF8B5CF6)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.35), width: 1.5),
          boxShadow: [
            BoxShadow(color: AppColors.primary.withOpacity(0.5), blurRadius: size * 0.35, offset: Offset(0, size * 0.12)),
          ],
        ),
        child: Stack(alignment: Alignment.center, children: [
          Icon(Icons.auto_stories_rounded, color: Colors.white, size: size * 0.5),
          Positioned(
            top: size * 0.16,
            right: size * 0.16,
            child: Icon(Icons.auto_awesome, color: const Color(0xFFFDE68A), size: size * 0.2),
          ),
        ]),
      );
}
