import 'dart:math';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';

// ── Helpers ────────────────────────────────────────────────────────────────
extension TrX on BuildContext {
  /// Bilingual string. Screens `watch<AppState>()` so a language switch rebuilds them.
  String tr(String en, String si) => Provider.of<AppState>(this, listen: false).t(en, si);
  String get locale => Provider.of<AppState>(this, listen: false).isSinhala ? 'si' : 'en';
}

String fmtTime(BuildContext c, DateTime d) => DateFormat.jm(c.locale).format(d);
String fmtDay(BuildContext c, DateTime d) => DateFormat.MMMEd(c.locale).format(d);
String fmtDate(BuildContext c, DateTime d) => DateFormat.yMMMd(c.locale).format(d);

String fmtMinutes(int m) {
  if (m < 60) return '${m}m';
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '${h}h' : '${h}h ${r}m';
}

String relativeDay(BuildContext c, DateTime d) {
  final diff = dateOnly(d).difference(dateOnly(DateTime.now())).inDays;
  if (diff == 0) return c.tr('Today', 'අද');
  if (diff == 1) return c.tr('Tomorrow', 'හෙට');
  if (diff == -1) return c.tr('Yesterday', 'ඊයේ');
  return fmtDay(c, d);
}

TextStyle ts(double size, {FontWeight w = FontWeight.w500, Color? c, double? h}) =>
    AppTheme.font(size: size, weight: w, color: c, height: h);

// ── Surfaces ───────────────────────────────────────────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Gradient? gradient;
  final Color? color;
  final double radius;
  final bool border;

  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
    this.onTap,
    this.gradient,
    this.color,
    this.radius = 22,
    this.border = true,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final hasFill = gradient != null || color != null;
    return Container(
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? p.surface) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(radius),
        border: border && !hasFill ? Border.all(color: p.border) : null,
        boxShadow: [
          if (gradient != null)
            BoxShadow(
              color: (gradient!.colors.first).withOpacity(0.35),
              blurRadius: 24,
              offset: const Offset(0, 10),
            )
          else if (!p.isDark)
            BoxShadow(
              color: const Color(0xFF1E293B).withOpacity(0.04),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
        ],
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(radius),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  final String title;
  final String? action;
  final VoidCallback? onAction;
  const SectionHeader(this.title, {super.key, this.action, this.onAction});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12, top: 4),
        child: Row(children: [
          Expanded(child: Text(title, style: ts(17, w: FontWeight.w800, c: context.pal.text))),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(action!, style: ts(13, w: FontWeight.w700, c: AppColors.primary)),
            ),
        ]),
      );
}

class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  final double radius;
  const IconBadge(this.icon, this.color, {super.key, this.size = 44, this.radius = 14});

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withOpacity(context.pal.isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Icon(icon, color: color, size: size * 0.5),
      );
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;
  final bool solid;
  const Pill(this.text, this.color, {super.key, this.icon, this.solid = false});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: solid ? color : color.withOpacity(context.pal.isDark ? 0.18 : 0.12),
          borderRadius: BorderRadius.circular(30),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: solid ? Colors.white : color),
            const SizedBox(width: 4),
          ],
          Text(text, style: ts(11.5, w: FontWeight.w700, c: solid ? Colors.white : color)),
        ]),
      );
}

class StatTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value, label;
  const StatTile({super.key, required this.icon, required this.color, required this.value, required this.label});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        IconBadge(icon, color, size: 36, radius: 11),
        const SizedBox(height: 12),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(value, style: ts(20, w: FontWeight.w800, c: p.text)),
        ),
        const SizedBox(height: 2),
        Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
            style: ts(11.5, w: FontWeight.w600, c: p.textMuted)),
      ]),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  final Color color;
  const EmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
    this.color = AppColors.primary,
  });

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 28),
      child: Column(children: [
        Container(
          width: 72,
          height: 72,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [color.withOpacity(0.22), color.withOpacity(0.06)]),
          ),
          child: Icon(icon, color: color, size: 34),
        ),
        const SizedBox(height: 16),
        Text(title, textAlign: TextAlign.center, style: ts(16, w: FontWeight.w800, c: p.text)),
        const SizedBox(height: 6),
        Text(subtitle, textAlign: TextAlign.center, style: ts(13, c: p.textSoft, h: 1.5)),
        if (actionLabel != null) ...[
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: onAction,
            icon: const Icon(Icons.add_rounded, size: 18),
            label: Text(actionLabel!),
            style: FilledButton.styleFrom(minimumSize: const Size(0, 46),
                padding: const EdgeInsets.symmetric(horizontal: 20)),
          ),
        ],
      ]),
    );
  }
}

class GradientButton extends StatelessWidget {
  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final Gradient gradient;
  final bool loading;
  const GradientButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.gradient = AppColors.brandGradient,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onPressed == null && !loading ? 0.5 : 1,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: gradient.colors.first.withOpacity(0.4), blurRadius: 18, offset: const Offset(0, 8)),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(18),
              onTap: loading ? null : onPressed,
              child: Center(
                child: loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : Row(mainAxisSize: MainAxisSize.min, children: [
                        if (icon != null) ...[Icon(icon, color: Colors.white, size: 20), const SizedBox(width: 8)],
                        Text(label, style: ts(15, w: FontWeight.w800, c: Colors.white)),
                      ]),
              ),
            ),
          ),
        ),
      );
}

// ── Progress ring ──────────────────────────────────────────────────────────
class ProgressRing extends StatelessWidget {
  final double value;
  final double size, stroke;
  final List<Color> colors;
  final Color? track;
  final Widget? child;
  const ProgressRing({
    super.key,
    required this.value,
    this.size = 120,
    this.stroke = 12,
    this.colors = const [AppColors.primary, AppColors.violet],
    this.track,
    this.child,
  });

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: value.clamp(0, 1)),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => SizedBox(
          width: size,
          height: size,
          child: CustomPaint(
            painter: _RingPainter(v, stroke, colors, track ?? context.pal.surfaceAlt),
            child: Center(child: child),
          ),
        ),
      );
}

class _RingPainter extends CustomPainter {
  final double v, stroke;
  final List<Color> colors;
  final Color track;
  _RingPainter(this.v, this.stroke, this.colors, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    canvas.drawArc(r, 0, 2 * pi, false,
        Paint()..color = track..style = PaintingStyle.stroke..strokeWidth = stroke);
    if (v <= 0) return;
    final paint = Paint()
      ..shader = SweepGradient(
        startAngle: -pi / 2,
        endAngle: 3 * pi / 2,
        colors: colors.length == 1 ? [colors[0], colors[0]] : colors,
        transform: const GradientRotation(-pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = stroke;
    canvas.drawArc(r, -pi / 2, 2 * pi * v, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter o) => o.v != v || o.track != track;
}

class SoftProgressBar extends StatelessWidget {
  final double value;
  final Color color;
  final double height;
  const SoftProgressBar({super.key, required this.value, required this.color, this.height = 8});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(height),
        child: Stack(children: [
          Container(height: height, color: color.withOpacity(0.15)),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: value.clamp(0, 1)),
            duration: const Duration(milliseconds: 800),
            curve: Curves.easeOutCubic,
            builder: (_, v, __) => FractionallySizedBox(
              widthFactor: v,
              child: Container(
                height: height,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.white, 0.25)!]),
                  borderRadius: BorderRadius.circular(height),
                ),
              ),
            ),
          ),
        ]),
      );
}

// ── Entrance animation ─────────────────────────────────────────────────────
class FadeSlideIn extends StatelessWidget {
  final Widget child;
  final int delay; // ms
  const FadeSlideIn({super.key, required this.child, this.delay = 0});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: Duration(milliseconds: 450 + delay),
        curve: Interval(delay / (450 + delay), 1, curve: Curves.easeOutCubic),
        builder: (_, v, c) => Opacity(
          opacity: v,
          child: Transform.translate(offset: Offset(0, 18 * (1 - v)), child: c),
        ),
        child: child,
      );
}

