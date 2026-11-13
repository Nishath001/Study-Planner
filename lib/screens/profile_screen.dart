import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../models/models.dart';
import '../state/app_state.dart';
import '../theme/app_theme.dart';
import '../widgets/pref_editors.dart';
import '../widgets/ui.dart';
import 'data_inspector_screen.dart';
import 'subjects_screen.dart';
import 'survey_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    final u = app.user!;
    final pr = app.prefs;

    return Scaffold(
      appBar: AppBar(title: Text(app.t('Profile & settings', 'පැතිකඩ සහ සැකසුම්'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          AppCard(
            gradient: AppColors.brandGradient,
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white54, width: 2)),
                child: Avatar(u.name, size: 58),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(u.isGuest ? app.t('Guest student', 'අමුත්තා') : u.name, style: ts(18, w: FontWeight.w800, c: Colors.white)),
                  Text(u.isGuest ? app.t('Data saved on this device', 'දත්ත මෙම උපාංගයේ') : u.email,
                      style: ts(12.5, c: Colors.white70)),
                  const SizedBox(height: 10),
                  Wrap(spacing: 8, children: [
                    _whiteChip(Icons.local_fire_department_rounded, app.t('${app.streak} day streak', 'දින ${app.streak}')),
                    _whiteChip(Icons.hourglass_bottom_rounded, fmtMinutes(app.totalMinutes)),
                  ]),
                ]),
              ),
            ]),
          ),
          const SizedBox(height: 22),

          _Group(title: app.t('Appearance & language', 'පෙනුම සහ භාෂාව'), children: [
            _Tile(
              icon: Icons.translate_rounded,
              color: AppColors.primary,
              title: app.t('Language', 'භාෂාව'),
              trailing: const LangToggle(),
            ),
            _Tile(
              icon: Icons.dark_mode_rounded,
              color: AppColors.violet,
              title: app.t('Theme', 'තේමාව'),
              trailing: SegmentedButton<ThemeMode>(
                showSelectedIcon: false,
                style: SegmentedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: p.border),
                  selectedBackgroundColor: AppColors.primary,
                  selectedForegroundColor: Colors.white,
                ),
                segments: const [
                  ButtonSegment(value: ThemeMode.system, icon: Icon(Icons.brightness_auto_rounded, size: 18)),
                  ButtonSegment(value: ThemeMode.light, icon: Icon(Icons.light_mode_rounded, size: 18)),
                  ButtonSegment(value: ThemeMode.dark, icon: Icon(Icons.dark_mode_rounded, size: 18)),
                ],
                selected: {app.themeMode},
                onSelectionChanged: (s) => app.setTheme(s.first),
              ),
            ),
          ]),

          _Group(title: app.t('Study plan', 'අධ්‍යයන සැලැස්ම'), children: [
            _Tile(
              icon: Icons.library_books_rounded,
              color: AppColors.teal,
              title: app.t('Subjects & exams', 'විෂයයන් සහ විභාග'),
              subtitle: app.t('${app.subjects.length} subjects', 'විෂයයන් ${app.subjects.length}'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SubjectsScreen())),
            ),
            _Tile(
              icon: Icons.schedule_rounded,
              color: AppColors.amber,
              title: app.t('Availability & study style', 'නිදහස් කාලය සහ රටාව'),
              subtitle: app.t('${fmtMinutes(pr.weeklyMinutes)}/week · ${pr.sessionMinutes} min sessions',
                  'සතියට ${fmtMinutes(pr.weeklyMinutes)} · මිනිත්තු ${pr.sessionMinutes} සැසි'),
              onTap: () => _editPrefs(context, app),
            ),
          ]),

          _Group(title: app.t('Reminders', 'සිහිකැඳවීම්'), children: [
            _Tile(
              icon: Icons.notifications_active_rounded,
              color: AppColors.rose,
              title: app.t('Session reminders', 'සැසි සිහිකැඳවීම්'),
              subtitle: app.t('${pr.reminderLeadMinutes} min before each session', 'සෑම සැසියකටම මිනිත්තු ${pr.reminderLeadMinutes}කට පෙර'),
              trailing: Switch(value: pr.remindersOn, onChanged: (v) => app.savePrefs(pr..remindersOn = v)),
            ),
            if (pr.remindersOn)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Wrap(spacing: 8, children: [
                  for (final m in [5, 10, 15, 30])
                    ChoiceChip(
                      label: Text('$m min'),
                      selected: pr.reminderLeadMinutes == m,
                      showCheckmark: false,
                      selectedColor: AppColors.rose,
                      labelStyle: ts(12, w: FontWeight.w700, c: pr.reminderLeadMinutes == m ? Colors.white : p.textSoft),
                      onSelected: (_) => app.savePrefs(pr..reminderLeadMinutes = m),
                    ),
                ]),
              ),
            _Tile(
              icon: Icons.wb_sunny_rounded,
              color: AppColors.amber,
              title: app.t('Daily plan digest', 'දෛනික සාරාංශය'),
              subtitle: app.t('Every morning at ${pr.dailyDigestHour}:00', 'සෑම උදෑසනකම ${pr.dailyDigestHour}:00 ට'),
              trailing: Switch(value: pr.dailyDigestOn, onChanged: (v) => app.savePrefs(pr..dailyDigestOn = v)),
            ),
          ]),

          _Group(title: app.t('Research participation', 'පර්යේෂණ සහභාගීත්වය'), children: [
            _Tile(
              icon: Icons.verified_user_rounded,
              color: AppColors.green,
              title: app.t('I consent to take part', 'සහභාගී වීමට එකඟයි'),
              subtitle: app.t('Voluntary · anonymous · withdraw any time', 'ස්වේච්ඡා · නිර්නාමික · ඕනෑම විට ඉවත් විය හැක'),
              trailing: Switch(value: app.researchConsent, onChanged: app.setConsent),
            ),
            _Tile(
              icon: Icons.rate_review_rounded,
              color: AppColors.teal,
              title: app.t('Feedback survey', 'ප්‍රතිචාර සමීක්ෂණය'),
              subtitle: app.surveys.isEmpty
                  ? app.t('Takes about 2 minutes', 'මිනිත්තු 2ක් පමණ')
                  : app.t('Last SUS score: ${app.surveys.last.susScore.toStringAsFixed(1)}',
                      'අවසන් SUS: ${app.surveys.last.susScore.toStringAsFixed(1)}'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SurveyScreen())),
            ),
            _Tile(
              icon: Icons.ios_share_rounded,
              color: AppColors.primary,
              title: app.t('Export anonymised data', 'නිර්නාමික දත්ත අපනයනය'),
              subtitle: app.t('Copies JSON for the research team', 'පර්යේෂණ කණ්ඩායම සඳහා JSON පිටපත් කරයි'),
              onTap: () => _export(context, app),
            ),
          ]),

          _Group(title: app.t('Cloud & storage', 'වලාකුළු සහ ගබඩාව'), children: [
            _Tile(
              icon: app.isCloudUser
                  ? (app.cloudError == null ? Icons.cloud_done_rounded : Icons.cloud_sync_rounded)
                  : Icons.cloud_off_rounded,
              color: app.isCloudUser ? (app.cloudError == null ? AppColors.green : AppColors.amber) : p.textMuted,
              title: app.t('Cloud backup (Firebase)', 'වලාකුළු උපස්ථය (Firebase)'),
              subtitle: !app.cloudEnabled
                  ? app.t('Off — Firebase not set up. Data stays on this phone.', 'අක්‍රියයි — Firebase සකසා නැත. දත්ත මෙම දුරකථනයේ පමණි.')
                  : u.isGuest
                      ? app.t('Create an account to back up your data', 'දත්ත උපස්ථ කිරීමට ගිණුමක් සාදන්න')
                      : app.cloudError != null
                          ? app.t('Waiting for internet — changes are saved on this phone', 'අන්තර්ජාලය එනතුරු — වෙනස්කම් දුරකථනයේ සුරකින ලදී')
                          : app.lastCloudSync == null
                              ? app.t('Syncing…', 'සමමුහුර්ත වෙමින්…')
                              : app.t('Synced at ${fmtTime(context, app.lastCloudSync!)}', '${fmtTime(context, app.lastCloudSync!)} ට සමමුහුර්ත විය'),
              trailing: app.isCloudUser
                  ? TextButton(
                      onPressed: () async {
                        await app.syncNow();
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                            content: Text(app.cloudError == null
                                ? app.t('Your data is backed up', 'ඔබේ දත්ත උපස්ථ කර ඇත')
                                : app.t('Offline — will sync when connected', 'නොබැඳි — සම්බන්ධ වූ විට සමමුහුර්ත වේ'))));
                      },
                      child: Text(app.t('Sync now', 'දැන් සමමුහුර්ත කරන්න')),
                    )
                  : null,
            ),
            _Tile(
              icon: Icons.storage_rounded,
              color: AppColors.sky,
              title: app.t('On-device storage', 'උපාංග ගබඩාව'),
              subtitle: app.usesSqlite
                  ? app.t('SQLite database · works offline', 'SQLite දත්ත සමුදාය · නොබැඳිව ක්‍රියා කරයි')
                  : app.t('Browser storage (web demo)', 'බ්‍රවුසර ගබඩාව (වෙබ් ආදර්ශනය)'),
            ),
            _Tile(
              icon: Icons.table_chart_rounded,
              color: AppColors.violet,
              title: app.t('View database & cloud', 'දත්ත සමුදාය සහ වලාකුළ බලන්න'),
              subtitle: app.t('SQLite tables and Firebase sync status', 'SQLite වගු සහ Firebase තත්ත්වය'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const DataInspectorScreen())),
            ),
          ]),

          _Group(title: app.t('Account', 'ගිණුම'), children: [
            if (!u.isGuest && !app.cloudEnabled)
              _Tile(
                icon: Icons.lock_reset_rounded,
                color: app.hasRecovery ? AppColors.green : AppColors.rose,
                title: app.t('Password recovery', 'මුරපද ප්‍රතිසාධනය'),
                subtitle: app.hasRecovery
                    ? app.securityQuestion(app.recoveryQuestionId!)
                    : app.t('Not set — add a security question', 'සකසා නැත — ආරක්ෂක ප්‍රශ්නයක් එක් කරන්න'),
                onTap: () => showDialog(
                  context: context,
                  builder: (_) => ChangeNotifierProvider.value(value: app, child: const _RecoveryDialog()),
                ),
              ),
            _Tile(
              icon: Icons.restart_alt_rounded,
              color: AppColors.amber,
              title: app.t('Reset all my data', 'සියලු දත්ත යළි සකසන්න'),
              onTap: () async {
                final ok = await _confirm(context, app, app.t('Reset all data?', 'සියලු දත්ත මකන්නද?'),
                    app.t('Subjects, tasks, sessions and surveys will be deleted from this device.',
                        'විෂයයන්, කාර්යයන්, සැසි සහ සමීක්ෂණ මෙම උපාංගයෙන් මැකේ.'));
                if (ok && context.mounted) {
                  await app.resetData();
                  if (context.mounted) Navigator.pop(context);
                }
              },
            ),
            _Tile(
              icon: Icons.logout_rounded,
              color: AppColors.rose,
              title: app.t('Sign out', 'වරන්න'),
              onTap: () {
                Navigator.pop(context);
                app.signOut();
              },
            ),
          ]),

          const SizedBox(height: 12),
          Center(
            child: Column(children: [
              Text('StudySync 1.0', style: ts(12.5, w: FontWeight.w800, c: p.textMuted)),
              const SizedBox(height: 4),
              Text('Horizon Campus · BIT (Hons) Networking & Mobile Computing',
                  textAlign: TextAlign.center, style: ts(11, c: p.textMuted)),
            ]),
          ),
        ],
      ),
    );
  }

  Widget _whiteChip(IconData i, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.18), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 13, color: Colors.white),
          const SizedBox(width: 4),
          Text(t, style: ts(11, w: FontWeight.w700, c: Colors.white)),
        ]),
      );

  void _editPrefs(BuildContext context, AppState app) {
    final draft = StudyPreferences.fromJson(app.prefs.toJson());
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => ChangeNotifierProvider.value(
        value: app,
        child: StatefulBuilder(
          builder: (ctx, set) => ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.88),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              children: [
                Text(app.t('Availability & study style', 'නිදහස් කාලය සහ රටාව'), style: ts(20, w: FontWeight.w800, c: ctx.pal.text)),
                const SizedBox(height: 16),
                AvailabilityEditor(prefs: draft, onChanged: () => set(() {})),
                const SizedBox(height: 20),
                StudyStyleEditor(prefs: draft, onChanged: () => set(() {})),
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

  Future<void> _export(BuildContext context, AppState app) async {
    final json = app.exportResearchData();
    await Clipboard.setData(ClipboardData(text: json));
    if (!context.mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(app.t('Copied to clipboard', 'පිටපත් කරන ලදී')),
        content: SizedBox(
          width: 400,
          height: 300,
          child: SingleChildScrollView(
            child: SelectableText(json, style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: ctx.pal.textSoft)),
          ),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: Text(app.t('Close', 'වසන්න')))],
      ),
    );
  }

  Future<bool> _confirm(BuildContext context, AppState app, String title, String body) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(app.t('Cancel', 'අවලංගු'))),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(app.t('Confirm', 'තහවුරු කරන්න'), style: const TextStyle(color: AppColors.rose)),
            ),
          ],
        ),
      ) ??
      false;
}

