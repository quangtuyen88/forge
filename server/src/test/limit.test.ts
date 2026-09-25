import test from "node:test";
import assert from "node:assert/strict";
import { createApp } from "../app.js";

function makeApp(limiter?: (key: string) => Promise<boolean>) {
  const calls: string[] = [];
  const app = createApp({
    chunks: [],
    complete: async () => {
      calls.push("called");
      return { answer: "stub", provider: "gemini" };
    },
    secret: "test",
    providers: ["gemini"],
    limiter,
  });
  return { app, calls };
}

function post(app: ReturnType<typeof createApp>) {
  return app(
    new Request("http://x/coach", {
      method: "POST",
      headers: { "content-type": "application/json", "x-forge-secret": "test", "cf-connecting-ip": "1.2.3.4" },
      body: JSON.stringify({ question: "how many sets for chest" }),
    }),
  );
}

test("limiter returning false yields 429 and provider is never called", async () => {
  const keys: string[] = [];
  const { app, calls } = makeApp(async (key) => {
    keys.push(key);
    return false;
  });
  const res = await post(app);
  assert.equal(res.status, 429);
  assert.deepEqual(await res.json(), { error: "Too many questions. Try again in a minute." });
  assert.deepEqual(keys, ["1.2.3.4"]);
  assert.equal(calls.length, 0);
});

test("limiter returning true proceeds", async () => {
  const { app, calls } = makeApp(async () => true);
  const res = await post(app);
  assert.equal(res.status, 200);
  assert.equal(calls.length, 1);
});
