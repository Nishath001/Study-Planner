import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:table_calendar/table_calendar.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/task_sheets.dart';
import '../widgets/ui.dart';
import 'shell.dart';

class PlanScreen extends StatefulWidget {
  const PlanScreen({super.key});

  @override
  State<PlanScreen> createState() => _PlanScreenState();
}

class _PlanScreenState extends State<PlanScreen> {
  DateTime _focused = DateTime.now();
  DateTime _selected = DateTime.now();
  CalendarFormat _format = CalendarFormat.week;

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final tasks = app.tasksOn(_selected);
    final planned = tasks.where((t) => t.status != TaskStatus.skipped).fold<int>(0, (a, t) => a + t.durationMinutes);
    final available = app.prefs.minutesFor(_selected);
    final done = tasks.where((t) => t.isDone).length;
    final examsToday = app.subjects.where((s) => s.examDate != null && sameDay(s.examDate!, _selected)).toList();

    return Scaffold(
      floatingActionButton: Padding(
        padding: const EdgeInsets.only(bottom: 84),
        child: FloatingActionButton(
          onPressed: () => showTaskEditor(context, day: _selected),
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: const Icon(Icons.add_rounded, size: 28),
        ),
      ),
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            Row(children: [
              Expanded(child: Text(app.t('Study plan', 'අධ්‍යයන සැලැස්ම'), style: ts(26, w: FontWeight.w800, c: p.text))),
              _FormatToggle(
                month: _format == CalendarFormat.month,
                labels: (app.t('Week', 'සතිය'), app.t('Month', 'මාසය')),
                onChanged: (m) => setState(() => _format = m ? CalendarFormat.month : CalendarFormat.week),
              ),
            ]),
            const SizedBox(height: 16),
            AppCard(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: TableCalendar<StudyTask>(
                locale: context.locale,
                firstDay: DateTime.now().subtract(const Duration(days: 365)),
                lastDay: DateTime.now().add(const Duration(days: 365)),
                focusedDay: _focused,
                calendarFormat: _format,
                startingDayOfWeek: StartingDayOfWeek.monday,
                availableCalendarFormats: const {CalendarFormat.week: 'Week', CalendarFormat.month: 'Month'},
                selectedDayPredicate: (d) => isSameDay(d, _selected),
                onDaySelected: (s, f) => setState(() {
                  _selected = s;
                  _focused = f;
                }),
                onPageChanged: (f) => _focused = f,
                eventLoader: (d) => app.tasksOn(d),
                headerStyle: HeaderStyle(
                  formatButtonVisible: false,
                  titleCentered: true,
                  titleTextStyle: ts(15, w: FontWeight.w800, c: p.text),
                  leftChevronIcon: Icon(Icons.chevron_left_rounded, color: p.textSoft),
                  rightChevronIcon: Icon(Icons.chevron_right_rounded, color: p.textSoft),
                ),
                daysOfWeekStyle: DaysOfWeekStyle(
                  weekdayStyle: ts(11.5, w: FontWeight.w700, c: p.textMuted),
                  weekendStyle: ts(11.5, w: FontWeight.w700, c: p.textMuted),
                ),
                daysOfWeekHeight: 26,
                rowHeight: 50,
                calendarStyle: CalendarStyle(
                  outsideDaysVisible: false,
                  defaultTextStyle: ts(14, w: FontWeight.w700, c: p.text),
                  weekendTextStyle: ts(14, w: FontWeight.w700, c: p.textSoft),
                  todayDecoration: BoxDecoration(color: AppColors.primary.withOpacity(0.12), shape: BoxShape.circle),
                  todayTextStyle: ts(14, w: FontWeight.w800, c: AppColors.primary),
                  selectedDecoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
                  selectedTextStyle: ts(14, w: FontWeight.w800, c: Colors.white),
                ),
                calendarBuilders: CalendarBuilders(
                  markerBuilder: (ctx, day, events) {
                    if (events.isEmpty) return null;
                    final exam = app.subjects.any((s) => s.examDate != null && sameDay(s.examDate!, day));
                    return Positioned(
                      bottom: 4,
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        for (final e in events.take(3))
                          Container(
                            width: 5,
                            height: 5,
                            margin: const EdgeInsets.symmetric(horizontal: 1),
                            decoration: BoxDecoration(
                              color: e.isDone ? p.textMuted : app.subjectColor(e.subjectId),
                              shape: BoxShape.circle,
                            ),
                          ),
                        if (exam) const Icon(Icons.star_rounded, size: 8, color: AppColors.rose),
                      ]),
                    );
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(relativeDay(context, _selected), style: ts(19, w: FontWeight.w800, c: p.text)),
                  Text(
                    app.t('${tasks.length} sessions · $done done', 'සැසි ${tasks.length} · $done අවසන්'),
                    style: ts(12.5, c: p.textMuted),
                  ),
                ]),
              ),
              _LoadMeter(planned: planned, available: available),
            ]),
            const SizedBox(height: 14),
            for (final s in examsToday)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: AppCard(
                  color: AppColors.rose.withOpacity(0.1),
                  padding: const EdgeInsets.all(14),
                  child: Row(children: [
                    const Icon(Icons.emoji_events_rounded, color: AppColors.rose),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(app.t('${s.name} exam — good luck!', '${s.name} විභාගය — සුභ පැතුම්!'),
                          style: ts(13.5, w: FontWeight.w800, c: p.text)),
                    ),
                  ]),
                ),
              ),
            if (tasks.isEmpty)
              EmptyState(
                icon: Icons.event_available_rounded,
                title: app.t('A free day', 'නිදහස් දිනයක්'),
                subtitle: app.t('Add a task or let the AI fill it based on your availability.',
                    'කාර්යයක් එක් කරන්න හෝ AI ට ඔබේ නිදහස් කාලය අනුව සැලසුම් කිරීමට ඉඩ දෙන්න.'),
                actionLabel: app.t('Plan with AI', 'AI සමඟ සැලසුම් කරන්න'),
                onAction: () => context.read<ShellNav>().go(2),
                color: AppColors.violet,
              )
            else
              _Timeline(tasks: tasks),
          ],
        ),
      ),
    );
  }
}