class _Group extends StatelessWidget {
  final String title;
  final List<Widget> children;
  const _Group({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(title.toUpperCase(), style: AppTheme.font(size: 11.5, weight: FontWeight.w800, color: p.textMuted, spacing: 0.8)),
        ),
        AppCard(padding: const EdgeInsets.symmetric(vertical: 4), child: Column(children: children)),
      ]),
    );
  }
}

class _Tile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  const _Tile({required this.icon, required this.color, required this.title, this.subtitle, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final p = context.pal;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          IconBadge(icon, color, size: 40, radius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: ts(14, w: FontWeight.w700, c: p.text)),
              if (subtitle != null) Text(subtitle!, style: ts(12, c: p.textMuted)),
            ]),
          ),
          if (trailing != null) trailing! else if (onTap != null) Icon(Icons.chevron_right_rounded, color: p.textMuted),
        ]),
      ),
    );
  }
}


/// Add or change the security question used by "Forgot password?".
class _RecoveryDialog extends StatefulWidget {
  const _RecoveryDialog();

  @override
  State<_RecoveryDialog> createState() => _RecoveryDialogState();
}

class _RecoveryDialogState extends State<_RecoveryDialog> {
  late int? _q = context.read<AppState>().recoveryQuestionId;
  final _answer = TextEditingController();
  final _pass = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _answer.dispose();
    _pass.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final app = context.read<AppState>();
    if (_q == null) {
      setState(() => _error = app.t('Choose a question.', 'ප්‍රශ්නයක් තෝරන්න.'));
      return;
    }
    setState(() => _busy = true);
    final err = await app.setRecovery(_pass.text, _q!, _answer.text);
    if (!mounted) return;
    if (err == null) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(app.t('Security question saved', 'ආරක්ෂක ප්‍රශ්නය සුරකින ලදී'))));
      return;
    }
    setState(() {
      _busy = false;
      _error = switch (err) {
        'wrong' => app.t('Current password is incorrect.', 'වත්මන් මුරපදය වැරදියි.'),
        'answer' => app.t('Please enter an answer.', 'පිළිතුරක් ඇතුළත් කරන්න.'),
        _ => app.t('Something went wrong.', 'දෝෂයක් සිදුවිය.'),
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    final app = context.watch<AppState>();
    final p = context.pal;
    return AlertDialog(
      title: Text(app.t('Password recovery', 'මුරපද ප්‍රතිසාධනය')),
      content: SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(app.t('If you forget your password, you can reset it by answering this question.',
                  'මුරපදය අමතක වුවහොත්, මෙම ප්‍රශ්නයට පිළිතුරු දී එය යළි සැකසිය හැක.'),
              style: ts(13, c: p.textSoft, h: 1.45)),
          const SizedBox(height: 14),
          DropdownButtonFormField<int>(
            value: _q,
            isExpanded: true,
            dropdownColor: p.surface,
            decoration: InputDecoration(hintText: app.t('Security question', 'ආරක්ෂක ප්‍රශ්නය')),
            items: [
              for (var i = 0; i < 6; i++)
                DropdownMenuItem(
                  value: i,
                  child: Text(app.securityQuestion(i), maxLines: 2, overflow: TextOverflow.ellipsis, style: ts(13, c: p.text)),
                ),
            ],
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 12),
          TextField(controller: _answer, decoration: InputDecoration(hintText: app.t('Answer', 'පිළිතුර'))),
          const SizedBox(height: 12),
          TextField(
            controller: _pass,
            obscureText: true,
            decoration: InputDecoration(hintText: app.t('Current password', 'වත්මන් මුරපදය')),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: ts(12.5, w: FontWeight.w600, c: AppColors.rose)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(app.t('Cancel', 'අවලංගු'))),
        FilledButton(
          onPressed: _busy ? null : _save,
          style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
          child: Text(app.t('Save', 'සුරකින්න')),
        ),
      ],
    );
  }
}
