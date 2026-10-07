import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/task_sheets.dart';
import '../widgets/ui.dart';
import 'profile_screen.dart';
import 'shell.dart';
import 'subjects_screen.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final nav = context.read<ShellNav>();
    final p = context.pal;
    final hour = DateTime.now().hour;
    final greet = hour < 12
        ? app.t('Good morning', 'සුභ උදෑසනක්')
        : hour < 17
            ? app.t('Good afternoon', 'සුභ දහවලක්')
            : app.t('Good evening', 'සුභ සන්ධ්‍යාවක්');
    final name = app.user?.isGuest == true ? app.t('Student', 'ශිෂ්‍යයා') : app.user!.name.split(' ').first;
    final today = app.todayTasks;
    final missed = app.missedTasks;
    final next = app.nextTask;
    final exams = app.subjects.where((s) => s.examDate != null && !s.examPassed).toList()
      ..sort((a, b) => a.examDate!.compareTo(b.examDate!));

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            // ── Header ───────────────────────────────────────────────────
            Row(children: [
              GestureDetector(
                onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ProfileScreen())),
                child: Avatar(app.user?.name ?? 'S', size: 46),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(greet, style: ts(12.5, w: FontWeight.w600, c: p.textMuted)),
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(20, w: FontWeight.w800, c: p.text)),
                ]),
              ),
              const LangToggle(),
              const SizedBox(width: 8),
              _IconCircle(
                icon: Icons.notifications_none_rounded,
                dot: next != null,
                onTap: () => _showReminders(context, app),
              ),
            ]),
            const SizedBox(height: 22),

            // ── Hero progress ────────────────────────────────────────────
            FadeSlideIn(child: _HeroCard(app: app, today: today)),
            const SizedBox(height: 16),

            // ── Missed → adaptive reschedule ─────────────────────────────
            if (missed.isNotEmpty) ...[
              FadeSlideIn(delay: 60, child: _MissedBanner(count: missed.length)),
              const SizedBox(height: 16),
            ],

            // ── Up next ──────────────────────────────────────────────────
            if (next != null) ...[
              FadeSlideIn(delay: 100, child: _UpNext(task: next, onStart: () => nav.startFocus(next))),
              const SizedBox(height: 22),
            ],

            // ── Exams ────────────────────────────────────────────────────
            if (exams.isNotEmpty) ...[
              SectionHeader(app.t('Exam countdown', 'විභාග ගණන් කිරීම')),
              SizedBox(
                height: 118,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: exams.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _ExamCard(subject: exams[i]),
                ),
              ),
              const SizedBox(height: 22),
            ],

            // ── Today's plan ─────────────────────────────────────────────
            SectionHeader(
              app.t("Today's plan", 'අද සැලැස්ම'),
              action: app.t('Add task', 'එක් කරන්න'),
              onAction: () => showTaskEditor(context),
            ),
            if (app.subjects.isEmpty)
              EmptyState(
                icon: Icons.library_add_rounded,
                title: app.t('Add your subjects', 'ඔබේ විෂයයන් එක් කරන්න'),
                subtitle: app.t('Add subjects with their exam dates and difficulty so the AI can plan for you.',
                    'AI ට සැලසුම් කිරීමට විෂයයන්, විභාග දින සහ අපහසුතාව එක් කරන්න.'),
                actionLabel: app.t('Add subject', 'විෂයයක් එක් කරන්න'),
                onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubjectsScreen())),
              )
            else if (today.isEmpty)
              EmptyState(
                icon: Icons.auto_awesome_rounded,
                color: AppColors.violet,
                title: app.t('Nothing planned today', 'අද කිසිවක් සැලසුම් කර නැත'),
                subtitle: app.t('Let the AI planner build your personalised timetable in seconds.',
                    'AI සැලසුම්කරුට තත්පර කිහිපයකින් ඔබේ කාලසටහන සෑදීමට ඉඩ දෙන්න.'),
                actionLabel: app.t('Open AI planner', 'AI සැලසුම්කරු'),
                onAction: () => nav.go(2),
              )
            else
              for (final (i, t) in today.indexed)
                FadeSlideIn(
                  delay: 40 * i,
                  child: TaskCard(task: t, onTap: () => showTaskDetail(context, t)),
                ),
            const SizedBox(height: 18),

            // ── Subjects ─────────────────────────────────────────────────
            if (app.subjects.isNotEmpty) ...[
              SectionHeader(
                app.t('My subjects', 'මගේ විෂයයන්'),
                action: app.t('Manage', 'කළමනාකරණය'),
                onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubjectsScreen())),
              ),
              SizedBox(
                height: 150,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  itemCount: app.subjects.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => _SubjectMini(subject: app.subjects[i]),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showReminders(BuildContext context, AppState app) {
    final upcoming = app.tasks
        .where((t) => t.status == TaskStatus.pending && t.end.isAfter(DateTime.now()))
        .toList()
      ..sort((a, b) => a.start.compareTo(b.start));
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final p = ctx.pal;
        return ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.7),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text(app.t('Upcoming reminders', 'ඉදිරි සිහිකැඳවීම්'), style: ts(20, w: FontWeight.w800, c: p.text)),
              const SizedBox(height: 4),
              Text(
                app.prefs.remindersOn
                    ? app.t('You\'ll be notified ${app.prefs.reminderLeadMinutes} min before each session.',
                        'සෑම සැසියකටම මිනිත්තු ${app.prefs.reminderLeadMinutes}කට පෙර දැනුම් දෙනු ලැබේ.')
                    : app.t('Reminders are turned off in Settings.', 'සිහිකැඳවීම් සැකසුම් තුළ අක්‍රියයි.'),
                style: ts(13, c: p.textSoft),
              ),
              const SizedBox(height: 16),
              if (upcoming.isEmpty)
                Text(app.t('No upcoming sessions.', 'ඉදිරි සැසි නැත.'), style: ts(13, c: p.textMuted)),
              for (final t in upcoming.take(12))
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(children: [
                    IconBadge(Icons.notifications_active_rounded, app.subjectColor(t.subjectId), size: 40, radius: 12),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13.5, w: FontWeight.w700, c: p.text)),
                        Text('${relativeDay(ctx, t.start)} · ${fmtTime(ctx, t.start.subtract(Duration(minutes: app.prefs.reminderLeadMinutes)))}',
                            style: ts(12, c: p.textMuted)),
                      ]),
                    ),
                  ]),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _IconCircle extends StatelessWidget {
  final IconData icon;
  final bool dot;
  final VoidCallback onTap;
  const _IconCircle({required this.icon, required this.onTap, this.dot = false});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle, border: Border.all(color: p.border)),
        child: Stack(alignment: Alignment.center, children: [
          Icon(icon, size: 21, color: p.text),
          if (dot)
            Positioned(
              top: 10,
              right: 11,
              child: Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(color: AppColors.rose, shape: BoxShape.circle, border: Border.all(color: p.surface, width: 1.5)),
              ),
            ),
        ]),
      ),
    );
  }
}

