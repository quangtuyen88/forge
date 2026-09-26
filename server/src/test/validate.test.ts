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

test("an answer quoting the app packet's bare e1RM with a unit passes", () => {
  const issues = validateAnswer({
    ...clean,
    answer: "Your best bench is 76 kg.",
    context: "per_lift_bests: Barbell Bench Press 76 e1RM",
    data: "",
  });
  assert.ok(!kinds(issues).includes("invented_number"));
});

test("thousands grouping in the answer matches the plain figure in data", () => {
  const issues = validateAnswer({
    ...clean,
    answer: "This week's tonnage was 18,250 kg.",
    context: "",
    data: "This week tonnage kg 18250",
  });
  assert.ok(!kinds(issues).includes("invented_number"));
});

test("a decimal comma in the answer is read as the source's decimal point", () => {
  const issues = validateAnswer({
    ...clean,
    answer: "Your best e1RM is 92,5 kg.",
    context: "",
    data: "best e1RM 92.5",
  });
  assert.ok(!kinds(issues).includes("invented_number"));
});

test("a figure near but not at the source value is still invented", () => {
  const issues = validateAnswer({
    ...clean,
    answer: "Your e1RM is 95 kg.",
    context: "",
    data: "best e1RM 92.5",
  });
  assert.ok(kinds(issues).includes("invented_number"));
  assert.ok(mustReplace(issues));
});

test("validateAnswer: a number the lifter wrote in the question is not invented", () => {
  const issues = validateAnswer({
    ...clean,
    question: "I want to change my training weight 10kg",
    answer: "Which lift should change by 10 kg?",
  });
  assert.deepEqual(kinds(issues), []);
});

test("validateAnswer: Vietnamese, Japanese and Korean referral language outside a medical refusal is flagged", () => {
  const cases = [
    ["vi", "Hãy tham khảo ý kiến của chuyên gia y tế."],
    ["vi", "Bạn nên đi khám bác sĩ."],
    ["ja", "医師に相談してください。"],
    ["ko", "의사와 상담하세요."],
  ] as const;
  for (const [language, answer] of cases) {
    const issues = validateAnswer({ ...clean, language, answer });
    assert.ok(kinds(issues).includes("medical_disclaimer_misuse"), `${language}: ${answer}`);
  }
});

test("validateAnswer: a load that is a data number plus or minus the lifter's number is not invented", () => {
  const base = { ...clean, question: "Lower my bench by 10kg, it is too heavy" };
  assert.deepEqual(kinds(validateAnswer({ ...base, answer: "Your bench was 80 kg; type 70 kg on the set." })), []);
  assert.deepEqual(kinds(validateAnswer({ ...base, answer: "Or go up to 90 kg later." })), []);
});

test("validateAnswer: a load the lifter's number cannot explain is still invented", () => {
  const base = { ...clean, question: "Lower my bench by 10kg, it is too heavy" };
  assert.ok(kinds(validateAnswer({ ...base, answer: "Type 65 kg on the set." })).includes("invented_number"));
  assert.ok(kinds(validateAnswer({ ...clean, answer: "Type 70 kg on the set." })).includes("invented_number"));
});

// --- R0b: symptom-aware referral check ---

test("referral wording is kept when the question describes a symptom", () => {
  const cases = [
    {
      language: "en",
      question: "My knee feels sore after squats. Should I keep adding weight?",
      answer: "Hold the load; if it keeps hurting, see a physio.",
    },
    {
      language: "vi",
      question: "Gối tôi hơi đau sau khi squat.",
      answer: "Giữ nguyên mức tạ; nếu đau kéo dài, hãy gặp bác sĩ.",
    },
    {
      language: "ja",
      question: "スクワットの後に膝が痛い。",
      answer: "負荷は維持してください。痛みが続くなら医師に相談してください。",
    },
    {
      language: "ko",
      question: "스쿼트 후 무릎이 아파요.",
      answer: "중량을 유지하세요. 통증이 계속되면 의사와 상담하세요.",
    },
  ] as const;
  for (const { language, question, answer } of cases) {
    const issues = validateAnswer({ ...clean, language, question, answer });
    assert.ok(!kinds(issues).includes("medical_disclaimer_misuse"), language);
  }
});

test("referral wording is still flagged when the question has no symptom", () => {
  const en = validateAnswer({ ...clean, question: "I want to change my training weight 10kg", answer: "Please consult a doctor." });
  assert.ok(kinds(en).includes("medical_disclaimer_misuse"));
  const vi = validateAnswer({ ...clean, language: "vi", question: "Tôi muốn thay đổi mức tạ 10kg", answer: "Bạn nên hỏi bác sĩ." });
  assert.ok(kinds(vi).includes("medical_disclaimer_misuse"));
});
