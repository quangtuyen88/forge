import test from "node:test";
import assert from "node:assert/strict";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { bm25, loadKnowledge, rrf, type Chunk } from "../rag.js";

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

test("rrf: fuses ranked lists, dedupes by id, top-k", () => {
  const c = (id: string): Chunk => ({ id, file: "f.md", heading: id, text: "" });
  const a = [c("x"), c("y"), c("z")];
  const b = [c("y"), c("w"), c("x")];
  // y = 1/62 + 1/61, x = 1/61 + 1/63 (deduped), w = 1/62, z = 1/63
  assert.deepEqual(rrf([a, b], 3).map((f) => f.id), ["y", "x", "w"]);
  assert.deepEqual(rrf([a, []], 4).map((f) => f.id), ["x", "y", "z"]);
});
