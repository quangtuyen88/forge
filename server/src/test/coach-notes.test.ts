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

test("/coach: a question that matches no rule gets the whole rulebook and no citations", async () => {
  const seen: string[] = [];
  const chunks = [
    { id: "a.md:Load progression: auto-regulation", file: "a.md", heading: "Load progression: auto-regulation", text: "Compare actual vs target RPE." },
    { id: "b.md:Mesocycle: deload week", file: "b.md", heading: "Mesocycle: deload week", text: "Cut the sets by half." },
  ];
  const app = createApp({
    chunks,
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
      body: JSON.stringify({ question: "Tôi muốn thay đổi tạ tập 10kg", context: "", language: "vi" }),
    }),
  );
  assert.equal(res.status, 200);
  const body = (await res.json()) as { citations: string[] };
  assert.equal(seen.length, 1);
  assert.ok(seen[0].includes("[Load progression: auto-regulation]"));
  assert.ok(seen[0].includes("[Mesocycle: deload week]"));
  assert.deepEqual(body.citations, []);
});

test("/coach: the load rule is in the prompt only for weight questions, in every shipped language", async () => {
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
  const ask = (question: string, language = "en") =>
    app(
      new Request("http://x/coach", {
        method: "POST",
        headers: { "content-type": "application/json", "x-forge-secret": "test" },
        body: JSON.stringify({ question, context: "", language }),
      }),
    );
  const loadQuestions = [
    ["Tôi muốn thay đổi tạ tập 10kg", "vi"],
    ["Tôi muốn thay đổi tạ tập 10kg".normalize("NFD"), "vi"],
    ["Tôi muốn giảm tạ 10kg vì tập nặng quá", "vi"],
    ["I want to change my training weight 10kg", "en"],
    ["トレーニングの重量を10kg変えたい", "ja"],
    ["운동 중량을 10kg 바꾸고 싶어요", "ko"],
  ] as const;
  for (const [question, language] of loadQuestions) {
    seen.length = 0;
    await ask(question, language);
    assert.ok(seen[0]?.includes("LOAD CHANGES:"), `${language}: ${question}`);
  }
  const otherQuestions = [
    ["Give me a completely different program.", "en"],
    ["Swap my deadlift for a hinge that's easier on my lower back", "en"],
    ["Tôi muốn tạm nghỉ một tuần", "vi"],
  ] as const;
  for (const [question, language] of otherQuestions) {
    seen.length = 0;
    await ask(question, language);
    assert.ok(seen[0] !== undefined && !seen[0].includes("LOAD CHANGES:"), `${language}: ${question}`);
  }
});
