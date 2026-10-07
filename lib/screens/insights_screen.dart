import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';
import 'survey_screen.dart';

class InsightsScreen extends StatelessWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final focus = app.avgFocus;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 120),
          children: [
            Text(app.t('Insights', 'විශ්ලේෂණ'), style: ts(26, w: FontWeight.w800, c: p.text)),
            const SizedBox(height: 4),
            Text(app.t('Your study habits at a glance', 'ඔබේ අධ්‍යයන පුරුදු එක බැල්මකින්'), style: ts(13, c: p.textMuted)),
            const SizedBox(height: 18),
            GridView.count(
              padding: EdgeInsets.zero,
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.45,
              children: [
                StatTile(icon: Icons.hourglass_bottom_rounded, color: AppColors.primary,
                    value: fmtMinutes(app.totalMinutes), label: app.t('Total study time', 'මුළු අධ්‍යයන කාලය')),
                StatTile(icon: Icons.local_fire_department_rounded, color: AppColors.amber,
                    value: app.t('${app.streak} days', 'දින ${app.streak}'),
                    label: app.t('Streak · best ${app.bestStreak}', 'අඛණ්ඩ · උපරිම ${app.bestStreak}')),
                StatTile(icon: Icons.task_alt_rounded, color: AppColors.teal,
                    value: '${(app.completionRate * 100).round()}%', label: app.t('Sessions completed', 'සම්පූර්ණ කළ සැසි')),
                StatTile(icon: Icons.psychology_rounded, color: AppColors.violet,
                    value: focus == null ? '—' : '${focus.toStringAsFixed(1)} / 5', label: app.t('Average focus', 'සාමාන්‍ය අවධානය')),
              ],
            ),
            const SizedBox(height: 22),
            _WeeklyChart(app: app),
            const SizedBox(height: 22),
            if (app.subjects.isNotEmpty && app.totalMinutes > 0) ...[
              _SubjectSplit(app: app),
              const SizedBox(height: 22),
            ],
            SectionHeader(app.t('Achievements', 'ජයග්‍රහණ')),
            GridView.count(
              padding: EdgeInsets.zero,
              crossAxisCount: 4,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 10,
              childAspectRatio: 0.72,
              children: [for (final a in app.achievements) _Badge(a: a)],
            ),
            const SizedBox(height: 22),
            AppCard(
              gradient: const LinearGradient(colors: [Color(0xFF0F766E), Color(0xFF0EA5E9)]),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SurveyScreen())),
              child: Row(children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(14)),
                  child: const Icon(Icons.rate_review_rounded, color: Colors.white),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(app.t('Help our research', 'අපගේ පර්යේෂණයට උදව් වන්න'), style: ts(15, w: FontWeight.w800, c: Colors.white)),
                    Text(
                      app.surveys.isEmpty
                          ? app.t('2-minute survey on StudySync', 'මිනිත්තු 2ක සමීක්ෂණය')
                          : app.t('Thanks! ${app.surveys.length} response(s) saved', 'ස්තූතියි! ප්‍රතිචාර ${app.surveys.length}'),
                      style: ts(12.5, c: Colors.white70),
                    ),
                  ]),
                ),
                const Icon(Icons.arrow_forward_rounded, color: Colors.white),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  final AppState app;
  const _WeeklyChart({required this.app});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    final actual = app.last7Days;
    final planned = app.planned7Days;
    final today = dateOnly(DateTime.now());
    final maxY = ([...actual, ...planned, 60].reduce((a, b) => a > b ? a : b) / 60 * 1.15).ceilToDouble();

    return AppCard(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(app.t('Last 7 days', 'පසුගිය දින 7'), style: ts(15, w: FontWeight.w800, c: p.text)),
              Text(app.t('${fmtMinutes(app.weekMinutes)} studied', 'අධ්‍යයනය ${fmtMinutes(app.weekMinutes)}'),
                  style: ts(12, c: p.textMuted)),
            ]),
          ),
          _legend(AppColors.primary, app.t('Studied', 'ඉගෙනගත්'), p),
          const SizedBox(width: 10),
          _legend(p.border, app.t('Planned', 'සැලසුම්'), p),
        ]),
        const SizedBox(height: 18),
        SizedBox(
          height: 180,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              alignment: BarChartAlignment.spaceAround,
              borderData: FlBorderData(show: false),
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: maxY > 6 ? 2 : 1,
                getDrawingHorizontalLine: (_) => FlLine(color: p.border, strokeWidth: 1, dashArray: [4, 4]),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => p.isDark ? const Color(0xFF262C3E) : const Color(0xFF0F172A),
                  getTooltipItem: (group, _, rod, rodIndex) => BarTooltipItem(
                    '${rodIndex == 0 ? app.t('Planned', 'සැලසුම්') : app.t('Studied', 'ඉගෙනගත්')}\n${fmtMinutes((rod.toY * 60).round())}',
                    ts(11.5, w: FontWeight.w700, c: Colors.white),
                  ),
                ),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 28,
                    interval: maxY > 6 ? 2 : 1,
                    getTitlesWidget: (v, _) => v % 1 != 0 ? const SizedBox() : Text('${v.toInt()}h', style: ts(10, c: p.textMuted)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 26,
                    getTitlesWidget: (v, _) {
                      final d = today.subtract(Duration(days: 6 - v.toInt()));
                      final isToday = v.toInt() == 6;
                      return Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(DateFormat.E(context.locale).format(d),
                            style: ts(10.5, w: isToday ? FontWeight.w800 : FontWeight.w600, c: isToday ? AppColors.primary : p.textMuted)),
                      );
                    },
                  ),
                ),
              ),
              barGroups: List.generate(7, (i) => BarChartGroupData(
                    x: i,
                    barsSpace: 4,
                    barRods: [
                      BarChartRodData(
                        toY: planned[i] / 60,
                        width: 9,
                        color: p.border,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      BarChartRodData(
                        toY: actual[i] / 60,
                        width: 9,
                        gradient: const LinearGradient(
                          colors: [AppColors.primary, AppColors.violet],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ],
                  )),
            ),
            duration: const Duration(milliseconds: 600),
          ),
        ),
      ]),
    );
  }

  Widget _legend(Color c, String l, Palette p) => Row(children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: c, borderRadius: BorderRadius.circular(3))),
        const SizedBox(width: 5),
        Text(l, style: ts(11, w: FontWeight.w600, c: p.textMuted)),
      ]);
}

