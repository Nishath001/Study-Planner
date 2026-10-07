# StudySync — AI-Powered Personalized Study Planner

Horizon Campus · BIT (Hons.) Networking & Mobile Computing  
Flutter app for Android, iOS and web. Built to match the research proposal.

## Proposal → feature map

| Proposal requirement | Old project | This version |
|---|---|---|
| **Obj 1** – AI timetable from subjects, difficulty, **available time** and exam dates | Claude-only; with no key it used a hard-coded schedule that ignored the user's subjects. No available-time input | **On-device adaptive engine** (`lib/services/scheduler_engine.dart`) that works offline. It weighs urgency 40%, difficulty 25%, remaining workload 20% and struggle 15%, fills only your free time per weekday, and plans the day before an exam as final revision. Sessions follow spaced repetition (learn → practice → review, then past papers near exams). Claude is optional |
| Adapts when a student **misses a task / falls behind** | Missing | Overdue tasks become *missed*. **Smart reschedule** moves them into the next free slot before the exam. Load shrinks when your completion rate drops, and subjects you miss or rate low get a boost |
| **Automatic reminders** | Bell icon only | Local notifications before each session plus a daily digest (`notification_service.dart`), and an in-app reminder centre |
| Progress **tracking** | Hard-coded chart data and streak | Real study sessions, a focus timer, a 7-day studied vs planned chart, time per subject, streaks, completion rate, average focus and peak focus hour |
| Motivation | Static streak "7" | Real streaks, achievement badges and a daily goal ring |
| **Obj 2** – Sinhala–English UI | Partial | Every screen is bilingual, with Sinhala date formats and the Noto Sans Sinhala font |
| User inputs: available time, exam schedules, study goals | Missing | First-run setup wizard (availability, preferred time, session length, daily goal) |
| **Obj 3** – evaluate via surveys / beta testing | Missing | In-app survey: the 10-item SUS plus items mapped to RQ1–RQ3. **Anonymised JSON export** with usage metrics for analysis |
| Ethics: informed consent, anonymity | Missing | Consent step during setup (can be withdrawn in Settings). Exports contain no name, email or ID |
| Local offline storage (SQLite/Hive) | SharedPreferences | **Hive**, one box per user |
| Authentication | Plain-text passwords | Salted SHA-256 hashing, plus guest mode |

## Run

```bash
flutter pub get
flutter run                      # Android / iOS / Chrome
flutter test                     # scheduler engine tests
flutter run -d chrome -t lib/main_demo.dart   # demo mode with a seeded week of data
```

Demo mode accepts `?screen=home|plan|ai|focus|insights|profile|subjects|survey|onboarding|auth|setup&lang=si&theme=dark`.
It is handy for viva screenshots.

Built and tested on Flutter 3.22.1 / Dart 3.4. Packages are pinned for that version (`fl_chart 0.69`, `flutter_local_notifications 17`).

## Structure

```
lib/
  models/models.dart              Subject, StudyTask, StudySession, StudyPreferences, SurveyResponse
  services/scheduler_engine.dart  on-device AI planner + rescheduler (unit-tested)
  services/claude_service.dart    optional cloud planner (API key in Settings)
  services/notification_service.dart
  services/storage_service.dart   Hive
  services/auth_service.dart      local accounts, hashed passwords
  state/app_state.dart            app state, analytics, achievements, research export
  screens/                        onboarding, auth, setup, home, plan, ai_planner, focus,
                                  insights, subjects, profile, survey
  widgets/                        design system (cards, rings, task cards, editors)
```

## Not included (optional in the proposal)

- **Firebase cloud sync.** The app is offline-first. A Firebase repository can be added behind `StorageService` once a Firebase project is configured.
- **TensorFlow Lite.** The planner is a transparent, rule-based model instead. It is explainable, works with little data and suits the 20–30 participant study. The data it logs (focus ratings, misses, completions) can train a TFLite model later.
- **Sinhala TTS/STT voice assistant.** Listed as optional.
