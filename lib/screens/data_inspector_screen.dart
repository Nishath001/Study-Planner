import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/cloud_service.dart';
import '../services/storage_service.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/ui.dart';

/// Shows where the student's data lives: the SQLite tables on the phone and
/// the Firebase project / Firestore copy. Built for demonstrating the storage
/// layer (e.g. to a supervisor) without extra tools.
class DataInspectorScreen extends StatefulWidget {
  const DataInspectorScreen({super.key});

  @override
  State<DataInspectorScreen> createState() => _DataInspectorScreenState();
}

class _DataInspectorScreenState extends State<DataInspectorScreen> {
  final _store = StorageService.instance;
  final _cloud = CloudService.instance;
  List<(String, String, int)> _tables = [];
  Map<String, int>? _remote;
  String? _remoteError;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() => _loading = true);
    final cloudUser = context.read<AppState>().isCloudUser;
    final tables = await _store.tableStats();
    Map<String, int>? remote;
    String? err;
    if (cloudUser) {
      try {
        remote = await _cloud.remoteCounts();
      } catch (e) {
        err = '$e';
      }
    }
    if (!mounted) return;
    setState(() {
      _tables = tables;
      _remote = remote;
      _remoteError = err;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final totalRows = _tables.fold<int>(0, (a, t) => a + t.$3);

    return Scaffold(
      appBar: AppBar(
        title: Text(app.t('Database & Cloud', 'දත්ත සමුදාය සහ වලාකුළ')),
        actions: [
          IconButton(
            tooltip: app.t('Refresh', 'නැවුම් කරන්න'),
            onPressed: _loading ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            // ── Overview ───────────────────────────────────────────────
            FlexGrid(columns: 2, children: [
              _StatusCard(
                icon: Icons.storage_rounded,
                color: AppColors.sky,
                title: 'SQLite',
                status: app.usesSqlite ? app.t('Active on this phone', 'මෙම දුරකථනයේ සක්‍රියයි') : app.t('Web demo uses browser storage', 'වෙබ් සඳහා බ්‍රවුසර ගබඩාව'),
                ok: app.usesSqlite,
                detail: app.t('$totalRows rows', 'පේළි $totalRows'),
              ),
              _StatusCard(
                icon: Icons.local_fire_department_rounded,
                color: AppColors.amber,
                title: 'Firebase',
                status: !app.cloudEnabled
                    ? app.t('Not set up', 'සකසා නැත')
                    : app.isCloudUser
                        ? app.t('Connected', 'සම්බන්ධයි')
                        : app.t('Sign in to sync', 'සමමුහුර්තයට පිවිසෙන්න'),
                ok: app.isCloudUser,
                detail: _cloud.projectId ?? '—',
              ),
            ]),
            const SizedBox(height: 22),

            // ── SQLite ─────────────────────────────────────────────────
            SectionHeader(app.t('SQLite tables (this phone)', 'SQLite වගු (මෙම දුරකථනය)')),
            if (_store.databasePath != null)
              _InfoRow(Icons.insert_drive_file_rounded, app.t('Database file', 'දත්ත ගොනුව'), _store.databasePath!),
            if (app.user != null) _InfoRow(Icons.badge_rounded, app.t('Rows for user', 'පරිශීලකයාගේ පේළි'), app.user!.id),
            const SizedBox(height: 10),
            AppCard(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(children: [
                for (final (table, key, rows) in _tables)
                  ListTile(
                    onTap: () => _showTable(context, table),
                    leading: const Icon(Icons.table_chart_rounded, color: AppColors.sky),
                    title: Text(table, style: AppTheme.font(size: 14, weight: FontWeight.w700, color: p.text).copyWith(fontFamily: 'monospace')),
                    subtitle: Text(_tableLabel(app, key), style: ts(12, c: p.textMuted)),
                    trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                      Pill('$rows', AppColors.sky),
                      Icon(Icons.chevron_right_rounded, color: p.textMuted),
                    ]),
                  ),
              ]),
            ),
            const SizedBox(height: 8),
            Text(app.t('Tap a table to see its rows and the SQL query.', 'පේළි සහ SQL විමසුම බැලීමට වගුවක් ඔබන්න.'),
                style: ts(12, c: p.textMuted)),
            const SizedBox(height: 22),

            // ── Firebase ───────────────────────────────────────────────
            SectionHeader(app.t('Firebase (cloud)', 'Firebase (වලාකුළ)')),
            if (!app.cloudEnabled)
              AppCard(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(app.t('Firebase is not connected yet', 'Firebase තවම සම්බන්ධ කර නැත'),
                      style: ts(14.5, w: FontWeight.w800, c: p.text)),
                  const SizedBox(height: 6),
                  Text(
                    app.t('Follow FIREBASE_SETUP.md: create a Firebase project, enable Email/Password sign-in and Firestore, then run "flutterfire configure". The app is using local accounts and SQLite only.',
                        'FIREBASE_SETUP.md අනුගමනය කරන්න: Firebase ව්‍යාපෘතියක් සාදා, Email/Password සහ Firestore සක්‍රිය කර "flutterfire configure" ධාවනය කරන්න.'),
                    style: ts(12.5, c: p.textSoft, h: 1.5),
                  ),
                ]),
              )
            else ...[
              _InfoRow(Icons.cloud_rounded, app.t('Project', 'ව්‍යාපෘතිය'), _cloud.projectId ?? '—'),
              _InfoRow(Icons.person_rounded, app.t('Signed in', 'පිවිසී ඇත'),
                  app.isCloudUser ? '${app.user!.email}\nuid: ${app.user!.id}' : app.t('Guest (not synced)', 'අමුත්තා (සමමුහුර්ත නැත)')),
              _InfoRow(Icons.sync_rounded, app.t('Last sync', 'අවසන් සමමුහුර්තය'),
                  app.lastCloudSync == null ? '—' : fmtTime(context, app.lastCloudSync!)),
              if (app.isCloudUser) ...[
                const SizedBox(height: 10),
                AppCard(
                  child: Column(children: [
                    Row(children: [
                      Expanded(child: Text(app.t('Collection', 'එකතුව'), style: ts(12, w: FontWeight.w800, c: p.textMuted))),
                      SizedBox(width: 64, child: Text('SQLite', textAlign: TextAlign.center, style: ts(12, w: FontWeight.w800, c: AppColors.sky))),
                      SizedBox(width: 72, child: Text('Firestore', textAlign: TextAlign.center, style: ts(12, w: FontWeight.w800, c: AppColors.amber))),
                    ]),
                    const Divider(height: 18),
                    for (final (_, key, rows) in _tables.where((t) => t.$2.isNotEmpty))
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(children: [
                          Expanded(
                            child: Text('users/…/$key',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTheme.font(size: 12.5, weight: FontWeight.w600, color: p.text).copyWith(fontFamily: 'monospace')),
                          ),
                          SizedBox(width: 64, child: Text('$rows', textAlign: TextAlign.center, style: ts(14, w: FontWeight.w800, c: p.text))),
                          SizedBox(
                            width: 72,
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(_remote == null ? '…' : '${_remote![key] ?? 0}', style: ts(14, w: FontWeight.w800, c: p.text)),
                              if (_remote != null) ...[
                                const SizedBox(width: 4),
                                Icon(
                                  _remote![key] == rows ? Icons.check_circle_rounded : Icons.sync_problem_rounded,
                                  size: 15,
                                  color: _remote![key] == rows ? AppColors.green : AppColors.amber,
                                ),
                              ],
                            ]),
                          ),
                        ]),
                      ),
                  ]),
                ),
                if (_remoteError != null) ...[
                  const SizedBox(height: 8),
                  Text(app.t('Could not reach Firestore (offline?). Changes are saved in SQLite and will upload later.',
                          'Firestore වෙත ළඟා විය නොහැක. වෙනස්කම් SQLite හි සුරකින අතර පසුව උඩුගත වේ.'),
                      style: ts(12, c: AppColors.amber)),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : () async {
                          await app.syncNow();
                          await _refresh();
                        },
                  icon: const Icon(Icons.cloud_sync_rounded, size: 18),
                  label: Text(app.t('Sync now', 'දැන් සමමුහුර්ත කරන්න')),
                ),
              ],
            ],
            const SizedBox(height: 22),
            AppCard(
              color: AppColors.primary.withOpacity(p.isDark ? 0.14 : 0.07),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Icon(Icons.lightbulb_rounded, color: AppColors.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    app.t('Live demo: add a subject or daily task, come back and tap refresh. The new row appears in SQLite straight away, and in Firestore a moment later.',
                        'සජීවී ආදර්ශනය: විෂයයක් හෝ කාර්යයක් එක් කර, මෙතැනට පැමිණ නැවුම් කරන්න. නව පේළිය SQLite හි වහාම ද Firestore හි ටික වේලාවකින් ද පෙනේ.'),
                    style: ts(12.5, c: p.textSoft, h: 1.5),
                  ),
                ),
              ]),
            ),
          ],
        ),
      ),
    );
  }

  String _tableLabel(AppState app, String key) => switch (key) {
        'subjects' => app.t('Subjects & exam dates', 'විෂයයන් සහ විභාග දින'),
        'tasks' => app.t('AI-planned study sessions', 'AI සැලසුම් කළ සැසි'),
        'sessions' => app.t('Completed study / focus time', 'සම්පූර්ණ කළ අධ්‍යයන කාලය'),
        'dailyTasks' => app.t('Daily to-do tasks', 'දෛනික කාර්යයන්'),
        'surveys' => app.t('Research survey answers', 'සමීක්ෂණ පිළිතුරු'),
        _ => app.t('Settings & preferences', 'සැකසුම් සහ මනාපයන්'),
      };

  Future<void> _showTable(BuildContext context, String table) async {
    final rows = await _store.tableRows(table);
    if (!context.mounted) return;
    final p = context.pal;
    final mono = AppTheme.font(size: 11.5, weight: FontWeight.w500, color: p.textSoft).copyWith(fontFamily: 'monospace');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.85),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: [
            Text(table, style: AppTheme.font(size: 20, weight: FontWeight.w800, color: p.text).copyWith(fontFamily: 'monospace')),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF0F172A), borderRadius: BorderRadius.circular(12)),
              child: Text(StorageService.querySql(table),
                  style: AppTheme.font(size: 12, weight: FontWeight.w600, color: const Color(0xFF7DD3FC)).copyWith(fontFamily: 'monospace')),
            ),
            const SizedBox(height: 10),
            Text('${rows.length} rows', style: ts(12.5, w: FontWeight.w700, c: p.textMuted)),
            const SizedBox(height: 10),
            for (final r in rows)
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: p.surfaceAlt, borderRadius: BorderRadius.circular(12)),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  for (final e in r.entries)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 3),
                      child: Text.rich(TextSpan(children: [
                        TextSpan(text: '${e.key}: ', style: mono.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800)),
                        TextSpan(text: _short(e.key, e.value), style: mono),
                      ])),
                    ),
                ]),
              ),
          ],
        ),
      ),
    );
  }

  /// Pretty, shortened cell value.
  static String _short(String column, Object? v) {
    if (v == null) return 'NULL';
    if (column == 'updated_at' && v is int) return DateTime.fromMillisecondsSinceEpoch(v).toIso8601String().substring(0, 19);
    var s = v.toString();
    if ((column == 'data' || column == 'value') && s.startsWith('{')) {
      try {
        final m = jsonDecode(s) as Map;
        s = m.entries.take(6).map((e) => '${e.key}=${e.value}').join(', ') + (m.length > 6 ? ', …' : '');
      } catch (_) {}
    }
    return s.length > 220 ? '${s.substring(0, 220)}…' : s;
  }
}

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, status, detail;
  final bool ok;
  const _StatusCard({required this.icon, required this.color, required this.title, required this.status, required this.detail, required this.ok});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          IconBadge(icon, color, size: 38, radius: 12),
          const Spacer(),
          Icon(ok ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              size: 18, color: ok ? AppColors.green : p.textMuted),
        ]),
        const SizedBox(height: 10),
        Text(title, style: ts(16, w: FontWeight.w800, c: p.text)),
        const SizedBox(height: 2),
        Text(status, style: ts(12, w: FontWeight.w700, c: ok ? AppColors.green : p.textSoft, h: 1.3)),
        const SizedBox(height: 4),
        Text(detail, maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(11.5, c: p.textMuted)),
      ]),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  const _InfoRow(this.icon, this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 17, color: p.textMuted),
        const SizedBox(width: 8),
        SizedBox(width: 92, child: Text(label, style: ts(12.5, w: FontWeight.w700, c: p.textSoft))),
        Expanded(child: SelectableText(value, style: ts(12.5, c: p.text, h: 1.4))),
      ]),
    );
  }
}