class _SubjectSplit extends StatefulWidget {
  final AppState app;
  const _SubjectSplit({required this.app});

  @override
  State<_SubjectSplit> createState() => _SubjectSplitState();
}

class _SubjectSplitState extends State<_SubjectSplit> {
  int _touched = -1;

  @override
  Widget build(BuildContext context) {
    final app = widget.app;
    final p = context.pal;
    final data = app.subjects
        .map((s) => (s, app.minutesForSubject(s.id)))
        .where((e) => e.$2 > 0)
        .toList()
      ..sort((a, b) => b.$2.compareTo(a.$2));
    final total = data.fold<int>(0, (a, e) => a + e.$2);

    return AppCard(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(app.t('Time by subject', 'විෂය අනුව කාලය'), style: ts(15, w: FontWeight.w800, c: p.text)),
        const SizedBox(height: 16),
        Row(children: [
          SizedBox(
            width: 130,
            height: 130,
            child: Stack(alignment: Alignment.center, children: [
              PieChart(PieChartData(
                sectionsSpace: 3,
                centerSpaceRadius: 40,
                startDegreeOffset: -90,
                pieTouchData: PieTouchData(touchCallback: (e, r) {
                  setState(() => _touched = (e.isInterestedForInteractions && r?.touchedSection != null)
                      ? r!.touchedSection!.touchedSectionIndex
                      : -1);
                }),
                sections: [
                  for (final (i, e) in data.indexed)
                    PieChartSectionData(
                      value: e.$2.toDouble(),
                      color: e.$1.color,
                      radius: i == _touched ? 24 : 18,
                      showTitle: false,
                    ),
                ],
              )),
              Column(mainAxisSize: MainAxisSize.min, children: [
                Text(fmtMinutes(total), style: ts(15, w: FontWeight.w800, c: p.text)),
                Text(app.t('total', 'මුළු'), style: ts(10, c: p.textMuted)),
              ]),
            ]),
          ),
          const SizedBox(width: 18),
          Expanded(
            child: Column(children: [
              for (final e in data.take(5))
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: e.$1.color, borderRadius: BorderRadius.circular(3))),
                    const SizedBox(width: 8),
                    Expanded(child: Text(e.$1.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, w: FontWeight.w600, c: p.textSoft))),
                    Text('${(e.$2 / total * 100).round()}%', style: ts(12.5, w: FontWeight.w800, c: p.text)),
                  ]),
                ),
            ]),
          ),
        ]),
        const SizedBox(height: 18),
        for (final s in app.subjects)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(s.iconData, size: 15, color: s.color),
                const SizedBox(width: 6),
                Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: ts(12.5, w: FontWeight.w700, c: p.text))),
                Text('${fmtMinutes(app.minutesForSubject(s.id))} / ${s.targetHours}h', style: ts(11.5, c: p.textMuted)),
              ]),
              const SizedBox(height: 6),
              SoftProgressBar(value: app.subjectProgress(s), color: s.color, height: 6),
            ]),
          ),
      ]),
    );
  }
}

class _Badge extends StatelessWidget {
  final Achievement a;
  const _Badge({required this.a});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    return Tooltip(
      message: app.t(a.descEn, a.descSi),
      triggerMode: TooltipTriggerMode.tap,
      child: Column(children: [
        Stack(alignment: Alignment.center, children: [
          ProgressRing(
            value: a.progress,
            size: 62,
            stroke: 4,
            colors: [a.color, a.color],
            child: Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: a.unlocked
                    ? LinearGradient(colors: [a.color, Color.lerp(a.color, Colors.white, 0.3)!],
                        begin: Alignment.topLeft, end: Alignment.bottomRight)
                    : null,
                color: a.unlocked ? null : p.surfaceAlt,
              ),
              child: Icon(a.icon, size: 22, color: a.unlocked ? Colors.white : p.textMuted),
            ),
          ),
          if (!a.unlocked)
            Positioned(
              bottom: 0,
              right: 2,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(color: p.surface, shape: BoxShape.circle),
                child: Icon(Icons.lock_rounded, size: 12, color: p.textMuted),
              ),
            ),
        ]),
        const SizedBox(height: 6),
        Text(app.t(a.en, a.si), textAlign: TextAlign.center, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: ts(10.5, w: FontWeight.w700, c: a.unlocked ? p.text : p.textMuted, h: 1.2)),
      ]),
    );
  }
}
