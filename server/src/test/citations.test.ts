import test from "node:test";
import assert from "node:assert/strict";
import { stripCitationTags } from "../app.js";

const HEADINGS = ["Load progression: auto-regulation", "Deload"];

test("bracketed heading and generic [Source: …] tags are removed", () => {
  assert.equal(
    stripCitationTags("The lift went as planned [Load progression: auto-regulation].", HEADINGS),
    "The lift went as planned.",
  );
  assert.equal(
    stripCitationTags("Add 2.5 kg [Source: Load progression] next week.", HEADINGS),
    "Add 2.5 kg next week.",
  );
});

test("unrelated brackets such as [8 to 12 reps] are kept", () => {
  const answer = "Accessories stay in the hypertrophy range [8 to 12 reps].";
  assert.equal(stripCitationTags(answer, HEADINGS), answer);
});

test("spacing and punctuation left behind are cleaned", () => {
  assert.equal(stripCitationTags("planned [Deload].", HEADINGS), "planned.");
  assert.equal(
    stripCitationTags("Loads auto-regulate [deload ] weekly.", HEADINGS),
    "Loads auto-regulate weekly.",
  );
});
