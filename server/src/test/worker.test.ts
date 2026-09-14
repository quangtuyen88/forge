import test from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../app.js";
import { loadKnowledgeFromStrings } from "../rag.js";
import { KNOWLEDGE } from "../knowledge.generated.js";

const chunks = loadKnowledgeFromStrings(KNOWLEDGE);
const calls: { system: string; last: string }[] = [];
const app = createApp({
  chunks,
  complete: async (system, messages) => {
    calls.push({ system, last: messages.at(-1)!.content });
    return { answer: "stub answer", provider: "gemini" };
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

test("training question returns stub answer with citation heading and provider", async () => {
  const res = await post({ question: "how many sets for chest", context: "" }, "test");
  assert.equal(res.status, 200);
  const data = await res.json();
  assert.equal(data.answer, "stub answer");
  assert.equal(data.refused, false);
  assert.equal(data.provider, "gemini");
  assert.ok(data.citations.includes("Volume landmarks: chest"));
  assert.ok(calls.at(-1)!.system.includes("[Volume landmarks: chest]"));
  assert.equal(calls.at(-1)!.last, "how many sets for chest");
});

test("coach field selects the persona; only Nova and Kai accepted", async () => {
  await post({ question: "how many sets for chest", coach: "Kai" }, "test");
  assert.ok(calls.at(-1)!.system.includes("You are Kai, a strength coach inside the Forge app."));
  assert.ok(calls.at(-1)!.system.includes("Tone: warm, high energy, direct, still concise."));

  await post({ question: "how many sets for back", coach: "  Nova  " }, "test");
  assert.ok(calls.at(-1)!.system.includes("You are Nova, a strength coach inside the Forge app."));

  await post({ question: "how many sets for quads", coach: "Arnold" }, "test");
  assert.ok(calls.at(-1)!.system.includes("You are Nova, a strength coach inside the Forge app."));
});

test("/health returns the health shape", async () => {
  const res = await app(new Request("http://x/health"));
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), {
    ok: true,
    providers: ["gemini", "claude"],
    chunks: chunks.length,
  });
});
