# Firebase + SQLite setup — StudySync

## How data is stored

```
Phone                                   Cloud (Firebase)
┌──────────────────────────┐            ┌───────────────────────────────┐
│ SQLite  studysync.db     │  sync  →   │ Cloud Firestore               │
│  subjects, study_tasks,  │  ← merge   │  users/{uid}                  │
│  study_sessions,         │            │   ├ subjects/{id}             │
│  daily_tasks, surveys,   │            │   ├ tasks/{id}  sessions/{id} │
│  user_kv, app_kv         │            │   └ dailyTasks/{id} surveys/… │
└──────────────────────────┘            │ Firebase Authentication       │
   works fully offline                  │  email + password, reset email│
                                        └───────────────────────────────┘
```

* **SQLite is the source of truth on the phone.** Everything works offline.
* Every change is uploaded to Firestore (queued while offline).
* Signing in on a new phone downloads the student's data and merges it in.
* Guest mode stays on the phone only.
* **Until Firebase is configured the app runs in offline mode**: local accounts,
  security-question password reset, no cloud backup.

## One-time setup (about 15 minutes)

You need: a Google account, Node.js (for the Firebase CLI), and this project.

1. **Create the project** — https://console.firebase.google.com → *Add project* →
   name it `studysync` → Analytics optional → *Create*.

2. **Turn on Email/Password sign-in** — *Build → Authentication → Get started →
   Sign-in method → Email/Password → Enable → Save*.

3. **Create Firestore** — *Build → Firestore Database → Create database* →
   choose a location near Sri Lanka (e.g. `asia-south1`) → *Start in production mode*.

4. **Install the tools** (once, in a terminal):

   ```bash
   npm install -g firebase-tools
   ```

   ```bash
   firebase login
   ```

   ```bash
   dart pub global activate flutterfire_cli
   ```

5. **Connect the app** — in the `studysync` folder:

   ```bash
   flutterfire configure --project=<your-project-id> --platforms=android,web
   ```

   This replaces `lib/firebase_options.dart` and creates
   `android/app/google-services.json`. Android package name: `lk.horizoncampus.studysync`.

6. **Deploy the security rules** (each student can only see their own data):

   ```bash
   firebase deploy --only firestore:rules --project <your-project-id>
   ```

   (If asked, run `firebase init firestore` first and keep the existing `firestore.rules`.)

7. **Run it**:

   ```bash
   flutter run
   ```

   *Profile → Cloud & storage* should now show **Cloud backup: Synced at …**.

## Checking it works

* Register → sign in → add a subject → Firebase console → *Firestore* →
  `users/<uid>/subjects` shows the document.
* *Login → Forgot password?* sends a real reset email (check spam).
* Uninstall, reinstall, sign in → your subjects and tasks come back.

## Notes

* Firebase Auth needs **Android 6.0 (API 23) or newer**.
* Deleting an item on one phone while another phone is offline can bring it back
  when that phone syncs (this phone's copy wins on merge).
* Accounts created in offline mode are not moved to Firebase; register again
  after configuring Firebase.
