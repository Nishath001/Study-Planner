import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../services/scheduler_engine.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/pref_editors.dart';
import '../widgets/ui.dart';
import 'shell.dart';
import 'subjects_screen.dart';
import 'suggestions_screen.dart';

class AIPlannerScreen extends StatefulWidget {
  const AIPlannerScreen({super.key});

  @override
  State<AIPlannerScreen> createState() => _AIPlannerScreenState();
}

class _AIPlannerScreenState extends State<AIPlannerScreen> {
  PlanResult? _preview;

  Future<void> _generate(AppState app) async {
    final r = await app.buildPlan();
    if (!mounted) return;
    setState(() => _preview = r);
    if (app.planError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(app.planError!)));
    }
  }

  Future<void> _apply(AppState app) async {
    await app.applyPlan(_preview!);
    if (!mounted) return;
    final n = _preview!.tasks.length;
    setState(() => _preview = null);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(app.t('$n sessions added to your plan', 'සැසි $n ක් ඔබේ සැලැස්මට එක් කළා')),
    ));
    context.read<ShellNav>().go(1);
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final insights = _preview?.insights ?? app.insights;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            Row(children: [
              Expanded(child: Text(app.t('AI Planner', 'AI සැලසුම්කරු'), style: ts(26, w: FontWeight.w800, c: p.text))),
              Pill(app.t('On-device', 'උපාංගය තුළ'), AppColors.teal, icon: Icons.memory_rounded),
            ]),
            const SizedBox(height: 16),
            _hero(app),
            const SizedBox(height: 20),

            if (app.subjects.isEmpty)
              EmptyState(
                icon: Icons.library_add_rounded,
                title: app.t('Add subjects to start', 'ආරම්භ කිරීමට විෂයයන් එක් කරන්න'),
                subtitle: app.t('The planner needs your subjects, exam dates and difficulty.',
                    'සැලසුම්කරුට ඔබේ විෂයයන්, විභාග දින සහ අපහසුතාව අවශ්‍යයි.'),
                actionLabel: app.t('Add subjects', 'විෂයයන් එක් කරන්න'),
                onAction: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubjectsScreen())),
              )
            else if (app.planning)
              const _Thinking()
            else if (_preview != null)
              _previewSection(app, _preview!)
            else ...[
              _inputs(app),
              const SizedBox(height: 20),
              _styleChooser(app),
              const SizedBox(height: 20),
              GradientButton(
                label: app.t('Generate my ${app.prefs.planHorizonDays}-day plan', 'දින ${app.prefs.planHorizonDays} සැලැස්ම සාදන්න'),
                icon: Icons.auto_awesome_rounded,
                gradient: AppColors.aiGradient,
                onPressed: () => _generate(app),
              ),
            ],

            if (insights.isNotEmpty && !app.planning) ...[
              const SizedBox(height: 26),
              SectionHeader(app.t('Subject priorities', 'විෂය ප්‍රමුඛතා')),
              Text(
                app.t('How the AI ranks your subjects right now — and why.',
                    'AI දැනට ඔබේ විෂයයන් ශ්‍රේණිගත කරන ආකාරය සහ හේතුව.'),
                style: ts(12.5, c: p.textMuted),
              ),
              const SizedBox(height: 12),
              for (final (i, x) in insights.indexed)
                FadeSlideIn(delay: 40 * i, child: _InsightCard(rank: i + 1, insight: x, showAllocation: _preview != null)),
              const SizedBox(height: 14),
              _adaptiveCard(app),
              const SizedBox(height: 14),
              _howItWorks(app),
            ],
          ],
        ),
      ),
    );
  }

  Widget _hero(AppState app) {
    final adherence = app.adherence;
    return AppCard(
      gradient: const LinearGradient(
        colors: [Color(0xFF1E1B4B), Color(0xFF4338CA), Color(0xFF7C3AED)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(color: Colors.white.withOpacity(0.15), borderRadius: BorderRadius.circular(14)),
            child: const Icon(Icons.psychology_rounded, color: Colors.white, size: 26),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('StudySync AI', style: ts(18, w: FontWeight.w800, c: Colors.white)),
              Text(app.t('Adaptive, explainable scheduling', 'අනුවර්තී, පැහැදිලි කාලසටහන්කරණය'),
                  style: ts(12, c: Colors.white70)),
            ]),
          ),
        ]),
        const SizedBox(height: 14),
        Text(
          app.t('Weighs exam urgency, difficulty, remaining workload and how you\'ve actually been doing — then fits sessions into your free time.',
              'විභාග ආසන්නභාවය, අපහසුතාව, ඉතිරි වැඩ ප්‍රමාණය සහ ඔබේ සැබෑ ප්‍රගතිය සලකා ඔබේ නිදහස් කාලයට සැසි යොදයි.'),
          style: ts(13, c: Colors.white.withOpacity(0.85), h: 1.5),
        ),
        const SizedBox(height: 16),
        Row(children: [
          _heroStat('${app.subjects.where((s) => !s.examPassed).length}', app.t('subjects', 'විෂයයන්')),
          _heroStat(fmtMinutes(app.prefs.weeklyMinutes), app.t('free / week', 'සතියට')),
          _heroStat('${(adherence * 100).round()}%', app.t('follow-through', 'අනුගමනය')),
        ]),
      ]),
    );
  }

  Widget _heroStat(String v, String l) => Expanded(
        child: Container(
          margin: const EdgeInsets.only(right: 8),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 10),
          decoration: BoxDecoration(color: Colors.white.withOpacity(0.12), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            FittedBox(child: Text(v, style: ts(17, w: FontWeight.w800, c: Colors.white))),
            FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft, child: Text(l, maxLines: 1, style: ts(11, c: Colors.white70))),
          ]),
        ),
      );

  Widget _inputs(AppState app) {
    final p = context.pal;
    final pr = app.prefs;
    Widget row(IconData i, Color c, String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 7),
          child: Row(children: [
            Icon(i, size: 19, color: c),
            const SizedBox(width: 10),
            Expanded(child: Text(label, style: ts(13, c: p.textSoft))),
            Text(value, style: ts(13, w: FontWeight.w800, c: p.text)),
          ]),
        );
    final windowLabel = [
      app.t('Morning', 'උදෑසන'),
      app.t('Afternoon', 'දහවල්'),
      app.t('Evening', 'සවස'),
      app.t('Night', 'රාත්‍රී'),
    ][pr.window.index];
    return AppCard(
      child: Column(children: [
        Row(children: [
          Expanded(child: Text(app.t('What the AI will use', 'AI භාවිතා කරන දේ'), style: ts(15, w: FontWeight.w800, c: p.text))),
          TextButton.icon(
            onPressed: () => _editPrefs(app),
            icon: const Icon(Icons.tune_rounded, size: 17),
            label: Text(app.t('Adjust', 'වෙනස් කරන්න')),
          ),
        ]),
        row(Icons.schedule_rounded, AppColors.primary, app.t('Free time this week', 'මෙම සතියේ නිදහස් කාලය'), fmtMinutes(pr.weeklyMinutes)),
        row(Icons.wb_twilight_rounded, AppColors.amber, app.t('Preferred time', 'කැමති කාලය'), windowLabel),
        row(Icons.timer_outlined, AppColors.teal, app.t('Session · break', 'සැසිය · විවේකය'), '${pr.sessionMinutes} · ${pr.breakMinutes} min'),
        row(Icons.event_note_rounded, AppColors.rose, app.t('Exams set', 'විභාග දින'),
            '${app.subjects.where((s) => s.examDate != null && !s.examPassed).length}/${app.subjects.length}'),
      ]),
    );
  }

  void _editPrefs(AppState app) {
    final draft = StudyPreferences.fromJson(app.prefs.toJson());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: app,
        child: StatefulBuilder(
          builder: (ctx, set) => ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(app.t('Planner settings', 'සැලසුම් සැකසුම්'), style: ts(20, w: FontWeight.w800, c: ctx.pal.text)),
                const SizedBox(height: 16),
                AvailabilityEditor(prefs: draft, onChanged: () => set(() {})),
                const SizedBox(height: 20),
                StudyStyleEditor(prefs: draft, onChanged: () => set(() {})),
                const SizedBox(height: 8),
                GradientButton(
                  label: app.t('Save', 'සුරකින්න'),
                  icon: Icons.check_rounded,
                  onPressed: () {
                    app.savePrefs(draft);
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _styleChooser(AppState app) {
    final p = context.pal;
    final styles = [
      (PlanMode.balanced, Icons.balance_rounded, AppColors.primary,
          app.t('Weighs exams, difficulty, workload and how you\'ve been doing',
              'විභාග, අපහසුතාව, වැඩ ප්‍රමාණය සහ ඔබේ ප්‍රගතිය සලකයි')),
      (PlanMode.examFocus, Icons.local_fire_department_rounded, AppColors.rose,
          app.t('Concentrates on your next exams with past papers and revision; other subjects get a short review',
              'ඊළඟ විභාග වෙත පසුගිය ප්‍රශ්න පත්‍ර සහ පුනරීක්ෂණයෙන් අවධානය; අනෙක් විෂයයන්ට කෙටි පුනරීක්ෂණයක්')),
      (PlanMode.light, Icons.spa_rounded, AppColors.teal,
          app.t('Uses about ${(SchedulerEngine.lightLoad * 100).round()}% of your free time — for busy or tiring weeks',
              'ඔබේ නිදහස් කාලයෙන් ${(SchedulerEngine.lightLoad * 100).round()}% ක් පමණ — කාර්යබහුල සති සඳහා')),
    ];
    final previews = app.stylePreviews;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(child: Text(app.t('Planning style', 'සැලසුම් රටාව'), style: ts(15, w: FontWeight.w800, c: p.text))),
        Icon(Icons.lock_outline_rounded, size: 14, color: p.textMuted),
        const SizedBox(width: 4),
        Text(app.t('Private · works offline', 'පෞද්ගලික · නොබැඳිව'), style: ts(11.5, w: FontWeight.w600, c: p.textMuted)),
      ]),
      const SizedBox(height: 10),
      for (final st in styles)
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: () {
            final sel = app.prefs.planMode == st.$1;
            return GestureDetector(
              onTap: () => app.setPlanMode(st.$1),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: sel ? st.$3.withOpacity(p.isDark ? 0.14 : 0.08) : p.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: sel ? st.$3 : p.border, width: sel ? 1.8 : 1),
                ),
                child: Row(children: [
                  IconBadge(st.$2, st.$3, size: 40, radius: 12),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(app.planModeLabel(st.$1), style: ts(14, w: FontWeight.w800, c: p.text)),
                      const SizedBox(height: 2),
                      Text(st.$4, style: ts(12, c: p.textMuted, h: 1.35)),
                      if (app.subjects.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 1),
                            child: Icon(Icons.event_note_rounded, size: 14, color: st.$3),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              app.t('${previews[st.$1]!.tasks.length} sessions · ${fmtMinutes(previews[st.$1]!.totalMinutes)}',
                                  'සැසි ${previews[st.$1]!.tasks.length} · ${fmtMinutes(previews[st.$1]!.totalMinutes)}'),
                              style: ts(12.5, w: FontWeight.w800, c: st.$3, h: 1.35),
                            ),
                          ),
                        ]),
                        if (_styleEffect(app, st.$1, previews) case final effect?) ...[
                          const SizedBox(height: 6),
                          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Icon(Icons.insights_rounded, size: 14, color: st.$3),
                            ),
                            const SizedBox(width: 6),
                            Expanded(child: Text(effect, style: ts(12, w: FontWeight.w700, c: p.textSoft, h: 1.35))),
                          ]),
                        ],
                      ],
                    ]),
                  ),
                  const SizedBox(width: 8),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: sel
                        ? Icon(Icons.check_circle_rounded, key: const ValueKey('on'), color: st.$3, size: 22)
                        : Icon(Icons.circle_outlined, key: const ValueKey('off'), color: p.border, size: 22),
                  ),
                ]),
              ),
            );
          }(),
        ),
    ]);
  }

  String? _styleEffect(AppState app, PlanMode m, Map<PlanMode, PlanResult> previews) {
    final bal = previews[PlanMode.balanced]!, r = previews[m]!;
    switch (m) {
      case PlanMode.balanced:
        final top = app.minutesBySubject(r);
        if (top.isEmpty || top.first.$2 == 0) return null;
        return app.t('Most time: ${top.first.$1.name}', 'වැඩිම කාලය: ${top.first.$1.name}');
      case PlanMode.examFocus:
        final focus = r.focusSubjectIds;
        if (focus.isEmpty || bal.totalMinutes == 0 || r.totalMinutes == 0) return null;
        int share(PlanResult x) =>
            (x.tasks.where((t) => focus.contains(t.subjectId)).fold<int>(0, (a, t) => a + t.durationMinutes) /
                    x.totalMinutes *
                    100)
                .round();
        final names = app.subjects.where((s) => focus.contains(s.id)).map((s) => s.name).join(' & ');
        return app.t('$names get ${share(r)}% of your time (Balanced: ${share(bal)}%)',
            '$names ට ඔබේ කාලයෙන් ${share(r)}% (සමබර: ${share(bal)}%)');
      case PlanMode.light:
        final fewer = bal.tasks.length - r.tasks.length;
        if (fewer <= 0) return null;
        return app.t('$fewer fewer sessions than Balanced', 'Balanced ට වඩා සැසි $fewer ක් අඩුයි');
    }
  }

  Widget _previewSection(AppState app, PlanResult plan) {
    final p = context.pal;
    final days = <DateTime, List<StudyTask>>{};
    for (final t in plan.tasks) {
      days.putIfAbsent(dateOnly(t.start), () => []).add(t);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      AppCard(
        color: AppColors.violet.withOpacity(p.isDark ? 0.16 : 0.08),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.auto_awesome_rounded, color: AppColors.violet),
            const SizedBox(width: 8),
            Expanded(child: Text(app.t('Your plan is ready', 'ඔබේ සැලැස්ම සූදානම්'), style: ts(17, w: FontWeight.w800, c: p.text))),
          ]),
          const SizedBox(height: 12),
          // Switch style here to see the plan change straight away.
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final m in PlanMode.values)
              ChoiceChip(
                label: Text(app.planModeLabel(m)),
                selected: app.prefs.planMode == m,
                showCheckmark: false,
                selectedColor: AppColors.violet,
                labelStyle: ts(12.5, w: FontWeight.w700, c: app.prefs.planMode == m ? Colors.white : p.textSoft),
                onSelected: (_) async {
                  if (app.prefs.planMode == m) return;
                  await app.setPlanMode(m);
                  await _generate(app);
                },
              ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            _miniStat('${plan.tasks.length}', app.t('sessions', 'සැසි')),
            _miniStat(fmtMinutes(plan.totalMinutes), app.t('study time', 'අධ්‍යයන කාලය')),
            _miniStat('${days.length}', app.t('days', 'දින')),
          ]),
          if (plan.loadFactor < 0.99) ...[
            const SizedBox(height: 12),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.tips_and_updates_rounded, size: 17, color: AppColors.amber),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  app.t('You completed ${(plan.adherence * 100).round()}% of recent sessions, so this plan uses ${(plan.loadFactor * 100).round()}% of your free time to stay realistic.',
                      'මෑත සැසිවලින් ${(plan.adherence * 100).round()}% ක් සම්පූර්ණ කළ නිසා, යථාර්ථවාදී වීමට මෙම සැලැස්ම ඔබේ නිදහස් කාලයෙන් ${(plan.loadFactor * 100).round()}% ක් භාවිතා කරයි.'),
                  style: ts(12.5, c: p.textSoft, h: 1.45),
                ),
              ),
            ]),
          ],
          if (plan.advice != null) ...[
            const SizedBox(height: 12),
            Text('“${plan.advice}”', style: ts(13, w: FontWeight.w600, c: p.textSoft, h: 1.45)),
          ],
        ]),
      ),
      const SizedBox(height: 16),
      if (plan.tasks.isNotEmpty) ...[
        _subjectSplit(app, plan),
        const SizedBox(height: 16),
      ],
      if (plan.tasks.isEmpty)
        EmptyState(
          icon: Icons.event_busy_rounded,
          title: app.t('No free slots found', 'නිදහස් වේලාවන් නැත'),
          subtitle: app.t('Increase your available time or check exam dates.',
              'ඔබේ නිදහස් කාලය වැඩි කරන්න හෝ විභාග දින පරීක්ෂා කරන්න.'),
        )
      else
        for (final e in days.entries.take(4)) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 8, top: 4),
            child: Text(relativeDay(context, e.key), style: ts(13.5, w: FontWeight.w800, c: p.textSoft)),
          ),
          for (final t in e.value) _PreviewRow(task: t),
          const SizedBox(height: 8),
        ],
      if (days.length > 4)
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(app.t('+ ${days.length - 4} more days', '+ තවත් දින ${days.length - 4}'),
              textAlign: TextAlign.center, style: ts(12.5, w: FontWeight.w700, c: p.textMuted)),
        ),
      const SizedBox(height: 8),
      GradientButton(
        label: app.t('Apply to my schedule', 'මගේ කාලසටහනට යොදන්න'),
        icon: Icons.check_rounded,
        gradient: AppColors.aiGradient,
        onPressed: plan.tasks.isEmpty ? null : () => _apply(app),
      ),
      const SizedBox(height: 10),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () => _generate(app),
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: Text(app.t('Regenerate', 'නැවත සාදන්න')),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton(
            onPressed: () => setState(() => _preview = null),
            child: Text(app.t('Discard', 'ඉවතලන්න')),
          ),
        ),
      ]),
    ]);
  }

  Widget _subjectSplit(AppState app, PlanResult plan) {
    final p = context.pal;
    final rows = app.minutesBySubject(plan);
    final top = rows.isEmpty ? 1 : rows.first.$2.clamp(1, 1 << 30);
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(app.t('Time per subject', 'විෂය අනුව කාලය'), style: ts(15, w: FontWeight.w800, c: p.text)),
        const SizedBox(height: 4),
        Text(app.t('How this style shares your week', 'මෙම රටාව ඔබේ සතිය බෙදන ආකාරය'), style: ts(12, c: p.textMuted)),
        const SizedBox(height: 12),
        for (final (s, mins, n) in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Line 1: subject (full width so the name isn't cut); line 2: exam + time.
              Row(children: [
                Icon(s.iconData, size: 15, color: s.color),
                const SizedBox(width: 6),
                Flexible(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w700, c: p.text))),
                if (plan.focusSubjectIds.contains(s.id)) ...[
                  const SizedBox(width: 6),
                  Pill(app.t('Focus', 'අවධානය'), AppColors.rose, icon: Icons.local_fire_department_rounded),
                ],
              ]),
              const SizedBox(height: 4),
              Row(children: [
                if (s.daysToExam != null && s.daysToExam! >= 0)
                  Text(app.t('Exam in ${s.daysToExam} days', 'විභාගයට දින ${s.daysToExam}'),
                      style: ts(11.5, w: FontWeight.w700, c: s.daysToExam! <= 7 ? AppColors.rose : p.textMuted)),
                const Spacer(),
                Text(
                  mins == 0
                      ? '—'
                      : app.t('${fmtMinutes(mins)} · $n session${n == 1 ? '' : 's'}', '${fmtMinutes(mins)} · සැසි $n'),
                  style: ts(12, w: FontWeight.w800, c: p.textSoft),
                ),
              ]),
              const SizedBox(height: 6),
              SoftProgressBar(value: mins / top, color: s.color, height: 7),
            ]),
          ),
      ]),
    );
  }

  Widget _miniStat(String v, String l) {
    final p = context.pal;
    return Expanded(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(v, style: ts(19, w: FontWeight.w800, c: p.text)),
        Text(l, style: ts(11.5, c: p.textMuted)),
      ]),
    );
  }

  Widget _adaptiveCard(AppState app) {
    final p = context.pal;
    final missed = app.missedTasks.length;
    final peak = app.peakHour;
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const IconBadge(Icons.sync_alt_rounded, AppColors.green, size: 40, radius: 12),
          const SizedBox(width: 12),
          Expanded(child: Text(app.t('Adapting to you', 'ඔබට අනුවර්තනය වෙමින්'), style: ts(15, w: FontWeight.w800, c: p.text))),
        ]),
        const SizedBox(height: 12),
        _bullet(Icons.check_circle_outline_rounded,
            app.t('Follow-through: ${(app.adherence * 100).round()}% of recent sessions completed.',
                'අනුගමනය: මෑත සැසිවලින් ${(app.adherence * 100).round()}% සම්පූර්ණයි.')),
        _bullet(Icons.event_busy_rounded,
            missed == 0
                ? app.t('No missed sessions — great job!', 'මඟහැරුණු සැසි නැත — නියමයි!')
                : app.t('$missed missed session(s) waiting to be rescheduled.', 'මඟහැරුණු සැසි $missed ක් නැවත සැකසීමට ඇත.')),
        _bullet(Icons.wb_sunny_outlined,
            peak == null
                ? app.t('Rate your focus after timer sessions to discover your peak hours.',
                    'ඔබේ හොඳම වේලාවන් සොයා ගැනීමට ටයිමර් සැසිවලින් පසු අවධානය ශ්‍රේණිගත කරන්න.')
                : app.t('You focus best around ${peak.toString().padLeft(2, '0')}:00.',
                    'ඔබ හොඳින්ම අවධානය යොමු කරන්නේ ${peak.toString().padLeft(2, '0')}:00 පමණ.')),
        const SizedBox(height: 4),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SuggestionsScreen())),
          icon: const Icon(Icons.lightbulb_outline_rounded, size: 18),
          label: Text(app.suggestions.isEmpty
              ? app.t('Smart suggestions', 'බුද්ධිමත් යෝජනා')
              : app.t('${app.suggestions.length} smart suggestions', 'බුද්ධිමත් යෝජනා ${app.suggestions.length}')),
          style: OutlinedButton.styleFrom(minimumSize: const Size(double.infinity, 46)),
        ),
        if (missed > 0) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () async {
              final r = await app.rescheduleMissed();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(app.t('${r.moved} rescheduled · ${r.unplaced} no slot', '${r.moved} නැවත සැකසුණි · ${r.unplaced} ඉඩ නැත')),
              ));
            },
            style: FilledButton.styleFrom(backgroundColor: AppColors.green, minimumSize: const Size(double.infinity, 46)),
            icon: const Icon(Icons.replay_rounded, size: 18),
            label: Text(app.t('Smart reschedule', 'බුද්ධිමත් නැවත සැකසීම')),
          ),
        ],
      ]),
    );
  }

  Widget _bullet(IconData i, String text) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(i, size: 17, color: p.textMuted),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: ts(12.5, c: p.textSoft, h: 1.45))),
      ]),
    );
  }

  Widget _howItWorks(AppState app) {
    final p = context.pal;
    final steps = [
      (app.t('Score', 'ලකුණු'), app.t('Urgency 40% · Difficulty 25% · Workload 20% · Struggle 15%', 'ආසන්නභාවය 40% · අපහසුතාව 25% · වැඩ 20% · අපහසුතා 15%')),
      (app.t('Fit', 'යෙදීම'), app.t('Fills only your free time, hardest subjects first', 'ඔබේ නිදහස් කාලය පමණි, අපහසුම විෂයයන් මුලින්')),
      (app.t('Space', 'පරතරය'), app.t('Learn, then practise, then review; past papers near exams', 'ඉගෙනීම, අභ්‍යාස, පසුව පුනරීක්ෂණය')),
      (app.t('Adapt', 'අනුවර්තනය'), app.t('Learns from missed sessions and focus ratings', 'මඟහැරුණු සැසි සහ අවධාන ලකුණු වලින් ඉගෙන ගනී')),
    ];
    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(app.t('How it works', 'එය ක්‍රියා කරන ආකාරය'), style: ts(15, w: FontWeight.w800, c: p.text)),
        const SizedBox(height: 12),
        for (final (i, s) in steps.indexed)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(gradient: AppColors.brandGradient, shape: BoxShape.circle),
                child: Center(child: Text('${i + 1}', style: ts(12, w: FontWeight.w800, c: Colors.white))),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.$1, style: ts(13, w: FontWeight.w800, c: p.text)),
                  Text(s.$2, style: ts(12, c: p.textMuted)),
                ]),
              ),
            ]),
          ),
      ]),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final StudyTask task;
  const _PreviewRow({required this.task});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final s = app.subject(task.subjectId);
    final c = s?.color ?? AppColors.primary;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: BoxDecoration(
        color: p.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border(left: BorderSide(color: c, width: 4)),
      ),
      child: Row(children: [
        SizedBox(width: 64, child: Text(fmtTime(context, task.start), style: ts(12, w: FontWeight.w800, c: p.textSoft))),
        Expanded(child: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(13, w: FontWeight.w700, c: p.text))),
        Text(fmtMinutes(task.durationMinutes), style: ts(11.5, w: FontWeight.w700, c: p.textMuted)),
      ]),
    );
  }
}

