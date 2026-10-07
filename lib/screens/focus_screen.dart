import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/notification_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'shell.dart';

/// Pomodoro-style focus timer. Every finished block is logged as a study
/// session with a self-rated focus score that feeds the adaptive planner.
class FocusScreen extends StatefulWidget {
  const FocusScreen({super.key});

  @override
  State<FocusScreen> createState() => _FocusScreenState();
}

class _FocusScreenState extends State<FocusScreen> {
  String? _subjectId;
  StudyTask? _task;
  int _minutes = 25;
  bool _break = false;

  Timer? _timer;
  DateTime? _endsAt;
  Duration _remaining = const Duration(minutes: 25);
  bool get _running => _timer != null;
  bool get _started => _remaining.inSeconds != _minutes * 60;

  ShellNav? _nav;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_nav == null) {
      _nav = context.read<ShellNav>()..addListener(_onNav);
      _minutes = context.read<AppState>().prefs.sessionMinutes;
      _remaining = Duration(minutes: _minutes);
    }
  }

  void _onNav() {
    final t = _nav!.focusTask;
    if (t == null || t == _task || _running) return;
    setState(() {
      _task = t;
      _subjectId = t.subjectId;
      _break = false;
      _setMinutes(t.durationMinutes);
    });
    _nav!.focusTask = null;
  }

  @override
  void dispose() {
    _nav?.removeListener(_onNav);
    _timer?.cancel();
    super.dispose();
  }

  void _setMinutes(int m) {
    _minutes = m;
    _remaining = Duration(minutes: m);
  }

  void _start() {
    _endsAt = DateTime.now().add(_remaining);
    _timer = Timer.periodic(const Duration(milliseconds: 250), (_) {
      final left = _endsAt!.difference(DateTime.now());
      if (left <= Duration.zero) {
        _complete();
      } else {
        setState(() => _remaining = left);
      }
    });
    setState(() {});
  }

  void _pause() {
    _timer?.cancel();
    _timer = null;
    setState(() {});
  }

  void _reset() {
    _pause();
    setState(() => _remaining = Duration(minutes: _minutes));
  }

  Future<void> _complete() async {
    _pause();
    final app = context.read<AppState>();
    if (_break) {
      NotificationService.instance.showNow(app.t('Break over', 'විවේකය අවසන්'), app.t('Ready for the next session?', 'ඊළඟ සැසියට සූදානම්ද?'));
      setState(() {
        _break = false;
        _setMinutes(app.prefs.sessionMinutes);
      });
      return;
    }
    final studied = _minutes - _remaining.inMinutes;
    setState(() => _remaining = Duration.zero);
    NotificationService.instance.showNow(app.t('Session complete 🎉', 'සැසිය අවසන් 🎉'), app.t('Time for a short break.', 'කෙටි විවේකයක් ගන්න.'));
    await _rate(studied.clamp(1, _minutes));
  }

  Future<void> _finishEarly() async {
    final studied = _minutes - _remaining.inMinutes;
    _pause();
    if (studied < 1) {
      _reset();
      return;
    }
    await _rate(studied);
  }

  Future<void> _rate(int studied) async {
    final app = context.read<AppState>();
    final rating = await showModalBottomSheet<int>(
      context: context,
      isDismissible: false,
      builder: (ctx) => ChangeNotifierProvider.value(value: app, child: _RatingSheet(minutes: studied)),
    );
    if (_subjectId != null && rating != null) {
      await app.logFocusSession(subjectId: _subjectId!, minutes: studied, rating: rating, task: _task);
    }
    if (!mounted) return;
    setState(() {
      _task = null;
      _break = true;
      _setMinutes(app.prefs.breakMinutes);
    });
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(600).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    _subjectId ??= app.subjects.isNotEmpty ? app.subjects.first.id : null;
    if (_subjectId != null && app.subject(_subjectId!) == null) {
      _subjectId = app.subjects.isNotEmpty ? app.subjects.first.id : null;
    }
    final subject = _subjectId == null ? null : app.subject(_subjectId!);
    final color = _break ? AppColors.teal : (subject?.color ?? AppColors.primary);
    final progress = _minutes == 0 ? 0.0 : 1 - _remaining.inSeconds / (_minutes * 60);
    final todaySessions = app.sessions.where((s) => sameDay(s.start, DateTime.now())).length;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            Row(children: [
              Expanded(child: Text(app.t('Focus', 'අවධානය'), style: ts(26, w: FontWeight.w800, c: p.text))),
              Pill(app.t('$todaySessions today · ${fmtMinutes(app.minutesOn(DateTime.now()))}',
                  'අද $todaySessions · ${fmtMinutes(app.minutesOn(DateTime.now()))}'), AppColors.teal,
                  icon: Icons.local_fire_department_rounded),
            ]),
            const SizedBox(height: 18),
            if (app.subjects.isEmpty)
              EmptyState(
                icon: Icons.timer_outlined,
                color: AppColors.teal,
                title: app.t('Add a subject first', 'පළමුව විෂයයක් එක් කරන්න'),
                subtitle: app.t('Focus sessions are tracked per subject.', 'අවධාන සැසි විෂය අනුව සටහන් වේ.'),
              )
            else ...[
              // Subject picker
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    for (final s in app.subjects)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          avatar: Icon(s.iconData, size: 16, color: _subjectId == s.id ? Colors.white : s.color),
                          label: Text(s.name),
                          selected: _subjectId == s.id,
                          showCheckmark: false,
                          selectedColor: s.color,
                          labelStyle: ts(12.5, w: FontWeight.w700, c: _subjectId == s.id ? Colors.white : p.textSoft),
                          onSelected: _running ? null : (_) => setState(() {
                                _subjectId = s.id;
                                _task = null;
                              }),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 28),

              // Timer ring
              Center(
                child: Stack(alignment: Alignment.center, children: [
                  Container(
                    width: 280,
                    height: 280,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: color.withOpacity(_running ? 0.28 : 0.12), blurRadius: 60, spreadRadius: 4)],
                    ),
                  ),
                  ProgressRing(
                    value: progress,
                    size: 270,
                    stroke: 16,
                    colors: [color, Color.lerp(color, Colors.white, 0.35)!],
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Pill(_break ? app.t('Break', 'විවේකය') : app.t('Focus', 'අවධානය'), color,
                          icon: _break ? Icons.free_breakfast_rounded : Icons.psychology_rounded),
                      const SizedBox(height: 10),
                      Text(_fmt(_remaining),
                          style: AppTheme.font(size: 60, weight: FontWeight.w800, color: p.text, spacing: -1)
                              .copyWith(fontFeatures: const [FontFeature.tabularFigures()])),
                      const SizedBox(height: 4),
                      SizedBox(
                        width: 190,
                        child: Text(
                          _task?.title ?? subject?.name ?? '',
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          overflow: TextOverflow.ellipsis,
                          style: ts(13, w: FontWeight.w600, c: p.textMuted),
                        ),
                      ),
                    ]),
                  ),
                ]),
              ),
              const SizedBox(height: 28),

              // Duration presets
              if (!_running && !_started && !_break)
                Center(
                  child: Wrap(spacing: 8, children: [
                    for (final m in {25, app.prefs.sessionMinutes, 60, 90}.toList()..sort())
                      ChoiceChip(
                        label: Text('$m min'),
                        selected: _minutes == m,
                        showCheckmark: false,
                        selectedColor: color,
                        labelStyle: ts(12.5, w: FontWeight.w700, c: _minutes == m ? Colors.white : p.textSoft),
                        onSelected: (_) => setState(() => _setMinutes(m)),
                      ),
                  ]),
                ),
              const SizedBox(height: 24),

              // Controls
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                _RoundBtn(icon: Icons.restart_alt_rounded, onTap: _started ? _reset : null),
                const SizedBox(width: 22),
                GestureDetector(
                  onTap: _running ? _pause : _start,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [color, Color.lerp(color, AppColors.violet, 0.35)!]),
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: color.withOpacity(0.45), blurRadius: 24, offset: const Offset(0, 10))],
                    ),
                    child: Icon(_running ? Icons.pause_rounded : Icons.play_arrow_rounded, color: Colors.white, size: 42),
                  ),
                ),
                const SizedBox(width: 22),
                _RoundBtn(
                  icon: _break ? Icons.skip_next_rounded : Icons.stop_rounded,
                  onTap: _break
                      ? () {
                          _pause();
                          setState(() {
                            _break = false;
                            _setMinutes(app.prefs.sessionMinutes);
                          });
                        }
                      : (_started ? _finishEarly : null),
                ),
              ]),
              const SizedBox(height: 28),
              AppCard(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  const IconBadge(Icons.tips_and_updates_rounded, AppColors.amber, size: 40, radius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _break
                          ? app.t('Stand up, stretch, drink some water. Avoid your phone feed.',
                              'නැගිට, ඇඟ දිගු කර, වතුර බොන්න. දුරකථනයෙන් ඈත් වන්න.')
                          : app.t('Put your phone face-down. After the session, rate your focus — the AI uses it to find your best study hours.',
                              'දුරකථනය යටිකුරු කරන්න. සැසියෙන් පසු ඔබේ අවධානය ශ්‍රේණිගත කරන්න — AI එය ඔබේ හොඳම වේලාවන් සොයා ගැනීමට භාවිතා කරයි.'),
                      style: ts(12.5, c: p.textSoft, h: 1.5),
                    ),
                  ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  const _RoundBtn({required this.icon, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: Material(
        color: p.surface,
        shape: CircleBorder(side: BorderSide(color: p.border)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onTap,
          child: SizedBox(width: 58, height: 58, child: Icon(icon, color: p.text, size: 26)),
        ),
      ),
    );
  }
}

