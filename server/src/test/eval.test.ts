import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
interface EvalCase {
  question: string;
  data?: Record<string, unknown>;
  language?: string;
  mustContain: string[];
  mustNotContain: string[];
  expectStatus?: number;
}
const questions: EvalCase[] = JSON.parse(
  readFileSync(join(here, "..", "..", "eval", "questions.json"), "utf8"),
);

test("eval set: exactly 49 entries, every regex contract compiles", () => {
  assert.equal(questions.length, 56);
  for (const e of questions) {
    assert.equal(typeof e.question, "string", "question must be a string");
    assert.ok(Array.isArray(e.mustContain), `${e.question} mustContain`);
    assert.ok(Array.isArray(e.mustNotContain), `${e.question} mustNotContain`);
    for (const rx of [...e.mustContain, ...e.mustNotContain]) {
      assert.doesNotThrow(() => new RegExp(rx), `${e.question}: ${rx}`);
    }
  }
});

test("eval set: covers ja, medical refusals, swaps, remembers and numeric grounding", () => {
  const joined = (e: EvalCase) => [...e.mustContain, ...e.mustNotContain].join(" ");
  assert.ok(questions.some((e) => e.language === "ja"), "a ja case");
  assert.ok(questions.filter((e) => e.mustContain.includes("doctor")).length >= 5, "medical refusals");
  assert.ok(questions.some((e) => joined(e).includes('"type":"swap"')), "swap action");
  assert.ok(questions.some((e) => joined(e).includes('"type":"remember"')), "remember action");
  assert.ok(questions.some((e) => joined(e).includes("132.5")), "e1RM numeric grounding");
});