class _Timeline extends StatelessWidget {
  final List<StudyTask> tasks;
  const _Timeline({required this.tasks});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Column(children: [
      for (final (i, t) in tasks.indexed)
        FadeSlideIn(
          delay: 30 * i,
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(
              width: 58,
              child: Padding(
                padding: const EdgeInsets.only(top: 16, right: 6),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(fmtTime(context, t.start),
                      style: ts(11.5, w: FontWeight.w800, c: t.isDone ? p.textMuted : p.textSoft)),
                ),
              ),
            ),
            Expanded(child: TaskCard(task: t, onTap: () => showTaskDetail(context, t))),
          ]),
        ),
    ]);
  }
}

class _LoadMeter extends StatelessWidget {
  final int planned, available;
  const _LoadMeter({required this.planned, required this.available});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final ratio = available == 0 ? (planned > 0 ? 1.2 : 0.0) : planned / available;
    final color = ratio > 1 ? AppColors.rose : (ratio > 0.85 ? AppColors.amber : AppColors.teal);
    return Row(children: [
      ProgressRing(
        value: ratio.clamp(0, 1).toDouble(),
        size: 44,
        stroke: 5,
        colors: [color, color],
        child: Icon(Icons.bolt_rounded, size: 18, color: color),
      ),
      const SizedBox(width: 10),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Text('${fmtMinutes(planned)} / ${fmtMinutes(available)}', style: ts(13, w: FontWeight.w800, c: p.text)),
        Text(app.t('planned / free', 'සැලසුම් / නිදහස්'), style: ts(11, c: p.textMuted)),
      ]),
    ]);
  }
}

class _FormatToggle extends StatelessWidget {
  final bool month;
  final (String, String) labels;
  final ValueChanged<bool> onChanged;
  const _FormatToggle({required this.month, required this.labels, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    Widget seg(String l, bool sel, bool v) => GestureDetector(
          onTap: () => onChanged(v),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: sel ? p.text : Colors.transparent,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(l, style: ts(12, w: FontWeight.w800, c: sel ? p.bg : p.textSoft)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(color: p.surface, borderRadius: BorderRadius.circular(24), border: Border.all(color: p.border)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [seg(labels.$1, !month, false), seg(labels.$2, month, true)]),
    );
  }
}
