import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

class SubjectsScreen extends StatelessWidget {
  const SubjectsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final list = [...app.subjects]
      ..sort((a, b) => (a.daysToExam ?? 999).compareTo(b.daysToExam ?? 999));

    return Scaffold(
      appBar: AppBar(title: Text(app.t('My subjects', 'මගේ විෂයයන්'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context, null),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded),
        label: Text(app.t('Add subject', 'විෂයයක් එක් කරන්න'), style: ts(14, w: FontWeight.w800, c: Colors.white)),
      ),
      body: list.isEmpty
          ? ListView(padding: const EdgeInsets.all(20), children: [
              EmptyState(
                icon: Icons.library_books_rounded,
                title: app.t('No subjects yet', 'තවම විෂයයන් නැත'),
                subtitle: app.t('Add each module with its exam date and how hard it feels for you.',
                    'සෑම විෂයයක්ම එහි විභාග දිනය සහ අපහසුතාව සමඟ එක් කරන්න.'),
                actionLabel: app.t('Add subject', 'විෂයයක් එක් කරන්න'),
                onAction: () => _open(context, null),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: app.addSampleSubjects,
                icon: const Icon(Icons.auto_fix_high_rounded, size: 18),
                label: Text(app.t('Try with sample NMC subjects', 'උදාහරණ විෂයයන් සමඟ උත්සාහ කරන්න')),
              ),
            ])
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
              itemCount: list.length,
              itemBuilder: (_, i) {
                final s = list[i];
                final prog = app.subjectProgress(s);
                final d = s.daysToExam;
                return FadeSlideIn(
                  delay: 40 * i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: AppCard(
                      onTap: () => _open(context, s),
                      child: Column(children: [
                        Row(children: [
                          IconBadge(s.iconData, s.color, size: 50, radius: 16),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(s.name, style: ts(16, w: FontWeight.w800, c: p.text)),
                              const SizedBox(height: 6),
                              Wrap(spacing: 6, runSpacing: 6, children: [
                                Pill(app.difficultyLabel(s.difficulty),
                                    [AppColors.teal, AppColors.amber, AppColors.rose][s.difficulty.index]),
                                if (d != null)
                                  Pill(
                                    d < 0
                                        ? app.t('Exam done', 'විභාගය අවසන්')
                                        : d == 0
                                            ? app.t('Exam today', 'අද විභාගය')
                                            : app.t('Exam in $d days', 'දින $d කින් විභාගය'),
                                    d < 0 ? p.textMuted : (d <= 7 ? AppColors.rose : AppColors.primary),
                                    icon: Icons.event_rounded,
                                  ),
                              ]),
                            ]),
                          ),
                          Icon(Icons.chevron_right_rounded, color: p.textMuted),
                        ]),
                        const SizedBox(height: 16),
                        Row(children: [
                          Expanded(child: SoftProgressBar(value: prog, color: s.color)),
                          const SizedBox(width: 12),
                          Text('${(prog * 100).round()}%', style: ts(13, w: FontWeight.w800, c: s.color)),
                        ]),
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text(
                            app.t('${fmtMinutes(app.minutesForSubject(s.id))} of ${s.targetHours}h target',
                                'ඉලක්ක පැය ${s.targetHours} න් ${fmtMinutes(app.minutesForSubject(s.id))}'),
                            style: ts(12, c: p.textMuted),
                          ),
                        ),
                      ]),
                    ),
                  ),
                );
              },
            ),
    );
  }

  void _open(BuildContext context, Subject? s) =>
      Navigator.push(context, MaterialPageRoute(builder: (_) => SubjectEditor(existing: s)));
}

class SubjectEditor extends StatefulWidget {
  final Subject? existing;
  const SubjectEditor({super.key, this.existing});

  @override
  State<SubjectEditor> createState() => _SubjectEditorState();
}

