import test from "node:test";
import assert from "node:assert/strict";
import { createApp, assignVariant, fnv1a, type EventsBinding } from "../app.js";
import { loadKnowledgeFromStrings } from "../rag.js";
import { KNOWLEDGE } from "../knowledge.generated.js";

const chunks = loadKnowledgeFromStrings(KNOWLEDGE);
const calls: { system: string; last: string }[] = [];
let stubAnswer = "stub answer";
const app = createApp({
  chunks,
  complete: async (system, messages) => {
    calls.push({ system, last: messages.at(-1)!.content });
    return { answer: stubAnswer, provider: "gemini" };
  },
  secret: "test",
  providers: ["gemini", "claude"],
});

function post(body: unknown, secret?: string) {
  return app(
    new Request("http://x/coach", {
      method: "POST",
      headers: {
        "content-type": "application/json",
        ...(secret ? { "x-forge-secret": secret } : {}),
      },
      body: JSON.stringify(body),
    }),
  );
}

test("401 without secret, provider never called", async () => {
  const res = await post({ question: "how many sets for chest" });
  assert.equal(res.status, 401);
  assert.equal(calls.length, 0);
});

test("medical question is refused", async () => {
  const res = await post({ question: "my shoulder hurts when I bench", context: "" }, "test");
  assert.equal(res.status, 200);
  const data = await res.json();
  assert.equal(data.refused, true);
  assert.deepEqual(data.citations, []);
});

test("training question returns stub answer with citation heading", async () => {
  const res = await post({ question: "how many sets for chest", context: "" }, "test");
  assert.equal(res.status, 200);
  const data = await res.json();
  assert.equal(data.answer, "stub answer");
  assert.equal(data.refused, false);
  assert.ok(data.citations.includes("Volume landmarks: chest"));
  assert.ok(calls.at(-1)!.system.includes("[Volume landmarks: chest]"));
  assert.equal(calls.at(-1)!.last, "how many sets for chest");
});

test("coach field selects the persona; only Nova and Kai accepted", async () => {
  await post({ question: "how many sets for chest", coach: "Kai" }, "test");
  assert.ok(calls.at(-1)!.system.includes("You are Kai, a strength coach inside the Regulift app."));
  assert.ok(calls.at(-1)!.system.includes("Tone: warm, high energy, direct, still concise."));

  await post({ question: "how many sets for back", coach: "  Nova  " }, "test");
  assert.ok(calls.at(-1)!.system.includes("You are Nova, a strength coach inside the Regulift app."));

  await post({ question: "how many sets for quads", coach: "Arnold" }, "test");
  assert.ok(calls.at(-1)!.system.includes("You are Nova, a strength coach inside the Regulift app."));
});

test("/health returns the health shape", async () => {
  const res = await app(new Request("http://x/health"));
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), {
    ok: true,
    chunks: chunks.length,
  });
});

test("valid trailing ACTION line is parsed and stripped", async () => {
  stubAnswer = 'Sure, swap it.\nACTION {"type":"swap","from":"barbell_bench","to":"incline_barbell_press"}';
  try {
    const res = await post({ question: "swap my bench press", context: "Exercise ids: Barbell Bench Press=barbell_bench" }, "test");
    assert.equal(res.status, 200);
    const data = await res.json();
    assert.equal(data.answer, "Sure, swap it.");
    assert.deepEqual(data.action, { type: "swap", from: "barbell_bench", to: "incline_barbell_press" });
  } finally {
    stubAnswer = "stub answer";
  }
});

test("malformed ACTION line keeps action null and text untouched", async () => {
  stubAnswer = 'Here you go.\nACTION {"type":"swap"}';
  try {
    const res = await post({ question: "swap my bench press", context: "" }, "test");
    const data = await res.json();
    assert.equal(data.action, null);
    assert.equal(data.answer, stubAnswer);
  } finally {
    stubAnswer = "stub answer";
  }
});

test("inline ACTION none is stripped and action is null", async () => {
  stubAnswer = 'Weight drops with fatigue. ACTION {"type":"none"}';
  try {
    const res = await post({ question: "why did my weight drop", context: "" }, "test");
    const data = await res.json();
    assert.equal(data.action, null);
    assert.equal(data.answer, "Weight drops with fatigue.");
  } finally {
    stubAnswer = "stub answer";
  }
});

test("inline valid ACTION on the same line is parsed and stripped", async () => {
  stubAnswer = 'Swap it. ACTION {"type":"earlyDeload"}';
  try {
    const res = await post({ question: "swap my bench press", context: "" }, "test");
    const data = await res.json();
    assert.equal(data.answer, "Swap it.");
    assert.deepEqual(data.action, { type: "earlyDeload" });
  } finally {
    stubAnswer = "stub answer";
  }
});

test("answer without an ACTION line returns action null", async () => {
  const res = await post({ question: "how many sets for chest", context: "" }, "test");
  const data = await res.json();
  assert.equal(data.action, null);
  assert.equal(data.answer, "stub answer");
});

test("assignVariant is deterministic fnv1a parity", () => {
  assert.equal(fnv1a("device-a"), 2575431553);
  assert.equal(assignVariant("device-a"), "B"); // odd hash
  assert.equal(assignVariant("device-b"), "A"); // even hash
  assert.equal(assignVariant("device-a"), assignVariant("device-a"));
});

