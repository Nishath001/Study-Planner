import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import 'ui.dart';

// ── Labels, icons and colours ──────────────────────────────────────────────
(String, IconData, Color) categoryMeta(AppState app, TaskCategory c) => switch (c) {
      TaskCategory.study => (app.t('Study', 'අධ්‍යයනය'), Icons.menu_book_rounded, AppColors.primary),
      TaskCategory.assignment => (app.t('Assignment', 'පැවරුම'), Icons.assignment_rounded, AppColors.violet),
      TaskCategory.personal => (app.t('Personal', 'පුද්ගලික'), Icons.person_rounded, AppColors.sky),
      TaskCategory.health => (app.t('Health', 'සෞඛ්‍යය'), Icons.favorite_rounded, AppColors.rose),
      TaskCategory.errand => (app.t('Errand', 'කටයුතු'), Icons.shopping_bag_rounded, AppColors.amber),
      TaskCategory.other => (app.t('Other', 'වෙනත්'), Icons.label_rounded, AppColors.teal),
    };

(String, Color) priorityMeta(AppState app, TaskPriority p) => switch (p) {
      TaskPriority.low => (app.t('Low', 'අඩු'), AppColors.teal),
      TaskPriority.medium => (app.t('Medium', 'මධ්‍යම'), AppColors.amber),
      TaskPriority.high => (app.t('High', 'ඉහළ'), AppColors.rose),
    };

String repeatLabel(AppState app, Repeat r) => switch (r) {
      Repeat.none => app.t('Once', 'එක් වරක්'),
      Repeat.daily => app.t('Every day', 'දිනපතා'),
      Repeat.weekdays => app.t('Weekdays', 'සතියේ දින'),
      Repeat.weekly => app.t('Weekly', 'සතිපතා'),
    };

String fmtDue(BuildContext c, int minutes) =>
    fmtTime(c, DateTime(2000, 1, 1).add(Duration(minutes: minutes)));

// ── Task row ───────────────────────────────────────────────────────────────
class DailyTaskTile extends StatelessWidget {
  final DailyTask task;
  final DateTime day;
  final bool compact;
  final Widget? trailing;
  const DailyTaskTile({super.key, required this.task, required this.day, this.compact = false, this.trailing});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final done = task.doneOn(day);
    final cat = categoryMeta(app, task.category);
    final pri = priorityMeta(app, task.priority);
    final due = task.dueOn(day);
    final late = !done && due != null && due.isBefore(DateTime.now());
    final subject = task.subjectId == null ? null : app.subject(task.subjectId!);
    final subDone = task.subtasksDoneOn(day);

