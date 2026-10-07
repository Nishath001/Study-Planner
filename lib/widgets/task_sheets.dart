import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../screens/shell.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

/// Detail sheet for a task: start focus, complete, skip, reschedule, edit, delete.
Future<void> showTaskDetail(BuildContext context, StudyTask task) {
  final nav = context.read<ShellNav?>();
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider<AppState>.value(
      value: context.read<AppState>(),
      child: _TaskDetail(task: task, nav: nav),
    ),
  );
}

class _TaskDetail extends StatelessWidget {
  final StudyTask task;
  final ShellNav? nav;
  const _TaskDetail({required this.task, this.nav});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final s = app.subject(task.subjectId);
    final color = s?.color ?? AppColors.primary;

    Widget action(IconData icon, String label, Color c, VoidCallback onTap) => Expanded(
          child: AppCard(
            onTap: onTap,
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Column(children: [
              Icon(icon, color: c, size: 22),
              const SizedBox(height: 6),
              Text(label, textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: ts(11.5, w: FontWeight.w700, c: p.textSoft)),
            ]),
          ),
        );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            IconBadge(s?.iconData ?? Icons.menu_book_rounded, color, size: 52, radius: 16),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s?.name ?? '', style: ts(12.5, w: FontWeight.w700, c: color)),
                const SizedBox(height: 2),
                Text(task.title, style: ts(18, w: FontWeight.w800, c: p.text, h: 1.25)),
              ]),
            ),
          ]),
          const SizedBox(height: 16),
          Wrap(spacing: 8, runSpacing: 8, children: [
            Pill('${relativeDay(context, task.start)} · ${fmtTime(context, task.start)}', AppColors.primary,
                icon: Icons.event_rounded),
            Pill(fmtMinutes(task.durationMinutes), AppColors.teal, icon: Icons.timer_outlined),
            Pill(app.typeLabel(task.type), AppColors.violet, icon: Icons.school_outlined),
            if (task.aiGenerated) Pill(app.t('AI planned', 'AI සැලසුම්'), AppColors.rose, icon: Icons.auto_awesome),
            if (task.rescheduleCount > 0)
              Pill(app.t('Moved ${task.rescheduleCount}×', '${task.rescheduleCount} වරක් ගෙනගියා'), AppColors.amber,
                  icon: Icons.replay_rounded),
          ]),
          if (task.notes.isNotEmpty) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(14)),
              child: Text(task.notes, style: ts(13, c: p.textSoft, h: 1.5)),
            ),
          ],
          const SizedBox(height: 20),
          if (!task.isDone && nav != null) ...[
            GradientButton(
              label: app.t('Start focus session', 'අවධාන සැසිය අරඹන්න'),
              icon: Icons.play_arrow_rounded,
              gradient: AppColors.focusGradient,
              onPressed: () {
                Navigator.pop(context);
                nav!.startFocus(task);
              },
            ),
            const SizedBox(height: 12),
          ],
          Row(children: [
            action(task.isDone ? Icons.undo_rounded : Icons.check_circle_rounded,
                task.isDone ? app.t('Undo', 'අහෝසි') : app.t('Done', 'අවසන්'), AppColors.green, () {
              app.toggleTask(task);
              Navigator.pop(context);
            }),
            const SizedBox(width: 8),
            action(Icons.event_repeat_rounded, app.t('Move', 'වෙනස් කරන්න'), AppColors.amber, () async {
              final moved = await _pickDateTime(context, task.start);
              if (moved == null) return;
              task
                ..start = moved
                ..status = TaskStatus.pending
                ..rescheduleCount += 1;
              await app.upsertTask(task);
              if (context.mounted) Navigator.pop(context);
            }),
            const SizedBox(width: 8),
            action(Icons.edit_rounded, app.t('Edit', 'සංස්කරණය'), AppColors.primary, () {
              Navigator.pop(context);
              showTaskEditor(context, existing: task);
            }),
            const SizedBox(width: 8),
            action(Icons.delete_outline_rounded, app.t('Delete', 'මකන්න'), AppColors.rose, () {
              app.deleteTask(task.id);
              Navigator.pop(context);
            }),
          ]),
          if (task.status == TaskStatus.pending) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: () {
                app.setTaskStatus(task, TaskStatus.skipped);
                Navigator.pop(context);
              },
              child: Text(app.t('Skip this session', 'මෙම සැසිය මඟහරින්න'),
                  style: ts(13, w: FontWeight.w700, c: p.textMuted)),
            ),
          ],
        ]),
      ),
    );
  }
}

Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final now = DateTime.now();
  final d = await showDatePicker(
    context: context,
    initialDate: initial.isBefore(now) ? now : initial,
    firstDate: dateOnly(now),
    lastDate: now.add(const Duration(days: 365)),
  );
  if (d == null || !context.mounted) return null;
  final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initial));
  if (t == null) return null;
  return DateTime(d.year, d.month, d.day, t.hour, t.minute);
}

/// Add or edit a manual study task.
Future<void> showTaskEditor(BuildContext context, {StudyTask? existing, DateTime? day}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider<AppState>.value(
      value: context.read<AppState>(),
      child: _TaskEditor(existing: existing, day: day),
    ),
  );
}

class _TaskEditor extends StatefulWidget {
  final StudyTask? existing;
  final DateTime? day;
  const _TaskEditor({this.existing, this.day});

