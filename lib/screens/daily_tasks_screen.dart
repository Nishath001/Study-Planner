import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/daily_task_ui.dart';
import '../widgets/ui.dart';

class DailyTasksScreen extends StatefulWidget {
  const DailyTasksScreen({super.key});

  @override
  State<DailyTasksScreen> createState() => _DailyTasksScreenState();
}

class _DailyTasksScreenState extends State<DailyTasksScreen> {
  DateTime _day = dateOnly(DateTime.now());
  TaskCategory? _filter;
  bool _showDone = true;
  final _strip = ScrollController(initialScrollOffset: 3 * 60.0);

  static const _back = 3, _ahead = 17; // days shown before / after today

  @override
  void dispose() {
    _strip.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final today = dateOnly(DateTime.now());
    final isToday = _day == today;
    final all = app.dailyFor(_day);
    final list = _filter == null ? all : all.where((x) => x.category == _filter).toList();
    final open = list.where((x) => !x.doneOn(_day)).toList();
    final done = list.where((x) => x.doneOn(_day)).toList();
    final overdue = isToday ? app.overdueDaily.where((x) => _filter == null || x.category == _filter).toList() : <DailyTask>[];
    final (doneCount, total) = app.dailyProgress(_day);
    final highLeft = all.where((x) => !x.doneOn(_day) && x.priority == TaskPriority.high).length;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showDailyTaskEditor(context, day: _day),
        backgroundColor: AppColors.teal,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(app.t('New task', 'නව කාර්යය'), style: ts(14, w: FontWeight.w800, c: Colors.white)),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
          children: [
            // ── Header ─────────────────────────────────────────────────
            Row(children: [
              if (Navigator.canPop(context))
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(Icons.arrow_back_rounded, color: p.text),
                  padding: EdgeInsets.zero,
                  visualDensity: VisualDensity.compact,
                ),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(app.t('Daily tasks', 'දෛනික කාර්යයන්'), style: ts(26, w: FontWeight.w800, c: p.text)),
                  Text(DateFormat.yMMMMEEEEd(context.locale).format(_day), style: ts(13, c: p.textMuted)),
                ]),
              ),
              if (!isToday)
                TextButton(onPressed: () => _jump(today), child: Text(app.t('Today', 'අද'))),
            ]),
            const SizedBox(height: 16),

            // ── Day strip ──────────────────────────────────────────────
            SizedBox(
              height: 84,
              child: ListView.builder(
                controller: _strip,
                scrollDirection: Axis.horizontal,
                itemCount: _back + _ahead + 1,
                itemBuilder: (_, i) {
                  final d = today.add(Duration(days: i - _back));
                  final (dn, tot) = app.dailyProgress(d);
                  return _DayPill(
                    day: d,
                    selected: d == _day,
                    isToday: d == today,
                    progress: tot == 0 ? null : dn / tot,
                    onTap: () => setState(() => _day = d),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // ── Summary ────────────────────────────────────────────────
            AppCard(
              gradient: const LinearGradient(
                colors: [Color(0xFF0F766E), Color(0xFF0D9488), Color(0xFF0EA5E9)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              padding: const EdgeInsets.all(18),
              child: Row(children: [
                ProgressRing(
                  value: total == 0 ? 0 : doneCount / total,
                  size: 84,
                  stroke: 9,
                  colors: const [Color(0xFFFDE68A), Colors.white],
                  track: Colors.white.withOpacity(0.2),
                  child: Text(total == 0 ? '—' : '${(doneCount / total * 100).round()}%',
                      style: ts(18, w: FontWeight.w800, c: Colors.white)),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      total == 0
                          ? app.t('A clear day', 'නිදහස් දිනයක්')
                          : doneCount == total
                              ? app.t('All done — great work!', 'සියල්ල අවසන් — නියමයි!')
                              : app.t('$doneCount of $total done', '$total න් $doneCount ක් අවසන්'),
                      style: ts(18, w: FontWeight.w800, c: Colors.white),
                    ),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      _glass(Icons.radio_button_unchecked_rounded, app.t('${total - doneCount} left', 'ඉතිරි ${total - doneCount}')),
                      if (highLeft > 0) _glass(Icons.flag_rounded, app.t('$highLeft high', 'ඉහළ $highLeft')),
                      if (overdue.isNotEmpty) _glass(Icons.history_rounded, app.t('${overdue.length} overdue', 'ප්‍රමාද ${overdue.length}')),
                    ]),
                  ]),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            QuickAddTask(day: _day),
            const SizedBox(height: 14),

            // ── Category filter ────────────────────────────────────────
            SizedBox(
              height: 40,
              child: ListView(scrollDirection: Axis.horizontal, children: [
                _filterChip(app.t('All', 'සියල්ල'), null, Icons.apps_rounded, AppColors.primary, all.length),
                for (final c in TaskCategory.values)
                  if (all.any((x) => x.category == c))
                    () {
                      final m = categoryMeta(app, c);
                      return _filterChip(m.$1, c, m.$2, m.$3, all.where((x) => x.category == c).length);
                    }(),
              ]),
            ),
            const SizedBox(height: 18),

            // ── Overdue ────────────────────────────────────────────────
            if (overdue.isNotEmpty) ...[
              _sectionTitle(app.t('Overdue', 'ප්‍රමාද වූ'), overdue.length, AppColors.rose,
                  action: app.t('Move all to today', 'සියල්ල අදට'),
                  onAction: () => app.moveDailyToToday(overdue)),
              for (final x in overdue)
                DailyTaskTile(
                  task: x,
                  day: x.date,
                  trailing: IconButton(
                    tooltip: app.t('Move to today', 'අදට ගෙනයන්න'),
                    icon: const Icon(Icons.redo_rounded, color: AppColors.rose, size: 20),
                    onPressed: () => app.moveDailyToToday([x]),
                  ),
                ),
              const SizedBox(height: 10),
            ],

            // ── To do ──────────────────────────────────────────────────
            if (list.isEmpty && overdue.isEmpty)
              EmptyState(
                icon: Icons.task_alt_rounded,
                color: AppColors.teal,
                title: _filter == null ? app.t('No tasks for this day', 'මෙම දිනයට කාර්යයන් නැත') : app.t('Nothing in this category', 'මෙම වර්ගයේ කිසිවක් නැත'),
                subtitle: app.t('Add assignments, errands or habits — anything you want to get done.',
                    'පැවරුම්, කටයුතු හෝ පුරුදු — ඔබට කිරීමට අවශ්‍ය ඕනෑම දෙයක් එක් කරන්න.'),
                actionLabel: app.t('New task', 'නව කාර්යය'),
                onAction: () => showDailyTaskEditor(context, day: _day),
              ),
            if (open.isNotEmpty) ...[
              _sectionTitle(app.t('To do', 'කළ යුතු'), open.length, AppColors.teal),
              for (final (i, x) in open.indexed)
                FadeSlideIn(delay: 30 * i, child: DailyTaskTile(key: ValueKey(x.id), task: x, day: _day)),
            ],
            if (done.isNotEmpty) ...[
              const SizedBox(height: 6),
              _sectionTitle(app.t('Completed', 'අවසන්'), done.length, AppColors.green,
                  action: _showDone ? app.t('Hide', 'සඟවන්න') : app.t('Show', 'පෙන්වන්න'),
                  onAction: () => setState(() => _showDone = !_showDone)),
              if (_showDone)
                for (final x in done) DailyTaskTile(key: ValueKey(x.id), task: x, day: _day, compact: true),
            ],
            if (list.isNotEmpty) ...[
              const SizedBox(height: 8),
              Center(
                child: Text(app.t('Tip: swipe right to complete, left to delete', 'ඉඟිය: අවසන් කිරීමට දකුණට, මැකීමට වමට ස්වයිප් කරන්න'),
                    style: ts(11.5, c: p.textMuted)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _jump(DateTime d) {
    setState(() => _day = d);
    _strip.animateTo(3 * 60.0, duration: const Duration(milliseconds: 300), curve: Curves.easeOutCubic);
  }

  Widget _glass(IconData i, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.16),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white.withOpacity(0.2)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 13, color: const Color(0xFFFDE68A)),
          const SizedBox(width: 4),
          Text(t, style: ts(11.5, w: FontWeight.w700, c: Colors.white)),
        ]),
      );

  Widget _filterChip(String label, TaskCategory? value, IconData icon, Color color, int count) {
    final p = context.pal;
    final sel = _filter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        avatar: Icon(icon, size: 16, color: sel ? Colors.white : color),
        label: Text('$label  $count'),
        selected: sel,
        showCheckmark: false,
        selectedColor: color,
        labelStyle: ts(12.5, w: FontWeight.w700, c: sel ? Colors.white : p.textSoft),
        onSelected: (_) => setState(() => _filter = value),
      ),
    );
  }

  Widget _sectionTitle(String title, int count, Color color, {String? action, VoidCallback? onAction}) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(title, style: ts(15, w: FontWeight.w800, c: p.text)),
        const SizedBox(width: 6),
        Text('$count', style: ts(13, w: FontWeight.w800, c: p.textMuted)),
        const Spacer(),
        if (action != null)
          GestureDetector(onTap: onAction, child: Text(action, style: ts(12.5, w: FontWeight.w800, c: color))),
      ]),
    );
  }
}