class _InsightCard extends StatelessWidget {
  final int rank;
  final SubjectInsight insight;
  final bool showAllocation;
  const _InsightCard({required this.rank, required this.insight, required this.showAllocation});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final s = insight.subject;
    final reasons = <(String, Color)>[
      if (insight.urgency >= 0.5) (app.t('Exam soon', 'විභාගය ළඟයි'), AppColors.rose),
      if (s.difficulty == Difficulty.hard) (app.t('Hard', 'අපහසුයි'), AppColors.amber),
      if (insight.workload >= 0.75) (app.t('Most left to cover', 'වැඩිපුර ඉතිරියි'), AppColors.primary),
      if (insight.struggle >= 0.45) (app.t('Needs attention', 'අවධානය අවශ්‍යයි'), AppColors.violet),
    ];
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: AppCard(
        padding: const EdgeInsets.all(14),
        child: Column(children: [
          Row(children: [
            Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(color: rank == 1 ? AppColors.amber : p.surfaceAlt, shape: BoxShape.circle),
              child: Center(child: Text('$rank', style: ts(12, w: FontWeight.w800, c: rank == 1 ? Colors.white : p.textSoft))),
            ),
            const SizedBox(width: 10),
            IconBadge(s.iconData, s.color, size: 38, radius: 12),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(14, w: FontWeight.w800, c: p.text)),
                Text(
                  showAllocation
                      ? app.t('${insight.sessions} sessions · ${fmtMinutes(insight.allocatedMinutes)} planned',
                          'සැසි ${insight.sessions} · ${fmtMinutes(insight.allocatedMinutes)}')
                      : app.t('${fmtMinutes(insight.remainingMinutes)} left to study', 'ඉතිරි ${fmtMinutes(insight.remainingMinutes)}'),
                  style: ts(11.5, c: p.textMuted),
                ),
              ]),
            ),
            Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text((insight.score * 100).round().toString(), style: ts(18, w: FontWeight.w800, c: s.color)),
              Text(app.t('priority', 'ප්‍රමුඛතාව'), style: ts(10, c: p.textMuted)),
            ]),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            _factor(app.t('Urgency', 'ආසන්න'), insight.urgency, AppColors.rose),
            _factor(app.t('Difficulty', 'අපහසු'), insight.difficulty, AppColors.amber),
            _factor(app.t('Workload', 'වැඩ'), insight.workload, AppColors.primary),
            _factor(app.t('Struggle', 'දුෂ්කර'), insight.struggle, AppColors.violet),
          ]),
          if (reasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerLeft,
              child: Wrap(spacing: 6, runSpacing: 6, children: [for (final r in reasons) Pill(r.$1, r.$2)]),
            ),
          ],
        ]),
      ),
    );
  }

  Widget _factor(String l, double v, Color c) => Expanded(
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Builder(
            builder: (context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SoftProgressBar(value: v, color: c, height: 5),
              const SizedBox(height: 4),
              Text(l, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(10, w: FontWeight.w600, c: context.pal.textMuted)),
            ]),
          ),
        ),
      );
}

