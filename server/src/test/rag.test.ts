import test from "node:test";
import assert from "node:assert/strict";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { bm25, loadKnowledge } from "../rag.js";

const chunks = loadKnowledge(
  join(dirname(fileURLToPath(import.meta.url)), "..", "..", "knowledge"),
);

test("knowledge base loads with chunks", () => {
  assert.ok(chunks.length >= 20);
});

test("chest volume query returns the chest landmark chunk first", () => {
  assert.equal(bm25("how many sets for chest", chunks)[0]?.heading, "Volume landmarks: chest");
});

test("deload query returns the mesocycle chunk first", () => {
  assert.equal(bm25("deload week intensity", chunks)[0]?.file, "mesocycle.md");
});