    final body = AppCard(
      padding: EdgeInsets.fromLTRB(14, compact ? 12 : 14, 12, compact ? 12 : 14),
      onTap: () => showDailyTaskEditor(context, task: task, day: day),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Check(done: done, color: pri.$2, onTap: () => app.toggleDaily(task, day)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                task.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: ts(14.5, w: FontWeight.w700, c: done ? p.textMuted : p.text).copyWith(
                  decoration: done ? TextDecoration.lineThrough : null,
                  decorationColor: p.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                if (due != null)
                  Pill(fmtDue(context, task.dueMinutes!), late ? AppColors.rose : p.textSoft, icon: Icons.schedule_rounded),
                Pill(subject?.name ?? cat.$1, subject?.color ?? cat.$3, icon: subject?.iconData ?? cat.$2),
                if (task.subtasks.isNotEmpty)
                  Pill('$subDone/${task.subtasks.length}', AppColors.teal, icon: Icons.checklist_rounded),
                if (task.repeat != Repeat.none) Icon(Icons.repeat_rounded, size: 15, color: p.textMuted),
                if (task.note.isNotEmpty) Icon(Icons.notes_rounded, size: 15, color: p.textMuted),
              ]),
            ]),
          ),
          trailing ??
              (task.priority == TaskPriority.low || done
                  ? const SizedBox(width: 4)
                  : Padding(
                      padding: const EdgeInsets.only(top: 2, left: 4),
                      child: Icon(Icons.flag_rounded, size: 18, color: pri.$2),
                    )),
        ]),
        if (!compact && !done && task.subtasks.isNotEmpty) ...[
          const SizedBox(height: 8),
          for (final (i, s) in task.subtasks.indexed)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => app.toggleSubtask(task, i, day),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(40, 4, 0, 4),
                child: Row(children: [
                  Icon(s.doneOn(day) ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
                      size: 18, color: s.doneOn(day) ? AppColors.teal : p.textMuted),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(s.title,
                        style: ts(13, w: FontWeight.w600, c: s.doneOn(day) ? p.textMuted : p.textSoft).copyWith(
                          decoration: s.doneOn(day) ? TextDecoration.lineThrough : null,
                          decorationColor: p.textMuted,
                        )),
                  ),
                ]),
              ),
            ),
        ],
      ]),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Dismissible(
        key: ValueKey('daily_${task.id}_${dayKey(day)}'),
        background: _swipeBg(Icons.check_rounded, AppColors.green, Alignment.centerLeft,
            done ? app.t('Undo', 'අහෝසි') : app.t('Done', 'අවසන්')),
        secondaryBackground: _swipeBg(Icons.delete_rounded, AppColors.rose, Alignment.centerRight, app.t('Delete', 'මකන්න')),
        confirmDismiss: (dir) async {
          if (dir == DismissDirection.startToEnd) {
            await app.toggleDaily(task, day);
            return false; // the row stays; it just moves to "Completed"
          }
          return true;
        },
        onDismissed: (_) {
          final backup = task.copy();
          app.deleteDaily(task.id);
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(app.t('Task deleted', 'කාර්යය මකන ලදී')),
            action: SnackBarAction(label: app.t('Undo', 'අහෝසි'), onPressed: () => app.upsertDaily(backup)),
          ));
        },
        child: body,
      ),
    );
  }

  Widget _swipeBg(IconData icon, Color color, Alignment align, String label) => Container(
        alignment: align,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(22)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (align == Alignment.centerRight) Text(label, style: ts(13, w: FontWeight.w800, c: color)),
          if (align == Alignment.centerRight) const SizedBox(width: 6),
          Icon(icon, color: color),
          if (align == Alignment.centerLeft) const SizedBox(width: 6),
          if (align == Alignment.centerLeft) Text(label, style: ts(13, w: FontWeight.w800, c: color)),
        ]),
      );
}

class _Check extends StatelessWidget {
  final bool done;
  final Color color;
  final VoidCallback onTap;
  const _Check({required this.done, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutBack,
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: done ? const LinearGradient(colors: [Color(0xFF22C55E), Color(0xFF14B8A6)]) : null,
            border: done ? null : Border.all(color: color, width: 2.2),
          ),
          child: AnimatedScale(
            scale: done ? 1 : 0,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            child: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
          ),
        ),
      );
}

// ── Quick add ──────────────────────────────────────────────────────────────
class QuickAddTask extends StatefulWidget {
  final DateTime day;
  const QuickAddTask({super.key, required this.day});

  @override
  State<QuickAddTask> createState() => _QuickAddTaskState();
}

class _QuickAddTaskState extends State<QuickAddTask> {
  final _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  void _add() {
    final app = context.read<AppState>();
    if (_c.text.trim().isEmpty) return;
    app.addQuickDaily(_c.text, day: widget.day);
    _c.clear();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    return TextField(
      controller: _c,
      textInputAction: TextInputAction.done,
      onSubmitted: (_) => _add(),
      decoration: InputDecoration(
        hintText: app.t('Add a task… e.g. Submit lab report', 'කාර්යයක් එක් කරන්න…'),
        prefixIcon: const Icon(Icons.add_task_rounded, color: AppColors.teal),
        suffixIcon: IconButton(
          tooltip: app.t('More options', 'තවත් විකල්ප'),
          icon: Icon(Icons.tune_rounded, color: p.textMuted),
          onPressed: () => showDailyTaskEditor(context, day: widget.day, initialTitle: _c.text),
        ),
      ),
    );
  }
}

// ── Add / edit sheet ───────────────────────────────────────────────────────
Future<void> showDailyTaskEditor(BuildContext context, {DailyTask? task, DateTime? day, String initialTitle = ''}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (_) => ChangeNotifierProvider<AppState>.value(
      value: context.read<AppState>(),
      child: _DailyEditor(existing: task, day: day ?? DateTime.now(), initialTitle: initialTitle),
    ),
  );
}

class _DailyEditor extends StatefulWidget {
  final DailyTask? existing;
  final DateTime day;
  final String initialTitle;
  const _DailyEditor({this.existing, required this.day, this.initialTitle = ''});

