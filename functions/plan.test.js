const test = require("node:test");
const assert = require("node:assert");
const { parseInput, buildPrompt, cleanSessions, InputError } = require("./plan");

const base = () => ({
  language: "EN",
  mode: "balanced",
  sessionMinutes: 50,
  breakMinutes: 10,
  adherence: 0.8,
  days: [
    { weekday: "Mon", startMinute: 8 * 60, minutes: 120, busy: [[10 * 60, 11 * 60]] },
    { weekday: "Tue", startMinute: 8 * 60, minutes: 60, busy: [] },
  ],
  subjects: [
    { id: "net", name: "Networks", difficulty: "hard", daysToExam: 1, remainingMinutes: 600, priority: 0.9 },
    { id: "db", name: "Databases", difficulty: "easy", daysToExam: null, remainingMinutes: 300, priority: 0.4 },
  ],
});

test("parseInput rejects empty and oversized inputs", () => {
  assert.throws(() => parseInput({}), InputError);
  assert.throws(() => parseInput({ ...base(), subjects: [] }), InputError);
  assert.throws(() => parseInput({ ...base(), days: Array(15).fill(base().days[0]) }), InputError);
  assert.throws(() => parseInput({ ...base(), sessionMinutes: 5 }), InputError);
});

test("parseInput rejects duplicate subject ids and cleans names", () => {
  const dup = base();
  dup.subjects[1].id = "net";
  assert.throws(() => parseInput(dup), InputError);
  const odd = base();
  odd.subjects[0].name = "Net\nworks";
  assert.strictEqual(parseInput(odd).subjects[0].name, "Net works");
});

test("buildPrompt includes days, subjects, mode and language", () => {
  const p = buildPrompt(parseInput({ ...base(), mode: "examFocus", language: "SI" }));
  assert.match(p, /day 0 \(Mon\): up to 120 min, not before 08:00; busy 10:00-11:00/);
  assert.match(p, /id "net": "Networks", hard, exam in 1 days/);
  assert.match(p, /Exam focus/);
  assert.match(p, /Sinhala/);
});

test("cleanSessions drops rule-breaking sessions", () => {
  const input = parseInput(base());
  const s = (o) => ({ day: 0, subjectId: "db", startHour: 8, startMinute: 0, minutes: 50, type: "learn", ...o });
  const out = cleanSessions(input, [
    s({}), // ok
    s({ startHour: 8, startMinute: 30 }), // overlaps the first
    s({ startHour: 10, startMinute: 15 }), // inside busy time
    s({ subjectId: "net", day: 1, startHour: 9 }), // on exam day
    s({ subjectId: "nope", startHour: 12 }), // unknown subject
    s({ startHour: 7 }), // before earliest start
    s({ startHour: 22, startMinute: 30 }), // ends after 23:00
    s({ startHour: 13, minutes: 50 }), // ok (100 of 120 min)
    s({ startHour: 15, minutes: 50 }), // over the day's free minutes
    s({ day: 1, startHour: 9, type: "review" }), // ok
  ]);
  assert.deepStrictEqual(
    out.map((x) => `${x.day}@${x.startHour}:${x.startMinute}`),
    ["0@8:0", "0@13:0", "1@9:0"],
  );
});
