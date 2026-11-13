// Builds the "your study plan" email. Pure functions, unit-tested offline.

class EmailInputError extends Error {}

const MAX_SESSIONS = 200;

const esc = (s) =>
  String(s ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");

const clean = (v, max) => String(v ?? "").replace(/[\u0000-\u001f]/g, " ").trim().slice(0, max);

/**
 * App sends: { language, name, advice, engine, sessions: [{date:"2026-11-16", start:"08:00", minutes, subject, type}] }
 */
function parseEmailInput(data) {
  if (!data || typeof data !== "object") throw new EmailInputError("Missing plan");
  const sessions = Array.isArray(data.sessions) ? data.sessions : [];
  if (sessions.length === 0) throw new EmailInputError("The plan has no sessions");
  if (sessions.length > MAX_SESSIONS) throw new EmailInputError(`At most ${MAX_SESSIONS} sessions`);
  return {
    language: data.language === "SI" ? "SI" : "EN",
    name: clean(data.name, 60),
    advice: clean(data.advice, 300),
    engine: data.engine === "claude" ? "claude" : "on-device",
    sessions: sessions.map((s) => {
      const date = clean(s.date, 10);
      const start = clean(s.start, 5);
      if (!/^\d{4}-\d{2}-\d{2}$/.test(date) || !/^\d{2}:\d{2}$/.test(start)) {
        throw new EmailInputError("Each session needs a date (YYYY-MM-DD) and start (HH:mm)");
      }
      const minutes = Math.round(Number(s.minutes));
      if (!Number.isFinite(minutes) || minutes < 1 || minutes > 600) throw new EmailInputError("Bad session length");
      return { date, start, minutes, subject: clean(s.subject, 80) || "Study", type: clean(s.type, 40) };
    }),
  };
}

const T = {
  EN: {
    subject: (n) => `Your StudySync study plan · ${n} sessions`,
    hello: (name) => (name ? `Hi ${name},` : "Hi,"),
    intro: "Here is the study plan you just created in StudySync.",
    total: (n, h) => `${n} sessions · ${h} of study`,
    by: (e) => (e === "claude" ? "Planned by Claude AI" : "Planned by StudySync on-device AI"),
    time: "Time",
    subjectCol: "Subject",
    session: "Session",
    footer: "You get this email because you applied a plan in StudySync. Turn it off in Profile → Email my study plans.",
  },
  SI: {
    subject: (n) => `ඔබේ StudySync අධ්‍යයන සැලැස්ම · සැසි ${n}`,
    hello: (name) => (name ? `ආයුබෝවන් ${name},` : "ආයුබෝවන්,"),
    intro: "ඔබ StudySync තුළ සෑදූ අධ්‍යයන සැලැස්ම මෙන්න.",
    total: (n, h) => `සැසි ${n} · අධ්‍යයන කාලය ${h}`,
    by: (e) => (e === "claude" ? "Claude AI මගින් සැලසුම් කළා" : "StudySync උපාංග AI මගින් සැලසුම් කළා"),
    time: "වේලාව",
    subjectCol: "විෂය",
    session: "සැසිය",
    footer: "ඔබ StudySync හි සැලැස්මක් යෙදූ නිසා මෙම ඊමේල් ලැබුණි. Profile → Email my study plans මගින් නවත්වන්න.",
  },
};

const hours = (m) => (m % 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m / 60}h`);

function dayTitle(date, lang) {
  const d = new Date(`${date}T00:00:00Z`);
  return d.toLocaleDateString(lang === "SI" ? "si-LK" : "en-GB", {
    weekday: "long",
    day: "numeric",
    month: "long",
    timeZone: "UTC",
  });
}

/** Returns { subject, html, text } for the plan email. */
function buildEmail(input) {
  const t = T[input.language];
  const total = input.sessions.reduce((a, s) => a + s.minutes, 0);
  const byDay = new Map();
  for (const s of [...input.sessions].sort((a, b) => (a.date + a.start).localeCompare(b.date + b.start))) {
    if (!byDay.has(s.date)) byDay.set(s.date, []);
    byDay.get(s.date).push(s);
  }

  const days = [...byDay.entries()]
    .map(([date, list]) => {
      const rows = list
        .map(
          (s) => `<tr>
  <td width="70" style="width:70px;padding:8px 10px;border-bottom:1px solid #eef0f6;white-space:nowrap;color:#4338ca;font-weight:700">${esc(s.start)}<br><span style="color:#8a8fa3;font-weight:400;font-size:12px">${s.minutes} min</span></td>
  <td style="padding:8px 10px;border-bottom:1px solid #eef0f6"><b>${esc(s.subject)}</b><br><span style="color:#6b7085;font-size:13px">${esc(s.type)}</span></td>
</tr>`,
        )
        .join("");
      return `<h3 style="margin:22px 0 6px;font-size:15px;color:#1e1b4b">${esc(dayTitle(date, input.language))}</h3>
<table role="presentation" width="100%" cellspacing="0" cellpadding="0" style="border-collapse:collapse;font-size:14px">${rows}</table>`;
    })
    .join("");

  const html = `<!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head><body style="margin:0;background:#f4f5fb;font-family:Segoe UI,Roboto,Helvetica,Arial,sans-serif;color:#1f2133">
<div style="max-width:560px;margin:0 auto;padding:24px 16px">
  <div style="background:linear-gradient(135deg,#1e1b4b,#4338ca,#7c3aed);border-radius:18px;padding:22px;color:#fff">
    <div style="font-size:20px;font-weight:800">StudySync</div>
    <div style="opacity:.85;font-size:13px;margin-top:2px">${esc(t.by(input.engine))}</div>
    <div style="font-size:16px;font-weight:700;margin-top:14px">${esc(t.total(input.sessions.length, hours(total)))}</div>
  </div>
  <div style="background:#fff;border-radius:18px;padding:20px;margin-top:14px">
    <p style="margin:0 0 6px">${esc(t.hello(input.name))}</p>
    <p style="margin:0;color:#4b5065">${esc(t.intro)}</p>
    ${input.advice ? `<p style="margin:14px 0 0;padding:12px 14px;background:#f1efff;border-radius:12px;color:#3b2f8f">“${esc(input.advice)}”</p>` : ""}
    ${days}
  </div>
  <p style="color:#8a8fa3;font-size:12px;line-height:1.5;margin:14px 6px">${esc(t.footer)}</p>
</div></body></html>`;

  const text = [
    t.hello(input.name),
    t.intro,
    t.total(input.sessions.length, hours(total)),
    input.advice ? `"${input.advice}"` : "",
    ...[...byDay.entries()].map(
      ([date, list]) =>
        `\n${dayTitle(date, input.language)}\n` +
        list.map((s) => `  ${s.start} (${s.minutes} min)  ${s.subject} – ${s.type}`).join("\n"),
    ),
    `\n${t.footer}`,
  ]
    .filter(Boolean)
    .join("\n");

  return { subject: t.subject(input.sessions.length), html, text };
}

module.exports = { EmailInputError, parseEmailInput, buildEmail, esc };