// ── Task card ──────────────────────────────────────────────────────────────
class TaskCard extends StatelessWidget {
  final StudyTask task;
  final VoidCallback? onTap;
  final bool showDate;
  const TaskCard({super.key, required this.task, this.onTap, this.showDate = false});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final subject = app.subject(task.subjectId);
    final color = subject?.color ?? AppColors.primary;
    final done = task.isDone;
    final missed = task.status == TaskStatus.missed;
    final skipped = task.status == TaskStatus.skipped;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(children: [
            Container(
              width: 5,
              margin: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: color.withOpacity(done || skipped ? 0.35 : 1),
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(6)),
              ),
            ),
            const SizedBox(width: 12),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: IconBadge(subject?.iconData ?? Icons.menu_book_rounded, color, size: 42, radius: 13),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      task.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: ts(14, w: FontWeight.w700, c: done || skipped ? p.textMuted : p.text).copyWith(
                        decoration: done ? TextDecoration.lineThrough : null,
                        decorationColor: p.textMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                      Row(mainAxisSize: MainAxisSize.min, children: [
                        Icon(Icons.schedule_rounded, size: 13, color: p.textMuted),
                        const SizedBox(width: 3),
                        Text(
                          '${showDate ? '${relativeDay(context, task.start)} · ' : ''}${fmtTime(context, task.start)} · ${fmtMinutes(task.durationMinutes)}',
                          style: ts(11.5, w: FontWeight.w600, c: p.textMuted),
                        ),
                      ]),
                      if (missed) Pill(context.tr('Missed', 'මඟහැරුණි'), AppColors.rose),
                      if (skipped) Pill(context.tr('Skipped', 'මඟහැරියා'), p.textMuted),
                      if (task.rescheduleCount > 0 && !missed)
                        Pill(context.tr('Rescheduled', 'නැවත සැකසූ'), AppColors.amber, icon: Icons.replay_rounded),
                      if (task.aiGenerated && !missed && task.rescheduleCount == 0)
                        Icon(Icons.auto_awesome_rounded, size: 13, color: AppColors.violet.withOpacity(0.8)),
                    ]),
                  ],
                ),
              ),
            ),
            _CheckButton(
              done: done,
              color: color,
              onTap: skipped ? null : () => app.toggleTask(task),
            ),
            const SizedBox(width: 10),
          ]),
        ),
      ),
    );
  }
}

class _CheckButton extends StatelessWidget {
  final bool done;
  final Color color;
  final VoidCallback? onTap;
  const _CheckButton({required this.done, required this.color, this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutBack,
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: done ? color : Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: done ? color : context.pal.border, width: 2),
          ),
          child: AnimatedScale(
            scale: done ? 1 : 0,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeOutBack,
            child: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
          ),
        ),
      );
}

/// Language switcher pill used in app bars.
class LangToggle extends StatelessWidget {
  const LangToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    Widget seg(String code, String label) {
      final sel = app.language == code;
      return GestureDetector(
        onTap: () => app.setLanguage(code),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: sel ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label, style: ts(12, w: FontWeight.w800, c: sel ? Colors.white : p.textSoft)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: p.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [seg('EN', 'EN'), seg('SI', 'සිං')]),
    );
  }
}

class Avatar extends StatelessWidget {
  final String name;
  final double size;
  const Avatar(this.name, {super.key, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final initials = name.trim().isEmpty
        ? '?'
        : name.trim().split(RegExp(r'\s+')).take(2).map((w) => w[0].toUpperCase()).join();
    return Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(shape: BoxShape.circle, gradient: AppColors.brandGradient),
      child: Center(child: Text(initials, style: ts(size * 0.36, w: FontWeight.w800, c: Colors.white))),
    );
  }
}
