import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { bm25, loadKnowledge } from "../rag.js";
import { classify } from "../guard.js";

const here = dirname(fileURLToPath(import.meta.url));
const questions: { q: string; expect?: string[]; refuse?: boolean }[] = JSON.parse(
  readFileSync(join(here, "..", "..", "eval", "questions.json"), "utf8"),
);
const chunks = loadKnowledge(join(here, "..", "..", "knowledge"));

test("eval set: exactly 20 entries, 17 training + 3 refusals", () => {
  assert.equal(questions.length, 20);
  assert.equal(questions.filter((e) => e.refuse).length, 3);
});

test("eval set: refusals classify medical, training questions retrieve their heading in top 4", () => {
  for (const { q, expect, refuse } of questions) {
    if (refuse) {
      assert.equal(classify(q), "medical", q);
      continue;
    }
    assert.equal(classify(q), "training", q);
    const headings = bm25(q, chunks, 4).map((c) => c.heading);
    for (const h of expect ?? []) {
      assert.ok(headings.includes(h), `${q} → [${h}] not in top 4: ${JSON.stringify(headings)}`);
    }
  }
});