/// Animated "thinking" state while the plan is built.
class _Thinking extends StatefulWidget {
  const _Thinking();

  @override
  State<_Thinking> createState() => _ThinkingState();
}

class _ThinkingState extends State<_Thinking> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final steps = [
      app.t('Reading exam dates & difficulty', 'විභාග දින සහ අපහසුතාව කියවමින්'),
      app.t('Learning from your study history', 'ඔබේ ඉතිහාසයෙන් ඉගෙන ගනිමින්'),
      app.t('Fitting sessions into free time', 'නිදහස් කාලයට සැසි යොදමින්'),
    ];
    return AppCard(
      padding: const EdgeInsets.all(24),
      child: Column(children: [
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Transform.rotate(
            angle: _c.value * 6.283,
            child: Container(
              width: 70,
              height: 70,
              decoration: const BoxDecoration(
                gradient: SweepGradient(colors: [AppColors.primary, AppColors.violet, Color(0xFFEC4899), AppColors.primary]),
                shape: BoxShape.circle,
              ),
              child: Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle),
                  child: const Icon(Icons.auto_awesome_rounded, color: AppColors.violet, size: 28),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 18),
        Text(app.t('Building your plan…', 'ඔබේ සැලැස්ම සාදමින්…'), style: ts(16, w: FontWeight.w800, c: p.text)),
        const SizedBox(height: 14),
        for (final (i, s) in steps.indexed)
          FadeSlideIn(
            delay: 220 * i,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded, size: 17, color: AppColors.teal),
                const SizedBox(width: 8),
                Expanded(child: Text(s, style: ts(12.5, c: p.textSoft))),
              ]),
            ),
          ),
      ]),
    );
  }
}