  @override
  State<_TaskEditor> createState() => _TaskEditorState();
}

class _TaskEditorState extends State<_TaskEditor> {
  late final _title = TextEditingController(text: widget.existing?.title ?? '');
  late final _notes = TextEditingController(text: widget.existing?.notes ?? '');
  late String? _subjectId = widget.existing?.subjectId;
  late DateTime _start = widget.existing?.start ?? _defaultStart();
  late int _duration = widget.existing?.durationMinutes ?? 60;
  late SessionType _type = widget.existing?.type ?? SessionType.custom;

  DateTime _defaultStart() {
    final now = DateTime.now();
    final base = widget.day ?? now;
    final hour = sameDay(base, now) ? (now.hour + 1).clamp(0, 22) : 9;
    return DateTime(base.year, base.month, base.day, hour);
  }

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    _subjectId ??= app.subjects.isNotEmpty ? app.subjects.first.id : null;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(widget.existing == null ? app.t('New study task', 'නව අධ්‍යයන කාර්යය') : app.t('Edit task', 'කාර්යය සංස්කරණය'),
                style: ts(20, w: FontWeight.w800, c: p.text)),
            const SizedBox(height: 18),
            if (app.subjects.isEmpty)
              Text(app.t('Add a subject first.', 'පළමුව විෂයයක් එක් කරන්න.'), style: ts(13, c: AppColors.rose))
            else
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
                          onSelected: (_) => setState(() => _subjectId = s.id),
                        ),
                      ),
                  ],
                ),
              ),
            const SizedBox(height: 14),
            TextField(
              controller: _title,
              decoration: InputDecoration(
                hintText: app.t('What will you study? e.g. Chapter 4 – TCP/IP', 'ඔබ ඉගෙන ගන්නේ කුමක්ද?'),
                prefixIcon: const Icon(Icons.edit_note_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: _PickerTile(
                  icon: Icons.event_rounded,
                  label: fmtDay(context, _start),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _start,
                      firstDate: DateTime.now().subtract(const Duration(days: 30)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _start = DateTime(d.year, d.month, d.day, _start.hour, _start.minute));
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _PickerTile(
                  icon: Icons.schedule_rounded,
                  label: fmtTime(context, _start),
                  onTap: () async {
                    final t = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(_start));
                    if (t != null) setState(() => _start = DateTime(_start.year, _start.month, _start.day, t.hour, t.minute));
                  },
                ),
              ),
            ]),
            const SizedBox(height: 14),
            Text(app.t('Duration', 'කාලය'), style: ts(13, w: FontWeight.w800, c: p.textSoft)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final m in [25, 45, 60, 90, 120])
                ChoiceChip(
                  label: Text(fmtMinutes(m)),
                  selected: _duration == m,
                  showCheckmark: false,
                  selectedColor: AppColors.primary,
                  labelStyle: ts(12.5, w: FontWeight.w700, c: _duration == m ? Colors.white : p.textSoft),
                  onSelected: (_) => setState(() => _duration = m),
                ),
            ]),
            const SizedBox(height: 14),
            Text(app.t('Type', 'වර්ගය'), style: ts(13, w: FontWeight.w800, c: p.textSoft)),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final t in SessionType.values)
                ChoiceChip(
                  label: Text(app.typeLabel(t)),
                  selected: _type == t,
                  showCheckmark: false,
                  selectedColor: AppColors.violet,
                  labelStyle: ts(12, w: FontWeight.w700, c: _type == t ? Colors.white : p.textSoft),
                  onSelected: (_) => setState(() => _type = t),
                ),
            ]),
            const SizedBox(height: 14),
            TextField(
              controller: _notes,
              maxLines: 3,
              minLines: 2,
              decoration: InputDecoration(hintText: app.t('Notes (optional)', 'සටහන් (අත්‍යවශ්‍ය නැත)')),
            ),
            const SizedBox(height: 20),
            GradientButton(
              label: app.t('Save task', 'සුරකින්න'),
              icon: Icons.check_rounded,
              onPressed: _subjectId == null
                  ? null
                  : () {
                      final s = app.subject(_subjectId!)!;
                      final title = _title.text.trim().isEmpty ? '${s.name} · ${app.typeLabel(_type)}' : _title.text.trim();
                      final x = widget.existing ??
                          StudyTask(
                            id: 'm_${DateTime.now().microsecondsSinceEpoch}',
                            subjectId: s.id,
                            title: title,
                            start: _start,
                            durationMinutes: _duration,
                          );
                      x
                        ..subjectId = s.id
                        ..title = title
                        ..start = _start
                        ..durationMinutes = _duration
                        ..type = _type
                        ..notes = _notes.text.trim();
                      if (x.status == TaskStatus.missed && x.end.isAfter(DateTime.now())) {
                        x.status = TaskStatus.pending;
                      }
                      app.upsertTask(x);
                      Navigator.pop(context);
                    },
            ),
          ]),
        ),
      ),
    );
  }
}

class _PickerTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PickerTile({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Material(
      color: p.surfaceAlt,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
          child: Row(children: [
            Icon(icon, size: 20, color: AppColors.primary),
            const SizedBox(width: 10),
            Expanded(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13.5, w: FontWeight.w700, c: p.text))),
          ]),
        ),
      ),
    );
  }
}
