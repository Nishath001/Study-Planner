const test = require("node:test");
const assert = require("node:assert");
const { parseEmailInput, buildEmail, EmailInputError } = require("./email");

const plan = () => ({
  language: "EN",
  name: "Nimal",
  advice: "Start with Networks.",
  engine: "claude",
  sessions: [
    { date: "2026-11-17", start: "09:00", minutes: 50, subject: "Databases", type: "Practice" },
    { date: "2026-11-16", start: "08:00", minutes: 50, subject: "Networks", type: "Learn" },
    { date: "2026-11-16", start: "10:00", minutes: 40, subject: "<b>Hack</b>", type: "Review" },
  ],
});

test("rejects empty, oversized and malformed plans", () => {
  assert.throws(() => parseEmailInput({ sessions: [] }), EmailInputError);
  assert.throws(() => parseEmailInput({ sessions: Array(201).fill(plan().sessions[0]) }), EmailInputError);
  assert.throws(() => parseEmailInput({ sessions: [{ ...plan().sessions[0], date: "16/11/2026" }] }), EmailInputError);
  assert.throws(() => parseEmailInput({ sessions: [{ ...plan().sessions[0], minutes: 0 }] }), EmailInputError);
});

test("email lists sessions by day, in order, with totals", () => {
  const e = buildEmail(parseEmailInput(plan()));
  assert.strictEqual(e.subject, "Your StudySync study plan · 3 sessions");
  assert.match(e.html, /3 sessions · 2h 20m of study/);
  assert.match(e.html, /Planned by Claude AI/);
  assert.ok(e.html.indexOf("Monday") < e.html.indexOf("Tuesday"));
  assert.ok(e.text.indexOf("08:00") < e.text.indexOf("10:00"));
  assert.match(e.text, /Hi Nimal,/);
});

test("subject names are escaped in HTML", () => {
  const e = buildEmail(parseEmailInput(plan()));
  assert.ok(!e.html.includes("<b>Hack</b>"));
  assert.match(e.html, /&lt;b&gt;Hack&lt;\/b&gt;/);
});

test("Sinhala email", () => {
  const e = buildEmail(parseEmailInput({ ...plan(), language: "SI" }));
  assert.match(e.subject, /සැසි 3/);
  assert.match(e.html, /ආයුබෝවන් Nimal/);
});
