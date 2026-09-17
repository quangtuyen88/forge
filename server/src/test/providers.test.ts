import test from "node:test";
import assert from "node:assert/strict";
import { completeWithFallback, providerChain, type AiBinding } from "../providers.js";

const fakeAI: AiBinding = { run: async () => ({ response: "ai answer" }) };

test("providerChain: chat tier is anthropic → gemini → workers-ai", () => {
  assert.deepEqual(providerChain({ GEMINI_API_KEY: "g", ANTHROPIC_API_KEY: "a" }), ["claude", "gemini"]);
  assert.deepEqual(providerChain({ AI: fakeAI, GEMINI_API_KEY: "g", ANTHROPIC_API_KEY: "a" }), [
    "claude",
    "gemini",
    "workers-ai",
  ]);
  // unusable providers dropped
  assert.deepEqual(providerChain({ AI: fakeAI, GEMINI_API_KEY: "g" }), ["gemini", "workers-ai"]);
  assert.deepEqual(providerChain({}), []);
});

test("providerChain: quick tier puts workers-ai first", () => {
  const env = { AI: fakeAI, GEMINI_API_KEY: "g", ANTHROPIC_API_KEY: "a" };
  assert.deepEqual(providerChain(env, "quick"), ["workers-ai", "claude", "gemini"]);
  assert.deepEqual(providerChain({ GEMINI_API_KEY: "g" }, "quick"), ["gemini"]);
  assert.deepEqual(providerChain({ AI: fakeAI }, "quick"), ["workers-ai"]);
});

test("completeWithFallback falls through a throwing provider to the AI binding", async () => {
  const realFetch = globalThis.fetch;
  globalThis.fetch = (async () => {
    throw new Error("network down");
  }) as typeof fetch;
  try {
    const result = await completeWithFallback(
      ["gemini", "workers-ai"],
      "sys",
      [{ role: "user", content: "q" }],
      { GEMINI_API_KEY: "g", AI: fakeAI },
    );
    assert.deepEqual(result, { answer: "ai answer", provider: "workers-ai" });
  } finally {
    globalThis.fetch = realFetch;
  }
});

test("empty chain (or all failing) throws the no-provider error", async () => {
  await assert.rejects(
    completeWithFallback([], "sys", [], {}),
    /no provider available: configure the AI binding, GEMINI_API_KEY or ANTHROPIC_API_KEY/,
  );
  const realFetch = globalThis.fetch;
  globalThis.fetch = (async () => {
    throw new Error("boom");
  }) as typeof fetch;
  try {
    await assert.rejects(
      completeWithFallback(["gemini"], "sys", [], { GEMINI_API_KEY: "g" }),
      /no provider available: boom/,
    );
  } finally {
    globalThis.fetch = realFetch;
  }
});
