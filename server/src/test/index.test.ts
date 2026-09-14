import { after, test } from "node:test";
import assert from "node:assert/strict";

process.env.APP_SECRET = "test";
process.env.PROVIDER = "claude";

const { server, setProvider } = await import("../index.js");

const calls: { system: string; messages: { role: string; content: string }[] }[] = [];
setProvider(async (_p, system, messages) => {
  calls.push({ system, messages });
  return "stub answer";
});

await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
const base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;

function post(body: unknown, secret?: string) {
  return fetch(`${base}/coach`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(secret ? { "x-forge-secret": secret } : {}),
    },
    body: JSON.stringify(body),
  });
}

test("POST without secret returns 401 and never calls the provider", async () => {
  const res = await post({ question: "how many sets for chest", context: "" });
  assert.equal(res.status, 401);
  assert.equal(calls.length, 0);
});

test("medical question is refused without calling the provider", async () => {
  const res = await post({ question: "my shoulder hurts when I bench", context: "" }, "test");
  assert.equal(res.status, 200);
  const data = await res.json();
  assert.equal(data.refused, true);
  assert.deepEqual(data.citations, []);
  assert.equal(calls.length, 0);
});

test("training question retrieves chunks, calls the stub, returns its answer", async () => {
  const res = await post(
    {
      question: "how many sets for chest",
      context: "goal: hypertrophy, 4 days/week",
      history: [{ role: "user", content: "hi" }, { role: "assistant", content: "hello" }],
    },
    "test",
  );
  assert.equal(res.status, 200);
  const data = await res.json();
  assert.equal(data.answer, "stub answer");
  assert.equal(data.refused, false);
  assert.ok(data.citations.includes("Volume landmarks: chest"));

  assert.equal(calls.length, 1);
  assert.ok(calls[0].system.includes("[Volume landmarks: chest]"));
  assert.ok(calls[0].system.includes("goal: hypertrophy, 4 days/week"));
  const last = calls[0].messages.at(-1)!;
  assert.equal(last.role, "user");
  assert.equal(last.content, "how many sets for chest");
});

after(() => server.close());
