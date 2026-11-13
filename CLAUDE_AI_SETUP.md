# Claude AI via Firebase Cloud Functions

StudySync can build the study timetable with **Claude AI** (model `claude-opus-5-5`) as well as the on-device AI.

```
 Flutter app (signed-in student)
      │  plan inputs: free time per day, busy slots, subjects, exam days, style, language
      ▼
 Cloud Function  generateStudyPlan  (asia-south1)
      │  1. checks Firebase sign-in            → no account, no access
      │  2. checks the inputs                   → size/format limits
      │  3. 10 plans per student per day        → Firestore aiUsage/{uid}
      │  4. asks Claude (API key = Firebase secret, never in the APK)
      │  5. removes any session that breaks the rules (overlaps, exam day, after 23:00, over free time)
      ▼
 App shows the plan ("Claude AI" badge) → student taps Apply → saved to SQLite + Firestore
```

If Claude can't be reached (offline, not deployed, limit reached) the app shows the **on-device plan** and a short message.

## Files
| File | What it is |
|---|---|
| `functions/index.js` | The Cloud Function (auth, rate limit, Claude call) |
| `functions/plan.js` | Input checks, prompt, output checks |
| `functions/plan.test.js` | Tests – run `npm --prefix functions test` |
| `lib/services/claude_service.dart` | App side: calls the function, turns the reply into tasks |
| `test/claude_service_test.dart` | App-side tests |
| `firebase.json`, `.firebaserc` | Firebase CLI config (project `studyapp-28624-6558e`) |
| `deploy_functions.cmd` | One-click deploy |

## One-time setup
1. **Upgrade to Blaze**: Firebase console → ⚙ → *Usage and billing* → *Details & settings* → *Modify plan* → Blaze.
   Cloud Functions require it. The free monthly quota (2M function calls) covers a student project;
   set a **budget alert** (e.g. $5) in the same page.
2. **Get an Anthropic API key**: https://console.anthropic.com → *API keys* (needs credit on the account).
   Each plan costs roughly US$0.02–0.10.
3. **Deploy**: double-click `deploy_functions.cmd` (or run it in a terminal). Paste the API key when asked.
   It is stored in Google Secret Manager as `ANTHROPIC_API_KEY`.

## Use it
App → sign in with an account (not guest) → **AI Planner** → turn on **Plan with Claude AI** → choose a style → **Generate**.

## Show your supervisor
- Firebase console → **Functions**: `generateStudyPlan` listed, with request count.
- Functions → **Logs**: "Plan generated" lines with proposed/kept sessions and token counts.
- Firestore → `aiUsage/{uid}`: per-student daily count (rate limiting).
- Secret Manager: the key is stored server-side; `grep` the APK and it isn't there.

## Useful commands
```
npm --prefix functions test                       # function tests
firebase functions:log --only generateStudyPlan   # recent logs
firebase functions:secrets:set ANTHROPIC_API_KEY  # replace the key
```

---

# Study plan emails (`emailStudyPlan`)

When a signed-in student taps **Apply** on a plan, the app calls the Cloud Function `emailStudyPlan`, which emails the timetable
(grouped by day, in English or Sinhala) to **the email address they registered with**.

- The recipient is taken from the student's Firebase sign-in token, never from the app, so the app can't send email to anyone else.
- Limit: 5 emails per student per day (Firestore `emailUsage/{uid}`).
- Students can turn it off: **Profile → Email my study plans**.
- Guests and local (non-Firebase) accounts don't get emails.
- Preview of the email: `report_screens/email_preview.png`.

## Setup (once)
1. Use a Gmail account for sending (a new one such as `studysync.app@gmail.com` is best).
2. Turn on **2-Step Verification** for it, then create an **App password**: Google Account → Security → App passwords.
3. Run `deploy_functions.cmd`. It asks for the Gmail address (`SMTP_USER`) and the app password (`SMTP_PASS`).

Gmail allows about 500 emails a day, which is plenty for this project.

## Files
| File | What it is |
|---|---|
| `functions/email.js` | Builds the email (HTML + plain text, EN/SI) |
| `functions/email.test.js` | Tests |
| `functions/index.js` | `emailStudyPlan` (sign-in check, limit, sending) |
| `lib/services/plan_email_service.dart` | App side |
