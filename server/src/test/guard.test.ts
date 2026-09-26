import test from "node:test";
import assert from "node:assert/strict";
import { classify, MEDICAL_TERMS } from "../guard.js";

test("every medical keyword classifies as medical", () => {
  for (const term of MEDICAL_TERMS) {
    assert.equal(classify(`should I worry about ${term} in my knee`).bucket, "medical", term);
  }
});

test("training questions classify as training", () => {
  assert.equal(classify("why did my squat weight drop").bucket, "training");
  assert.equal(classify("should I add to the number of sets").bucket, "training");
});

test("missing_fact: birthday question names the field", () => {
  const c = classify("when is my birthday");
  assert.equal(c.bucket, "missing_fact");
  assert.equal(c.field, "birthday");
});

test("ambiguous: weight question carries two readings", () => {
  const c = classify("how much do I weigh");
  assert.equal(c.bucket, "ambiguous");
  assert.deepEqual(c.options, ["your bodyweight", "the load you lift"]);
});

test("medical: shoulder pain stays medical", () => {
  assert.equal(classify("my shoulder hurts").bucket, "medical");
});

test("a fact present in knownFields stays training", () => {
  assert.equal(classify("when is my birthday", ["birthday"]).bucket, "training");
  assert.equal(classify("how much do I weigh", ["bodyweight"]).bucket, "training");
});

// --- R0b: weight-change ambiguity (body weight vs lifted load) ---

test("ambiguous: a weight that went up or down without saying whose", () => {
  const cases = [
    "Why did my weight drop?",
    "my weight went down this week",
    "Tại sao trọng lượng của tôi giảm?",
    "重さが減ったのはなぜ？",
    "무게가 왜 줄었어요?",
  ];
  for (const q of cases) {
    const c = classify(q);
    assert.equal(c.bucket, "ambiguous", q);
    assert.deepEqual(c.options, ["your bodyweight", "the load you lift"], q);
  }
});

test("training: a named weight subject stays training", () => {
  const cases = [
    "Why did my bodyweight drop?",
    "Why did my bench weight drop?",
    "Why did my squat load drop?",
    "Tại sao cân nặng của tôi giảm?",
    "Tại sao mức tạ bench của tôi giảm?",
    "体重が減ったのはなぜ？",
    "ベンチの重量が落ちたのはなぜ？",
    "체중이 왜 줄었어요?",
    "벤치 중량이 왜 줄었어요?",
    "Why did the weight go up so fast on squats?",
    "My weight dropped on rows this week",
  ];
  for (const q of cases) {
    assert.equal(classify(q).bucket, "training", q);
  }
});

test("medical still wins over ambiguous", () => {
  assert.equal(classify("My knee hurts, should I keep training?").bucket, "medical");
});