test("/config returns the paywall copy for the device's variant", async () => {
  const res = await app(new Request("http://x/config?device=device-a", { headers: { "x-forge-secret": "test" } }));
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), {
    paywall: {
      variant: "B",
      headline: "Your programming, done",
      subline: "Adaptive loads, deloads and swaps, every session.",
      annualBadge: "BEST VALUE",
    },
  });
  const resB = await app(new Request("http://x/config?device=device-b", { headers: { "x-forge-secret": "test" } }));
  assert.equal((await resB.json()).paywall.variant, "A");
});

test("/config requires the secret and a device", async () => {
  assert.equal((await app(new Request("http://x/config?device=x"))).status, 401);
  const res = await app(new Request("http://x/config", { headers: { "x-forge-secret": "test" } }));
  assert.equal(res.status, 400);
});

test("/events writes one data point per valid event", async () => {
  const points: Parameters<EventsBinding["writeDataPoint"]>[0][] = [];
  const events: EventsBinding = { writeDataPoint: (e) => points.push(e) };
  const app2 = createApp({
    chunks: [],
    complete: async () => ({ answer: "", provider: "gemini" }),
    secret: "test",
    providers: [],
    events,
  });
  const post = (body: unknown, secret = "test") =>
    app2(
      new Request("http://x/events", {
        method: "POST",
        headers: { "content-type": "application/json", "x-forge-secret": secret },
        body: JSON.stringify(body),
      }),
    );
  assert.equal(
    (
      await app2(
        new Request("http://x/events", {
          method: "POST",
          headers: { "content-type": "application/json" },
          body: JSON.stringify({ device: "d", events: [{ name: "x" }] }),
        }),
      )
    ).status,
    401,
  );
  const res = await post({
    device: "device-a",
    events: [
      { name: "coach_question", ts: 123.5, props: { q: "swap" } },
      { name: "BadName", ts: 1 },
      { ts: 2 },
    ],
  });
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true, accepted: 1 });
  assert.deepEqual(points, [
    { blobs: ["coach_question", "device-a", '{"q":"swap"}'], doubles: [123.5], indexes: ["coach_question"] },
  ]);
});

test("/events rejects oversized batches and missing device", async () => {
  const app2 = createApp({ chunks: [], complete: async () => ({ answer: "", provider: "gemini" }), secret: "test", providers: [] });
  const post = (body: unknown) =>
    app2(
      new Request("http://x/events", {
        method: "POST",
        headers: { "content-type": "application/json", "x-forge-secret": "test" },
        body: JSON.stringify(body),
      }),
    );
  assert.equal((await post({ events: [] })).status, 400);
  assert.equal((await post({ device: "d", events: Array.from({ length: 51 }, () => ({ name: "x", ts: 1 })) })).status, 400);
});

test("/feedback stores text as a feedback data point; text is capped at 2000", async () => {
  const points: Parameters<EventsBinding["writeDataPoint"]>[0][] = [];
  const app2 = createApp({
    chunks: [],
    complete: async () => ({ answer: "", provider: "gemini" }),
    secret: "test",
    providers: [],
    events: { writeDataPoint: (e) => points.push(e) },
  });
  const post = (body: unknown) =>
    app2(
      new Request("http://x/feedback", {
        method: "POST",
        headers: { "content-type": "application/json", "x-forge-secret": "test" },
        body: JSON.stringify(body),
      }),
    );
  const res = await post({ device: "device-a", text: "love the app", screen: "paywall" });
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true });
  assert.deepEqual(points, [{ blobs: ["feedback", "device-a", "love the app"], indexes: ["feedback"] }]);
  assert.equal((await post({ device: "device-a", text: "x".repeat(2001) })).status, 400);
});

test("/waitlist: valid email returns a stable 8-hex share code; invalid → 400; CORS + preflight", async () => {
  const res = await app(
    new Request("http://x/waitlist", {
      method: "POST",
      headers: { "content-type": "application/json", "origin": "https://regulift.app" },
      body: JSON.stringify({ email: "Lifter@Example.com", ref: "abc12345" }),
    }),
  );
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("access-control-allow-origin"), "*");
  const data = await res.json();
  assert.match(data.code, /^[0-9a-f]{8}$/);
  const again = await app(
    new Request("http://x/waitlist", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "lifter@example.com" }),
    }),
  );
  assert.equal((await again.json()).code, data.code); // same email → same code
  const bad = await app(
    new Request("http://x/waitlist", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ email: "not-an-email" }),
    }),
  );
  assert.equal(bad.status, 400);
  const preflight = await app(new Request("http://x/waitlist", { method: "OPTIONS" }));
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers.get("access-control-allow-origin"), "*");
});

test("/r/<code> redirects to the landing page with the ref", async () => {
  const res = await app(new Request("http://x/r/abc12345"));
  assert.equal(res.status, 302);
  assert.equal(res.headers.get("location"), "https://regulift.app/?ref=abc12345");
});

test("/coach passes tier through to complete (chat default, quick honored)", async () => {
  const tiers: (string | undefined)[] = [];
  const app2 = createApp({
    chunks: [],
    complete: async (_system, _messages, tier) => {
      tiers.push(tier);
      return { answer: "ok", provider: "gemini" };
    },
    secret: "test",
    providers: [],
  });
  const post2 = (body: unknown) =>
    app2(
      new Request("http://x/coach", {
        method: "POST",
        headers: { "content-type": "application/json", "x-forge-secret": "test" },
        body: JSON.stringify(body),
      }),
    );
  await post2({ question: "hi", context: "" });
  await post2({ question: "hi", context: "", tier: "quick" });
  await post2({ question: "hi", context: "", tier: "chat" });
  assert.deepEqual(tiers, ["chat", "quick", "chat"]);
});
