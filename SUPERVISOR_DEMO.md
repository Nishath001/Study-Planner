# Showing SQLite and Firebase to the supervisor

About 10 minutes. You need: an Android phone (Android 6.0+) with USB debugging on,
this laptop with Android Studio, and Firebase set up once (see `FIREBASE_SETUP.md`).

## Before the meeting

1. Finish `FIREBASE_SETUP.md` (Firebase project, Email/Password sign-in,
   Firestore, `flutterfire configure`, deploy `firestore.rules`).
2. Plug in the phone and install a **debug** build (the Database Inspector needs it):

   ```bash
   flutter run
   ```

3. Register an account in the app, sign in, add 2–3 subjects and a daily task.
4. Open the Firebase console in the browser: **Authentication** and **Firestore Database**
   tabs, so you can switch to them quickly.

## Part 1 — SQLite (on-device database)

**In the app:** Profile → Cloud & storage → **View database & cloud**.

* The **SQLite** card shows the database is active and how many rows it holds.
* The table list shows the real tables: `subjects`, `study_tasks`,
  `study_sessions`, `daily_tasks`, `surveys`, `user_kv`, with row counts.
* Tap `subjects` → the SQL query that ran
  (`SELECT id, sort_at, data, updated_at FROM subjects WHERE uid = ? …`) and the rows.

**Live change:** add a subject → come back → pull to refresh → the count goes up.

**Proof with an official tool:** Android Studio → **View → Tool Windows → App Inspection →
Database Inspector** → choose the phone and `lk.horizoncampus.studysync` →
`studysync.db`. Open `subjects`, or run a query:

```sql
SELECT id, json_extract(data, '$.name') AS name, sort_at FROM subjects;
```

**Offline:** turn on Airplane mode → add a daily task → it is saved and shown
(SQLite works without internet).

## Part 2 — Firebase (cloud)

**Authentication:** Firebase console → Authentication → Users → the account you
registered is listed (email, created date, UID). The UID matches the one on the
app's *Database & Cloud* screen.

**Cloud Firestore:** Firestore Database → `users` → your UID → `subjects`,
`dailyTasks`, … Each SQLite row is a document here.

**Live sync:** keep the Firestore page open. In the app, add a subject → within
a second the new document appears in the console. On *Database & Cloud* the
**SQLite vs Firestore** counts match (green ticks).

**Offline → online:** with Airplane mode on, add a task → the Firestore count
lags (amber icon) → turn Airplane mode off → tap **Sync now** → the counts match again.

**Password reset email:** sign out → *Forgot password?* → enter the email →
*Send reset link* → show the email from Firebase arriving.

**Security rules:** Firestore → Rules → each student can only read and write
`users/{their uid}` (file: `firestore.rules`).

**New phone / reinstall:** uninstall → install → sign in → the subjects come back
from Firestore into SQLite.

## Explaining the design (one minute)

* **SQLite is the main store on the phone.** The app is fast and works offline,
  which matters for students with patchy internet.
* **Firebase Authentication** handles accounts and password-reset emails.
* **Cloud Firestore** keeps a backup per student. Changes are uploaded
  automatically (queued while offline). Signing in on a new phone merges the
  cloud copy back into SQLite.
* Code: `lib/services/storage_service.dart` (SQLite schema and queries),
  `lib/services/cloud_service.dart` (Firebase Auth and Firestore sync), `firestore.rules`.
* Tests: `test/sqlite_storage_test.dart` (real SQLite), `test/cloud_sync_test.dart` (merge rules).