  @override
  State<_DailyEditor> createState() => _DailyEditorState();
}

class _DailyEditorState extends State<_DailyEditor> {
  late final DailyTask _t = widget.existing?.copy() ??
      DailyTask(id: 'd_${DateTime.now().microsecondsSinceEpoch}', title: widget.initialTitle, date: widget.day);
  late final _title = TextEditingController(text: _t.title);
  late final _note = TextEditingController(text: _t.note);
  final _sub = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _note.dispose();
    _sub.dispose();
    super.dispose();
  }

  void _addSub() {
    if (_sub.text.trim().isEmpty) return;
    setState(() => _t.subtasks.add(SubTask(_sub.text.trim())));
    _sub.clear();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;

    Widget label(String s) => Padding(
          padding: const EdgeInsets.only(top: 18, bottom: 10),
          child: Text(s, style: ts(13, w: FontWeight.w800, c: p.textSoft)),
        );

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Row(children: [
              Expanded(
                child: Text(widget.existing == null ? app.t('New task', 'නව කාර්යය') : app.t('Edit task', 'කාර්යය සංස්කරණය'),
                    style: ts(20, w: FontWeight.w800, c: p.text)),
              ),
              if (widget.existing != null)
                IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: AppColors.rose),
                  onPressed: () {
                    app.deleteDaily(_t.id);
                    Navigator.pop(context);
                  },
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              autofocus: widget.existing == null && widget.initialTitle.isEmpty,
              textCapitalization: TextCapitalization.sentences,
              style: ts(16, w: FontWeight.w700, c: p.text),
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: app.t('What needs to be done?', 'කළ යුත්තේ කුමක්ද?')),
            ),
            label(app.t('Category', 'වර්ගය')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in TaskCategory.values)
                () {
                  final m = categoryMeta(app, c);
                  final sel = _t.category == c;
                  return ChoiceChip(
                    avatar: Icon(m.$2, size: 16, color: sel ? Colors.white : m.$3),
                    label: Text(m.$1),
                    selected: sel,
                    showCheckmark: false,
                    selectedColor: m.$3,
                    labelStyle: ts(12.5, w: FontWeight.w700, c: sel ? Colors.white : p.textSoft),
                    onSelected: (_) => setState(() => _t.category = c),
                  );
                }(),
            ]),
            if ((_t.category == TaskCategory.study || _t.category == TaskCategory.assignment) && app.subjects.isNotEmpty) ...[
              label(app.t('Subject (optional)', 'විෂයය (අත්‍යවශ්‍ය නැත)')),
              SizedBox(
                height: 40,
                child: ListView(scrollDirection: Axis.horizontal, children: [
                  for (final s in app.subjects)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: ChoiceChip(
                        avatar: Icon(s.iconData, size: 15, color: _t.subjectId == s.id ? Colors.white : s.color),
                        label: Text(s.name),
                        selected: _t.subjectId == s.id,
                        showCheckmark: false,
                        selectedColor: s.color,
                        labelStyle: ts(12, w: FontWeight.w700, c: _t.subjectId == s.id ? Colors.white : p.textSoft),
                        onSelected: (v) => setState(() => _t.subjectId = v ? s.id : null),
                      ),
                    ),
                ]),
              ),
            ],
            label(app.t('Priority', 'ප්‍රමුඛතාව')),
            Row(children: [
              for (final pr in TaskPriority.values) ...[
                Expanded(
                  child: () {
                    final m = priorityMeta(app, pr);
                    final sel = _t.priority == pr;
                    return GestureDetector(
                      onTap: () => setState(() => _t.priority = pr),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: sel ? m.$2.withOpacity(0.14) : p.surfaceAlt,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: sel ? m.$2 : Colors.transparent, width: 1.6),
                        ),
                        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.flag_rounded, size: 17, color: m.$2),
                          const SizedBox(width: 6),
                          Text(m.$1, style: ts(13, w: FontWeight.w800, c: sel ? m.$2 : p.textSoft)),
                        ]),
                      ),
                    );
                  }(),
                ),
                if (pr != TaskPriority.high) const SizedBox(width: 8),
              ],
            ]),
            label(app.t('When', 'කවදාද')),
            Row(children: [
              Expanded(
                child: _Picker(
                  icon: Icons.event_rounded,
                  text: relativeDay(context, _t.date),
                  onTap: () async {
                    final d = await showDatePicker(
                      context: context,
                      initialDate: _t.date,
                      firstDate: DateTime.now().subtract(const Duration(days: 365)),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                    );
                    if (d != null) setState(() => _t.date = dateOnly(d));
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _Picker(
                  icon: Icons.schedule_rounded,
                  text: _t.dueMinutes == null ? app.t('Any time', 'ඕනෑම වේලාවක') : fmtDue(context, _t.dueMinutes!),
                  onClear: _t.dueMinutes == null ? null : () => setState(() => _t.dueMinutes = null),
                  onTap: () async {
                    final m = _t.dueMinutes ?? 17 * 60;
                    final tod = await showTimePicker(context: context, initialTime: TimeOfDay(hour: m ~/ 60, minute: m % 60));
                    if (tod != null) setState(() => _t.dueMinutes = tod.hour * 60 + tod.minute);
                  },
                ),
              ),
            ]),
            label(app.t('Repeat', 'නැවත කිරීම')),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final r in Repeat.values)
                ChoiceChip(
                  label: Text(repeatLabel(app, r)),
                  selected: _t.repeat == r,
                  showCheckmark: false,
                  selectedColor: AppColors.primary,
                  labelStyle: ts(12.5, w: FontWeight.w700, c: _t.repeat == r ? Colors.white : p.textSoft),
                  onSelected: (_) => setState(() => _t.repeat = r),
                ),
            ]),
            label(app.t('Steps', 'පියවර')),
            for (final (i, s) in _t.subtasks.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Icon(Icons.drag_indicator_rounded, size: 18, color: p.textMuted),
                  const SizedBox(width: 6),
                  Expanded(child: Text(s.title, style: ts(13.5, w: FontWeight.w600, c: p.text))),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.close_rounded, size: 18, color: p.textMuted),
                    onPressed: () => setState(() => _t.subtasks.removeAt(i)),
                  ),
                ]),
              ),
            TextField(
              controller: _sub,
              onSubmitted: (_) => _addSub(),
              decoration: InputDecoration(
                hintText: app.t('Add a step', 'පියවරක් එක් කරන්න'),
                prefixIcon: const Icon(Icons.checklist_rounded),
                suffixIcon: IconButton(icon: const Icon(Icons.add_rounded), onPressed: _addSub),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _note,
              minLines: 2,
              maxLines: 4,
              decoration: InputDecoration(hintText: app.t('Notes (optional)', 'සටහන් (අත්‍යවශ්‍ය නැත)')),
            ),
            const SizedBox(height: 6),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              value: _t.remind && _t.dueMinutes != null,
              onChanged: _t.dueMinutes == null ? null : (v) => setState(() => _t.remind = v),
              title: Text(app.t('Remind me at the due time', 'නියමිත වේලාවට මතක් කරන්න'),
                  style: ts(13.5, w: FontWeight.w700, c: p.text)),
              subtitle: _t.dueMinutes == null
                  ? Text(app.t('Set a time to get a reminder', 'සිහිකැඳවීමට වේලාවක් සකසන්න'), style: ts(12, c: p.textMuted))
                  : null,
            ),
            const SizedBox(height: 12),
            GradientButton(
              label: app.t('Save task', 'සුරකින්න'),
              icon: Icons.check_rounded,
              gradient: const LinearGradient(colors: [Color(0xFF0D9488), Color(0xFF0EA5E9)]),
              onPressed: _title.text.trim().isEmpty
                  ? null
                  : () {
                      _addSub();
                      _t
                        ..title = _title.text.trim()
                        ..note = _note.text.trim();
                      if (_t.category != TaskCategory.study && _t.category != TaskCategory.assignment) _t.subjectId = null;
                      app.upsertDaily(_t);
                      Navigator.pop(context);
                    },
            ),
          ],
        ),
      ),
    );
  }
}

class _Picker extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  const _Picker({required this.icon, required this.text, required this.onTap, this.onClear});

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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
          child: Row(children: [
            Icon(icon, size: 19, color: AppColors.teal),
            const SizedBox(width: 10),
            Expanded(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13.5, w: FontWeight.w700, c: p.text))),
            if (onClear != null)
              GestureDetector(onTap: onClear, child: Icon(Icons.close_rounded, size: 17, color: p.textMuted)),
          ]),
        ),
      ),
    );
  }
}
