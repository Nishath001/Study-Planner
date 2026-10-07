import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:provider/provider.dart';

import 'main.dart';
import 'models/models.dart';
import 'screens/auth_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/profile_screen.dart';
import 'screens/setup_screen.dart';
import 'screens/shell.dart';
import 'screens/splash_screen.dart';
import 'screens/subjects_screen.dart';
import 'screens/survey_screen.dart';
import 'services/storage_service.dart';
import 'state/app_state.dart';
import 'theme/app_theme.dart';

/// Demo entry point for presentations and screenshots.
/// Seeds a realistic week of data, then opens the screen named in the URL:
///   flutter run -d chrome -t lib/main_demo.dart
///   …/?screen=home|plan|ai|focus|insights|profile|subjects|survey|onboarding|auth|setup&lang=si&theme=dark
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting();
  await StorageService.instance.init();
  final q = Uri.base.queryParameters;
  final state = AppState();
  await state.boot();
  await state.setLanguage(q['lang'] == 'si' ? 'SI' : 'EN');
  await state.setTheme(q['theme'] == 'dark' ? ThemeMode.dark : ThemeMode.light);
  await state.finishOnboarding();
  if (state.user == null) await state.continueAsGuest();
  if (!state.setupDone) await state.completeSetup(consent: true);
  if (state.subjects.isEmpty) await seedDemo(state);

  final screen = q['screen'] ?? 'home';
  const tabs = {'home': 0, 'plan': 1, 'ai': 2, 'focus': 3, 'insights': 4};
  final Widget home = switch (screen) {
    'splash' => const SplashScreen(next: SizedBox(), hold: true),
    'onboarding' => const OnboardingScreen(),
    'auth' => const AuthScreen(),
    'setup' => const SetupScreen(),
    'profile' => const ProfileScreen(),
    'subjects' => const SubjectsScreen(),
    'survey' => const SurveyScreen(),
    _ => MainShell(initialIndex: tabs[screen] ?? 0),
  };

  runApp(ChangeNotifierProvider.value(
    value: state,
    child: Builder(
      builder: (context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: context.watch<AppState>().themeMode,
        home: screen == 'app' ? const RootGate() : home,
      ),
    ),
  ));
}

/// A week of plausible history: sessions with focus ratings, a few missed
/// tasks, and an applied AI plan for the coming days.
Future<void> seedDemo(AppState app) async {
  await app.addSampleSubjects();
  final now = DateTime.now();
  final ids = app.subjects.map((s) => s.id).toList();
  const minutes = [95, 140, 60, 170, 120, 80];
  for (var d = 6; d >= 1; d--) {
    final day = dateOnly(now).subtract(Duration(days: d));
    final total = minutes[6 - d];
    var used = 0, k = 0;
    while (used < total) {
      final len = (total - used).clamp(25, 50);
      final sid = ids[(d + k) % ids.length];
      final start = day.add(Duration(hours: 8 + k * 2));
      final task = StudyTask(
        id: 'demo_${d}_$k',
        subjectId: sid,
        title: '${app.subject(sid)!.name} · ${app.typeLabel(SessionType.values[k % 3])}',
        type: SessionType.values[k % 3],
        start: start,
        durationMinutes: len,
        aiGenerated: true,
      );
      app.tasks.add(task);
      await app.setTaskStatus(task, TaskStatus.completed);
      used += len;
      k++;
    }
    if (d == 2 || d == 4) {
      app.tasks.add(StudyTask(
        id: 'demo_missed_$d',
        subjectId: ids[d % ids.length],
        title: '${app.subject(ids[d % ids.length])!.name} · ${app.typeLabel(SessionType.practice)}',
        type: SessionType.practice,
        start: day.add(const Duration(hours: 19)),
        durationMinutes: 50,
        aiGenerated: true,
        status: TaskStatus.missed,
      ));
    }
  }
  // Focus ratings for the adaptive model.
  for (var i = 0; i < app.sessions.length; i++) {
    final s = app.sessions[i];
    app.sessions[i] = StudySession(
      id: s.id,
      subjectId: s.subjectId,
      taskId: s.taskId,
      start: s.start,
      minutes: s.minutes,
      focusRating: [4, 5, 3, 4, 2, 5][i % 6],
    );
  }
  await app.saveAll();
  final plan = await app.buildPlan();
  if (plan != null) await app.applyPlan(plan);
}
