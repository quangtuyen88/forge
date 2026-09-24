import test from "node:test";
import assert from "node:assert/strict";
import { createApp, guardAction, parseAction } from "../app.js";
import { ADJUST_PLAN_ACTIONS, buildSystem, PLAN_CHANGES, PLAN_CHANGES_ADJUST } from "../prompt.js";

// --- parseAction ---

test("parseAction: adjustPlan with days and minutes", () => {
  const { text, action } = parseAction(
    'I\'ve prepared 3 days a week with about 45-minute sessions. Review it below.\nACTION {"type":"adjustPlan","daysPerWeek":3,"sessionMinutes":45}',
  );
  assert.deepEqual(action, { type: "adjustPlan", daysPerWeek: 3, sessionMinutes: 45 });
  assert.equal(text, "I've prepared 3 days a week with about 45-minute sessions. Review it below.");
});

test("parseAction: adjustPlan with 2 days parses as an action", () => {
  const { action, unsupportedPlan } = parseAction('Prepared.\nACTION {"type":"adjustPlan","daysPerWeek":2}');
  assert.deepEqual(action, { type: "adjustPlan", daysPerWeek: 2 });
  assert.notEqual(unsupportedPlan, true);
});

test("parseAction: unsupported values return action null with unsupportedPlan", () => {
  for (const line of [
    'ACTION {"type":"adjustPlan","daysPerWeek":1}',
    'ACTION {"type":"adjustPlan","sessionMinutes":35}',
    'ACTION {"type":"adjustPlan","goal":"power"}',
  ]) {
    const { action, unsupportedPlan } = parseAction(`Prepared.\n${line}`);
    assert.equal(action, null, line);
    assert.equal(unsupportedPlan, true, line);
  }
});

test("parseAction: empty adjustPlan object returns action null", () => {
  const { action, unsupportedPlan } = parseAction('Prepared.\nACTION {"type":"adjustPlan"}');
  assert.equal(action, null);
  assert.notEqual(unsupportedPlan, true);
});

// --- guardAction ---

test("guardAction: adjustPlan needs plan-change intent in the question", () => {
  const action = { type: "adjustPlan", daysPerWeek: 3 } as const;
  assert.deepEqual(guardAction(action, "I can only train 3 days a week now"), action);
  assert.equal(guardAction(action, "What should I do tomorrow?"), null);
});

// --- buildSystem ---

test("buildSystem: adjustPlan swaps the prompt sections", () => {
  const withAdjust = buildSystem("ctx", [], "Nova", ["note"], "en", undefined, true);
  assert.ok(withAdjust.includes(ADJUST_PLAN_ACTIONS));
  assert.ok(withAdjust.includes(PLAN_CHANGES_ADJUST));
  assert.ok(!withAdjust.includes(PLAN_CHANGES));
  assert.ok(!withAdjust.includes("Settings → Training"));

  const without = buildSystem("ctx", [], "Nova", ["note"], "en", undefined, false);
  assert.ok(without.includes(PLAN_CHANGES));
  assert.ok(!without.includes("adjustPlan"));
  assert.equal(without, buildSystem("ctx", [], "Nova", ["note"], "en", undefined));
});

// --- /coach handler ---

function coachApp(answer: string) {
  return createApp({
    chunks: [],
    complete: async () => ({ answer, provider: "gemini" }),
    secret: "test",
    providers: [],
  });
}

const H = { "content-type": "application/json", "x-forge-secret": "test" };
function post(app: ReturnType<typeof createApp>, body: unknown) {
  return app(new Request("http://x/coach", { method: "POST", headers: H, body: JSON.stringify(body) }));
}

test("/coach: adjustPlan action passes through only with the capability", async () => {
  const answer =
    'I\'ve prepared 3 days a week with about 45-minute sessions. Review it below.\nACTION {"type":"adjustPlan","daysPerWeek":3,"sessionMinutes":45}';
  const withCap = await (await post(coachApp(answer), {
    question: "I can only train 3 days a week now",
    context: "",
    capabilities: ["adjust_plan"],
  })).json();
  assert.deepEqual(withCap.action, { type: "adjustPlan", daysPerWeek: 3, sessionMinutes: 45 });

  const withoutCap = await (await post(coachApp(answer), {
    question: "I can only train 3 days a week now",
    context: "",
  })).json();
  assert.equal(withoutCap.action, null);
});

test("/coach: unsupported adjustPlan values get the fixed template", async () => {
  const res = await post(coachApp('Sure.\nACTION {"type":"adjustPlan","daysPerWeek":1}'), {
    question: "I can only train 1 day a week now",
    context: "",
    capabilities: ["adjust_plan"],
  });
  const data = await res.json();
  assert.equal(
    data.answer,
    "Regulift plans 2 to 6 training days a week with 45, 60 or 90-minute sessions, so I can't set that up. Tell me a supported option, for example 2 days a week with 45-minute sessions, and I'll prepare it.",
  );
  assert.equal(data.action, null);
});
