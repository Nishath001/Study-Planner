# Study plan emails with EmailJS (free, no Blaze plan)

When a student taps **Apply** on a plan, the app emails the timetable to the address they registered with.
EmailJS sends the email from your Gmail account. The free plan allows 200 emails a month.

## 1. Create the account (2 min)
1. Go to https://www.emailjs.com and **Sign up** (free).

## 2. Connect Gmail
1. Dashboard → **Email Services** → **Add New Service** → **Gmail** → **Connect Account**, and pick the Gmail account the emails should come from.
2. Click **Create Service**. Copy the **Service ID** (looks like `service_ab12cd3`).

## 3. Create the email template
1. Dashboard → **Email Templates** → **Create New Template**.
2. Fill in:
   - **Subject:** `{{subject}}`
   - **To Email** (in the right panel): `{{to_email}}`
   - **From Name:** `StudySync`
   - **Content:** click **Edit Content → Code Editor**, delete everything, and type exactly:
     ```
     {{{plan_html}}}
     ```
     (three curly brackets on each side so the timetable shows as a table)
3. **Save**. Copy the **Template ID** (looks like `template_xy98zt1`).

## 4. Allow the mobile app
1. Dashboard → **Account** → **Security** → tick **Allow EmailJS API for non-browser applications** → Save.
2. Dashboard → **Account** → **General**: copy the **Public Key**.

## 5. Put the three values in the app
Open `lib/services/email_config.dart` and fill in:
```dart
static const serviceId = 'service_...';
static const templateId = 'template_...';
static const publicKey = '...';
```
(or send the three values to Claude to do it), then rebuild the APK:
```
flutter build apk --release
```

## Test
Sign in → AI Planner → Generate → **Apply** → "Plan emailed to you@gmail.com". Check Inbox and Spam.

Limits: 5 plan emails per student per day; students can turn emails off in **Profile → Email my study plans**.
The Cloud Function version (`functions/`, needs Blaze) is used only when these three values are empty.