class _RatingSheet extends StatefulWidget {
  final int minutes;
  const _RatingSheet({required this.minutes});

  @override
  State<_RatingSheet> createState() => _RatingSheetState();
}

class _RatingSheetState extends State<_RatingSheet> {
  int _r = 4;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    const faces = [
      Icons.sentiment_very_dissatisfied_rounded,
      Icons.sentiment_dissatisfied_rounded,
      Icons.sentiment_neutral_rounded,
      Icons.sentiment_satisfied_rounded,
      Icons.sentiment_very_satisfied_rounded,
    ];
    final labels = [
      app.t('Distracted', 'අවධානය නැත'),
      app.t('Meh', 'අඩුයි'),
      app.t('Okay', 'හොඳයි'),
      app.t('Focused', 'අවධානයෙන්'),
      app.t('In the zone', 'ඉතා හොඳයි'),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const IconBadge(Icons.celebration_rounded, AppColors.amber, size: 64, radius: 22),
          const SizedBox(height: 8),
          Text(app.t('${fmtMinutes(widget.minutes)} of focus!', 'අවධානයෙන් ${fmtMinutes(widget.minutes)}!'),
              style: ts(20, w: FontWeight.w800, c: p.text)),
          const SizedBox(height: 4),
          Text(app.t('How focused were you?', 'ඔබ කෙතරම් අවධානයෙන් සිටියාද?'), style: ts(13.5, c: p.textSoft)),
          const SizedBox(height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (var i = 0; i < 5; i++)
              GestureDetector(
                onTap: () => setState(() => _r = i + 1),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: _r == i + 1 ? AppColors.primary.withOpacity(0.14) : p.surfaceAlt,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _r == i + 1 ? AppColors.primary : Colors.transparent, width: 2),
                  ),
                  child: Center(child: AnimatedScale(
                    scale: _r == i + 1 ? 1.2 : 1,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(faces[i], size: 30, color: _r == i + 1 ? AppColors.primary : p.textMuted),
                  )),
                ),
              ),
          ]),
          const SizedBox(height: 10),
          Text(labels[_r - 1], style: ts(13, w: FontWeight.w800, c: AppColors.primary)),
          const SizedBox(height: 20),
          GradientButton(
            label: app.t('Save session', 'සැසිය සුරකින්න'),
            icon: Icons.check_rounded,
            onPressed: () => Navigator.pop(context, _r),
          ),
        ]),
      ),
    );
  }
}