class _HeroCard extends StatelessWidget {
  final AppState app;
  final List<StudyTask> today;
  const _HeroCard({required this.app, required this.today});

  @override
  Widget build(BuildContext context) {
    final mins = app.minutesOn(DateTime.now());
    final done = today.where((t) => t.isDone).length;
    return AppCard(
      gradient: const LinearGradient(
        colors: [Color(0xFF4F46E5), Color(0xFF7C3AED), Color(0xFFA855F7)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      padding: const EdgeInsets.all(20),
      child: Row(children: [
        ProgressRing(
          value: app.todayGoalProgress,
          size: 108,
          stroke: 11,
          colors: const [Color(0xFFFDE68A), Colors.white],
          track: Colors.white.withOpacity(0.18),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('${(app.todayGoalProgress * 100).round()}%', style: ts(22, w: FontWeight.w800, c: Colors.white)),
            Text(app.t('of goal', 'ඉලක්කයෙන්'), style: ts(10.5, w: FontWeight.w600, c: Colors.white70)),
          ]),
        ),
        const SizedBox(width: 18),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(app.t('Today\'s progress', 'අද ප්‍රගතිය'), style: ts(13, w: FontWeight.w600, c: Colors.white70)),
            const SizedBox(height: 2),
            Text('${fmtMinutes(mins)} / ${fmtMinutes(app.prefs.dailyGoalMinutes)}',
                style: ts(21, w: FontWeight.w800, c: Colors.white)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              _GlassChip(icon: Icons.local_fire_department_rounded, text: app.t('${app.streak} day streak', 'දින ${app.streak}ක')),
              _GlassChip(icon: Icons.task_alt_rounded, text: '$done/${today.length}'),
            ]),
          ]),
        ),
      ]),
    );
  }
}

class _GlassChip extends StatelessWidget {
  final IconData icon;
  final String text;
  const _GlassChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: const Color(0xFFFDE68A)),
          const SizedBox(width: 5),
          Text(text, style: ts(11.5, w: FontWeight.w700, c: Colors.white)),
        ]),
      );
}

class _MissedBanner extends StatefulWidget {
  final int count;
  const _MissedBanner({required this.count});

  @override
  State<_MissedBanner> createState() => _MissedBannerState();
}

