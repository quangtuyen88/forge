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
