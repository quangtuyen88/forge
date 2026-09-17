import test from "node:test";
import assert from "node:assert/strict";
import { validateAnswer, mustReplace, type Issue } from "../validate.js";

const clean = {
  answer: "Your bench is at 80 kg — keep the load steady.",
  bucket: "training" as const,
  context: "bench press 80 kg",
  data: "Lift: bench press, last set 80 kg x 8 reps",
  language: "en",
};

function kinds(issues: Issue[]): string[] {
  return issues.map((i) => i.kind);
}

test("prompt_leak fires on system-prompt talk or URLs", () => {
  const issues = validateAnswer({ ...clean, answer: "My system prompt says to be concise." });
  assert.ok(kinds(issues).includes("prompt_leak"));
  assert.ok(mustReplace(issues));
});

test("internal_tag fires on a stray ACTION outside the parsed line", () => {
  const issues = validateAnswer({
    ...clean,
    answer: 'Do this. ACTION {"type":"swap","from":"a","to":"b"} then that.',
  });
  assert.ok(kinds(issues).includes("internal_tag"));
  assert.ok(mustReplace(issues));
});

test("medical_disclaimer_misuse fires on referral language outside medical", () => {
  const issues = validateAnswer({ ...clean, answer: "You should ask a doctor about that." });
  assert.ok(kinds(issues).includes("medical_disclaimer_misuse"));
  assert.ok(mustReplace(issues));
});

test("unsupported_action fires on an unknown action type", () => {
  const issues = validateAnswer({ ...clean, answer: 'Ok. ACTION {"type":"explode"}' });
  assert.ok(kinds(issues).includes("unsupported_action"));
  assert.ok(!mustReplace(issues));
});

test("invented_number fires when a number is absent from context and data", () => {
  const issues = validateAnswer({ ...clean, answer: "Add 37 kg next session." });
  assert.ok(kinds(issues).includes("invented_number"));
  assert.ok(mustReplace(issues));
});

test("wrong_language fires when a ja answer has no Japanese script", () => {
  const issues = validateAnswer({ ...clean, language: "ja", answer: "Keep the load steady." });
  assert.ok(kinds(issues).includes("wrong_language"));
  assert.ok(!mustReplace(issues));
});

test("wrong_language fires when a ko answer has no Korean script", () => {
  const issues = validateAnswer({ ...clean, language: "ko", answer: "Keep the load steady." });
  assert.ok(kinds(issues).includes("wrong_language"));
});

test("a clean answer produces no issues", () => {
  assert.deepEqual(validateAnswer(clean), []);
});

test("a number present in the data passes, an invented one is flagged", () => {
  const ok = validateAnswer({ ...clean, answer: "Add 2.5 kg next week.", data: "Lift: bench press, last set 2.5 kg" });
  assert.ok(!kinds(ok).includes("invented_number"));
  const bad = validateAnswer({ ...clean, answer: "Add 40 kg next week." });
  assert.ok(kinds(bad).includes("invented_number"));
});