class _SubjectEditorState extends State<SubjectEditor> {
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late int _color = widget.existing?.colorValue ??
      AppColors.subjectPalette[context.read<AppState>().subjects.length % AppColors.subjectPalette.length].value;
  late String _icon = widget.existing?.icon ?? 'book';
  late Difficulty _difficulty = widget.existing?.difficulty ?? Difficulty.medium;
  late DateTime? _exam = widget.existing?.examDate;
  late int _target = widget.existing?.targetHours ?? 20;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final color = Color(_color);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.existing == null ? app.t('New subject', 'නව විෂයය') : app.t('Edit subject', 'විෂයය සංස්කරණය')),
        actions: [
          if (widget.existing != null)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded, color: AppColors.rose),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: Text(app.t('Delete subject?', 'විෂයය මකන්නද?')),
                    content: Text(app.t('Its pending tasks will be removed too.', 'එහි ඉතිරි කාර්යයන්ද ඉවත් වේ.')),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(context, false), child: Text(app.t('Cancel', 'අවලංගු'))),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: Text(app.t('Delete', 'මකන්න'), style: const TextStyle(color: AppColors.rose)),
                      ),
                    ],
                  ),
                );
                if (ok == true) {
                  await app.deleteSubject(widget.existing!.id);
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
        children: [
          // Live preview
          Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 250),
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [color, Color.lerp(color, Colors.white, 0.3)!],
                    begin: Alignment.topLeft, end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(28),
                boxShadow: [BoxShadow(color: color.withOpacity(0.4), blurRadius: 22, offset: const Offset(0, 10))],
              ),
              child: Icon(subjectIcons[_icon], color: Colors.white, size: 44),
            ),
          ),
          const SizedBox(height: 24),
          _label(app.t('Subject name', 'විෂයයේ නම'), p),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(hintText: app.t('e.g. Mobile Computing', 'උදා: Mobile Computing')),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 20),
          _label(app.t('Colour', 'වර්ණය'), p),
          Wrap(spacing: 10, runSpacing: 10, children: [
            for (final c in AppColors.subjectPalette)
              GestureDetector(
                onTap: () => setState(() => _color = c.value),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(color: _color == c.value ? p.text : Colors.transparent, width: 3),
                  ),
                  child: _color == c.value ? const Icon(Icons.check_rounded, color: Colors.white, size: 18) : null,
                ),
              ),
          ]),
          const SizedBox(height: 20),
          _label(app.t('Icon', 'අයිකනය'), p),
          GridView.count(
              padding: EdgeInsets.zero,
            crossAxisCount: 8,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 8,
            crossAxisSpacing: 8,
            children: [
              for (final e in subjectIcons.entries)
                GestureDetector(
                  onTap: () => setState(() => _icon = e.key),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: _icon == e.key ? color.withOpacity(0.16) : p.surfaceAlt,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _icon == e.key ? color : Colors.transparent, width: 1.6),
                    ),
                    child: Icon(e.value, size: 20, color: _icon == e.key ? color : p.textMuted),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          _label(app.t('How hard is it for you?', 'ඔබට එය කෙතරම් අපහසුද?'), p),
          Row(children: [
            for (final d in Difficulty.values) ...[
              Expanded(
                child: _DiffTile(
                  label: app.difficultyLabel(d),
                  color: [AppColors.teal, AppColors.amber, AppColors.rose][d.index],
                  bars: d.index + 1,
                  selected: _difficulty == d,
                  onTap: () => setState(() => _difficulty = d),
                ),
              ),
              if (d != Difficulty.hard) const SizedBox(width: 10),
            ],
          ]),
          const SizedBox(height: 20),
          _label(app.t('Exam date', 'විභාග දිනය'), p),
          Material(
            color: p.surfaceAlt,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () async {
                final now = DateTime.now();
                final d = await showDatePicker(
                  context: context,
                  initialDate: _exam ?? now.add(const Duration(days: 14)),
                  firstDate: dateOnly(now),
                  lastDate: now.add(const Duration(days: 730)),
                );
                if (d != null) setState(() => _exam = d);
              },
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(children: [
                  Icon(Icons.event_rounded, color: color),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _exam == null ? app.t('No exam date set', 'විභාග දිනයක් නැත') : fmtDate(context, _exam!),
                      style: ts(14, w: FontWeight.w700, c: _exam == null ? p.textMuted : p.text),
                    ),
                  ),
                  if (_exam != null)
                    GestureDetector(
                      onTap: () => setState(() => _exam = null),
                      child: Icon(Icons.close_rounded, size: 18, color: p.textMuted),
                    ),
                ]),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(children: [
            Expanded(child: _label(app.t('Study hours needed', 'අවශ්‍ය අධ්‍යයන පැය'), p)),
            Pill('${_target}h', color),
          ]),
          Slider(
            value: _target.toDouble(),
            min: 5,
            max: 100,
            divisions: 19,
            activeColor: color,
            onChanged: (v) => setState(() => _target = v.round()),
          ),
          const SizedBox(height: 24),
          GradientButton(
            label: app.t('Save subject', 'සුරකින්න'),
            icon: Icons.check_rounded,
            gradient: LinearGradient(colors: [color, Color.lerp(color, AppColors.violet, 0.4)!]),
            onPressed: _name.text.trim().isEmpty
                ? null
                : () async {
                    await app.upsertSubject(Subject(
                      id: widget.existing?.id ?? 'sub_${DateTime.now().microsecondsSinceEpoch}',
                      name: _name.text.trim(),
                      colorValue: _color,
                      icon: _icon,
                      difficulty: _difficulty,
                      examDate: _exam,
                      targetHours: _target,
                    ));
                    if (context.mounted) Navigator.pop(context);
                  },
          ),
        ],
      ),
    );
  }

  Widget _label(String s, Palette p) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(s, style: ts(13.5, w: FontWeight.w800, c: p.textSoft)),
      );
}

class _DiffTile extends StatelessWidget {
  final String label;
  final Color color;
  final int bars;
  final bool selected;
  final VoidCallback onTap;
  const _DiffTile({required this.label, required this.color, required this.bars, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: selected ? color.withOpacity(0.12) : p.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? color : p.border, width: selected ? 1.8 : 1),
        ),
        child: Column(children: [
          Row(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
            for (var i = 0; i < 3; i++)
              Container(
                width: 6,
                height: 8.0 + i * 5,
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: i < bars ? color : p.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ]),
          const SizedBox(height: 8),
          Text(label, style: ts(13, w: FontWeight.w800, c: selected ? color : p.textSoft)),
        ]),
      ),
    );
  }
}
