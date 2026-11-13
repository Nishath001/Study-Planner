// StudySync Cloud Functions.
//
// generateStudyPlan: a signed-in student sends their plan inputs; this function
// asks Claude for a timetable and returns it. The Anthropic API key is stored as
// a Firebase secret (ANTHROPIC_API_KEY) and never leaves Google's servers.

const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const logger = require("firebase-functions/logger");
const { initializeApp } = require("firebase-admin/app");
const { getFirestore, FieldValue } = require("firebase-admin/firestore");
const Anthropic = require("@anthropic-ai/sdk").default;

const nodemailer = require("nodemailer");

const { PLAN_SCHEMA, SYSTEM_PROMPT, InputError, parseInput, buildPrompt, cleanSessions } = require("./plan");
const { EmailInputError, parseEmailInput, buildEmail } = require("./email");

initializeApp();

const ANTHROPIC_API_KEY = defineSecret("ANTHROPIC_API_KEY");
const MODEL = "claude-opus-5-5";
const DAILY_LIMIT = 10; // Claude plans per student per day
const EMAIL_DAILY_LIMIT = 5; // plan emails per student per day

// Mail account the plan emails are sent from (e.g. a Gmail address + app password).
const SMTP_USER = defineSecret("SMTP_USER");
const SMTP_PASS = defineSecret("SMTP_PASS");

/** Counts today's requests for this student; refuses once the limit is reached. */
async function useQuota(uid, collection = "aiUsage", limit = DAILY_LIMIT) {
  const db = getFirestore();
  const ref = db.collection(collection).doc(uid);
  const today = new Date().toISOString().slice(0, 10);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = snap.exists && snap.get("day") === today ? snap.get("count") || 0 : 0;
    if (count >= limit) return false;
    tx.set(ref, { day: today, count: count + 1, total: FieldValue.increment(1), lastAt: FieldValue.serverTimestamp() }, { merge: true });
    return true;
  });
}

exports.generateStudyPlan = onCall(
  {
    region: "asia-south1", // same region as the Firestore database
    secrets: [ANTHROPIC_API_KEY],
    timeoutSeconds: 300,
    memory: "256MiB",
    maxInstances: 5,
  },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign in to use Claude AI planning.");
    }

    let input;
    try {
      input = parseInput(request.data);
    } catch (e) {
      if (e instanceof InputError) throw new HttpsError("invalid-argument", e.message);
      throw e;
    }

    if (!(await useQuota(request.auth.uid))) {
      throw new HttpsError("resource-exhausted", `Daily limit of ${DAILY_LIMIT} Claude plans reached. Try again tomorrow.`);
    }

    const client = new Anthropic({ apiKey: ANTHROPIC_API_KEY.value() });
    let response;
    try {
      response = await client.beta.messages.create({
        model: MODEL,
        max_tokens: 16000,
        // If a safety check declines the request, the API retries it on its recommended model.
        betas: ["server-side-fallback-2026-07-01"],
        fallbacks: "default",
        output_config: {
          effort: "medium",
          format: { type: "json_schema", schema: PLAN_SCHEMA },
        },
        system: SYSTEM_PROMPT,
        messages: [{ role: "user", content: buildPrompt(input) }],
      });
    } catch (e) {
      logger.error("Claude request failed", { status: e.status, message: e.message });
      if (e instanceof Anthropic.RateLimitError) {
        throw new HttpsError("resource-exhausted", "Claude is busy right now. Try again in a minute.");
      }
      if (e instanceof Anthropic.AuthenticationError || e instanceof Anthropic.PermissionDeniedError) {
        throw new HttpsError("failed-precondition", "The Claude API key on the server is missing or invalid.");
      }
      throw new HttpsError("unavailable", "Claude could not be reached. Try again shortly.");
    }

    if (response.stop_reason === "refusal") {
      throw new HttpsError("failed-precondition", "Claude declined to build this plan.");
    }
    if (response.stop_reason === "max_tokens") {
      throw new HttpsError("internal", "The plan was too long. Try fewer days or subjects.");
    }

    const textOut = response.content.filter((b) => b.type === "text").map((b) => b.text).join("");
    let plan;
    try {
      plan = JSON.parse(textOut);
    } catch {
      logger.error("Claude returned invalid JSON", { stop_reason: response.stop_reason });
      throw new HttpsError("internal", "Claude returned an unreadable plan.");
    }

    const sessions = cleanSessions(input, plan.sessions);
    logger.info("Plan generated", {
      uid: request.auth.uid,
      proposed: plan.sessions?.length ?? 0,
      kept: sessions.length,
      inputTokens: response.usage?.input_tokens,
      outputTokens: response.usage?.output_tokens,
    });

    return {
      model: MODEL,
      advice: String(plan.advice || "").slice(0, 300),
      sessions,
    };
  },
);

// emailStudyPlan: sends the plan the student just applied to the email address
// they registered with. The address comes from their Firebase sign-in token,
// never from the request, so the app cannot send mail to anyone else.
exports.emailStudyPlan = onCall(
  {
    region: "asia-south1",
    secrets: [SMTP_USER, SMTP_PASS],
    timeoutSeconds: 60,
    memory: "256MiB",
    maxInstances: 5,
  },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in to email your plan.");
    const to = request.auth.token.email;
    if (!to) throw new HttpsError("failed-precondition", "This account has no email address.");

    let input;
    try {
      input = parseEmailInput(request.data);
    } catch (e) {
      if (e instanceof EmailInputError) throw new HttpsError("invalid-argument", e.message);
      throw e;
    }

    if (!(await useQuota(request.auth.uid, "emailUsage", EMAIL_DAILY_LIMIT))) {
      throw new HttpsError("resource-exhausted", `You can email up to ${EMAIL_DAILY_LIMIT} plans a day.`);
    }

    const mail = buildEmail(input);
    const transport = nodemailer.createTransport({
      service: "gmail",
      auth: { user: SMTP_USER.value(), pass: SMTP_PASS.value() },
    });
    try {
      await transport.sendMail({ from: `"StudySync" <${SMTP_USER.value()}>`, to, subject: mail.subject, html: mail.html, text: mail.text });
    } catch (e) {
      logger.error("Plan email failed", { uid: request.auth.uid, code: e.code, response: e.response });
      if (e.code === "EAUTH") {
        throw new HttpsError("failed-precondition", "The email account on the server is not set up correctly.");
      }
      throw new HttpsError("unavailable", "The email could not be sent. Try again shortly.");
    }
    logger.info("Plan emailed", { uid: request.auth.uid, sessions: input.sessions.length });
    return { sentTo: to };
  },
);