class _MissedBannerState extends State<_MissedBanner> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    return AppCard(
      color: AppColors.amber.withOpacity(p.isDark ? 0.14 : 0.1),
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        const IconBadge(Icons.event_busy_rounded, AppColors.amber, size: 44),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(app.t('${widget.count} missed session${widget.count == 1 ? '' : 's'}', 'මඟහැරුණු සැසි ${widget.count}'),
                style: ts(14, w: FontWeight.w800, c: p.text)),
            Text(app.t('Let AI fit them into your free time', 'AI ට ඒවා ඔබේ නිදහස් කාලයට යෙදීමට ඉඩ දෙන්න'),
                style: ts(12, c: p.textSoft)),
          ]),
        ),
        const SizedBox(width: 8),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final r = await app.rescheduleMissed();
                  if (!context.mounted) return;
                  setState(() => _busy = false);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text(r.unplaced == 0
                        ? app.t('${r.moved} session(s) rescheduled', 'සැසි ${r.moved}ක් නැවත සකසන ලදී')
                        : app.t('${r.moved} moved · ${r.unplaced} couldn\'t fit before the exam',
                            '${r.moved}ක් ගෙනගියා · ${r.unplaced}ක් ඉඩ නැත')),
                  ));
                },
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.amber,
            minimumSize: const Size(0, 40),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
          child: Text(app.t('Fix', 'සකසන්න'), style: ts(13, w: FontWeight.w800, c: Colors.white)),
        ),
      ]),
    );
  }
}

class _UpNext extends StatelessWidget {
  final StudyTask task;
  final VoidCallback onStart;
  const _UpNext({required this.task, required this.onStart});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final s = app.subject(task.subjectId);
    final color = s?.color ?? AppColors.primary;
    final now = DateTime.now();
    final live = task.start.isBefore(now);
    final diff = task.start.difference(now);
    final when = live
        ? app.t('Happening now', 'දැන් සිදුවෙමින්')
        : diff.inMinutes < 60
            ? app.t('in ${diff.inMinutes} min', 'මිනිත්තු ${diff.inMinutes}කින්')
            : '${relativeDay(context, task.start)} · ${fmtTime(context, task.start)}';

    return AppCard(
      onTap: () => showTaskDetail(context, task),
      padding: const EdgeInsets.all(16),
      child: Row(children: [
        IconBadge(s?.iconData ?? Icons.menu_book_rounded, color, size: 52, radius: 16),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(width: 7, height: 7, decoration: BoxDecoration(color: live ? AppColors.green : color, shape: BoxShape.circle)),
              const SizedBox(width: 6),
              Text(app.t('UP NEXT', 'ඊළඟට'), style: AppTheme.font(size: 10.5, weight: FontWeight.w800, color: p.textMuted, spacing: 1.2)),
              const SizedBox(width: 6),
              Flexible(child: Text('· $when', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: ts(11.5, w: FontWeight.w700, c: live ? AppColors.green : color))),
            ]),
            const SizedBox(height: 4),
            Text(task.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(15, w: FontWeight.w800, c: p.text)),
          ]),
        ),
        const SizedBox(width: 10),
        GestureDetector(
          onTap: onStart,
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AppColors.focusGradient,
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(color: AppColors.teal.withOpacity(0.4), blurRadius: 14, offset: const Offset(0, 6))],
            ),
            child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 28),
          ),
        ),
      ]),
    );
  }
}

class _ExamCard extends StatelessWidget {
  final Subject subject;
  const _ExamCard({required this.subject});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final d = subject.daysToExam!;
    final urgent = d <= 7;
    return SizedBox(
      width: 160,
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(subject.iconData, size: 18, color: subject.color),
            const Spacer(),
            if (urgent) const Icon(Icons.priority_high_rounded, size: 16, color: AppColors.rose),
          ]),
          const Spacer(),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(d == 0 ? app.t('Today', 'අද') : '$d',
                style: ts(26, w: FontWeight.w800, c: urgent ? AppColors.rose : p.text, h: 1)),
            if (d != 0) ...[
              const SizedBox(width: 4),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(app.t(d == 1 ? 'day' : 'days', 'දින'), style: ts(12, w: FontWeight.w700, c: p.textMuted)),
              ),
            ],
          ]),
          const SizedBox(height: 4),
          Text(subject.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, w: FontWeight.w700, c: p.textSoft)),
        ]),
      ),
    );
  }
}

class _SubjectMini extends StatelessWidget {
  final Subject subject;
  const _SubjectMini({required this.subject});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final prog = app.subjectProgress(subject);
    return SizedBox(
      width: 150,
      child: AppCard(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubjectsScreen())),
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          IconBadge(subject.iconData, subject.color, size: 38, radius: 12),
          const Spacer(),
          Text(subject.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w800, c: p.text, h: 1.25)),
          const SizedBox(height: 8),
          SoftProgressBar(value: prog, color: subject.color, height: 6),
          const SizedBox(height: 6),
          Text('${fmtMinutes(app.minutesForSubject(subject.id))} / ${subject.targetHours}h',
              style: ts(11, w: FontWeight.w600, c: p.textMuted)),
        ]),
      ),
    );
  }
}
