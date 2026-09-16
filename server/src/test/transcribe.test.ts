import test from "node:test";
import assert from "node:assert/strict";
import { createApp, type TranscribeFn } from "../app.js";

function transcribeApp(transcribe?: TranscribeFn): ReturnType<typeof createApp> {
  return createApp({
    chunks: [],
    complete: async () => ({ answer: "stub", provider: "gemini" }),
    secret: "test",
    providers: [],
    transcribe,
  });
}

function post(
  app: ReturnType<typeof createApp>,
  url: string,
  headers: Record<string, string>,
  body: BodyInit,
): Promise<Response> {
  return app(new Request(`http://x${url}`, { method: "POST", headers, body }));
}

test("transcribe rejects without the app secret", async () => {
  const app = transcribeApp(async () => ({ text: "hi" }));
  const res = await post(app, "/transcribe", { "content-type": "audio/wav" }, new Uint8Array([1, 2, 3]));
  assert.equal(res.status, 401);
  assert.deepEqual(await res.json(), { error: "unauthorized" });
});

test("transcribe rejects an empty body", async () => {
  const app = transcribeApp(async () => ({ text: "hi" }));
  const res = await post(
    app,
    "/transcribe",
    { "content-type": "audio/mp4", "x-forge-secret": "test" },
    new Uint8Array(0),
  );
  assert.equal(res.status, 400);
  assert.deepEqual(await res.json(), { error: "audio required" });
});

test("transcribe passes language and prompt through and returns the text", async () => {
  let captured: { bytes: Uint8Array; language?: string; prompt?: string } | undefined;
  const app = transcribeApp(async (bytes, language, prompt) => {
    captured = { bytes, language, prompt };
    return { text: "one hundred kilos", language: "en" };
  });
  const body = new TextEncoder().encode("fake audio bytes");
  const res = await post(
    app,
    "/transcribe?language=vi&prompt=deadlift%2CRPE",
    { "content-type": "audio/mp4", "x-forge-secret": "test" },
    body,
  );
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { text: "one hundred kilos", language: "en" });
  assert.ok(captured);
  assert.equal(captured!.language, "vi");
  assert.equal(captured!.prompt, "deadlift,RPE");
  assert.deepEqual([...captured!.bytes], [...body]);
});

test("transcribe returns 502 with an error when the transcriber throws", async () => {
  const app = transcribeApp(async () => {
    throw new Error("whisper: model down");
  });
  const res = await post(
    app,
    "/transcribe",
    { "content-type": "audio/wav", "x-forge-secret": "test" },
    new Uint8Array([1]),
  );
  assert.equal(res.status, 502);
  assert.deepEqual(await res.json(), { error: "whisper: model down" });
});
