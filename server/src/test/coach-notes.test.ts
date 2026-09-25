import test from "node:test";
import assert from "node:assert/strict";
import { createApp, parseAction } from "../app.js";
import { buildSystem } from "../prompt.js";

test("parseAction: remember with a valid note returns action and stripped text", () => {
  const { text, action } = parseAction('Got it. ACTION {"type":"remember","note":"no cable station"}');
  assert.equal(text, "Got it.");
  assert.deepEqual(action, { type: "remember", note: "no cable station" });
});

test("parseAction: remember with empty note returns null action and untouched text", () => {
  const answer = 'Got it. ACTION {"type":"remember","note":""}';
  const { text, action } = parseAction(answer);
  assert.equal(action, null);
  assert.equal(text, answer);
});

test("parseAction: remember with note over 140 chars returns null action", () => {
  const note = "x".repeat(141);
  const answer = `Got it. ACTION {"type":"remember","note":"${note}"}`;
  const { text, action } = parseAction(answer);
  assert.equal(action, null);
  assert.equal(text, answer);
});

test("buildSystem: two notes produce the notes block with both bullets before User training data", () => {
  const system = buildSystem("ctx", [], "Nova", ["no cable station", "refuses sumo deadlift"]);
  assert.ok(system.includes("Lifter notes (facts they told you, respect them):"));
  assert.ok(system.includes("- no cable station"));
  assert.ok(system.includes("- refuses sumo deadlift"));
  assert.ok(system.indexOf("Lifter notes") < system.indexOf("User training data:"));
});

test("buildSystem: no notes means no Lifter notes text", () => {
  const system = buildSystem("ctx", [], "Nova");
  assert.ok(!system.includes("Lifter notes"));
});

test("buildSystem: en language adds no Reply in section", () => {
  const system = buildSystem("ctx", [], "Nova", [], "en");
  assert.ok(!system.includes("Reply in"));
});

test("/coach: language vi reaches complete with Reply in Vietnamese in the system prompt", async () => {
  const seen: string[] = [];
  const app = createApp({
    chunks: [],
    complete: async (system) => {
      seen.push(system);
      return { answer: "stub", provider: "gemini" };
    },
    secret: "test",
    providers: [],
  });
  const res = await app(
    new Request("http://x/coach", {
      method: "POST",
      headers: { "content-type": "application/json", "x-forge-secret": "test" },
      body: JSON.stringify({ question: "how many sets for chest", context: "", language: "vi" }),
    }),
  );
  assert.equal(res.status, 200);
  assert.equal(seen.length, 1);
  assert.ok(seen[0].includes("Reply in Vietnamese"));
});