class _DayPill extends StatelessWidget {
  final DateTime day;
  final bool selected, isToday;
  final double? progress;
  final VoidCallback onTap;
  const _DayPill({required this.day, required this.selected, required this.isToday, required this.progress, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final fg = selected ? Colors.white : p.text;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        width: 52,
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          gradient: selected ? const LinearGradient(colors: [Color(0xFF0D9488), Color(0xFF0EA5E9)], begin: Alignment.topCenter, end: Alignment.bottomCenter) : null,
          color: selected ? null : p.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: selected ? Colors.transparent : (isToday ? AppColors.teal : p.border), width: isToday && !selected ? 1.6 : 1),
          boxShadow: selected ? [BoxShadow(color: AppColors.teal.withOpacity(0.35), blurRadius: 12, offset: const Offset(0, 5))] : null,
        ),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(DateFormat.E(context.locale).format(day),
              maxLines: 1, overflow: TextOverflow.clip,
              style: ts(10.5, w: FontWeight.w700, c: selected ? Colors.white70 : p.textMuted)),
          const SizedBox(height: 4),
          Text('${day.day}', style: ts(18, w: FontWeight.w800, c: fg)),
          const SizedBox(height: 6),
          SizedBox(
            width: 26,
            height: 4,
            child: progress == null
                ? null
                : ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: selected ? Colors.white24 : p.surfaceAlt,
                      color: selected ? Colors.white : (progress == 1 ? AppColors.green : AppColors.teal),
                    ),
                  ),
          ),
        ]),
      ),
    );
  }
}
