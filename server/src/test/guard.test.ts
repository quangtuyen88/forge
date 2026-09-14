import test from "node:test";
import assert from "node:assert/strict";
import { classify, MEDICAL_TERMS } from "../guard.js";

test("every medical keyword classifies as medical", () => {
  for (const term of MEDICAL_TERMS) {
    assert.equal(classify(`should I worry about ${term} in my knee`), "medical", term);
  }
});

test("training questions classify as training", () => {
  assert.equal(classify("why did my squat weight drop"), "training");
  assert.equal(classify("should I add to the number of sets"), "training");
});
