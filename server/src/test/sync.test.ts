import test from "node:test";
import assert from "node:assert/strict";
import { apiApp, call, login } from "./helpers.js";

const T1 = "2025-06-01T10:00:00Z";
const T2 = "2025-06-02T10:00:00Z";

function ch(over: Record<string, unknown> = {}) {
  return { type: "session", id: "s1", updatedAt: T1, data: { note: "first" }, ...over };
}

test("push two records, pull from cursor 0 returns both", async () => {
  const { app } = apiApp();
  const { token } = await login(app);
  const push = await call(app, "POST", "/sync", {
    token,
    body: { cursor: 0, changes: [ch({ id: "s1" }), ch({ id: "s2" })] },
  });
  assert.equal(push.status, 200);
  const pushed = await push.json() as { cursor: number; changes: unknown[] };
  assert.equal(pushed.cursor, 2);
  assert.deepEqual(pushed.changes, []); // own accepted changes are echoed out
  const pull = await call(app, "POST", "/sync", { token, body: { cursor: 0, changes: [] } });
  const pulled = await pull.json() as { cursor: number; changes: { id: string; data: { note: string } }[] };
  assert.equal(pulled.cursor, 2);
  assert.deepEqual(pulled.changes.map((c) => c.id).sort(), ["s1", "s2"]);
  assert.equal(pulled.changes[0].data.note, "first");
});

test("older updatedAt does not overwrite; the server's newer row comes back", async () => {
  const { app } = apiApp();
  const { token } = await login(app);
  await call(app, "POST", "/sync", { token, body: { cursor: 0, changes: [ch({ updatedAt: T2, data: { note: "newer" } })] } });
  const older = await call(app, "POST", "/sync", {
    token,
    body: { cursor: 0, changes: [ch({ updatedAt: T1, data: { note: "older" } })] },
  });
  assert.equal(older.status, 200);
  const data = await older.json() as { cursor: number; changes: { id: string; data: { note: string } }[] };
  assert.equal(data.cursor, 1); // nothing accepted, seq unchanged
  assert.equal(data.changes.length, 1); // rejected id: device learns the server version
  assert.equal(data.changes[0].data.note, "newer");
});

test("deleted flag propagates", async () => {
  const { app } = apiApp();
  const { token } = await login(app);
  await call(app, "POST", "/sync", { token, body: { cursor: 0, changes: [ch()] } });
  await call(app, "POST", "/sync", { token, body: { cursor: 1, changes: [ch({ updatedAt: T2, deleted: true })] } });
  const pull = await call(app, "POST", "/sync", { token, body: { cursor: 0, changes: [] } });
  const { changes } = await pull.json() as { changes: { id: string; deleted: boolean }[] };
  assert.equal(changes[0].id, "s1");
  assert.equal(changes[0].deleted, true);
});

test("push an exercise change, pull from a fresh cursor returns it", async () => {
  const { app } = apiApp();
  const { token } = await login(app);
  const push = await call(app, "POST", "/sync", {
    token,
    body: { cursor: 0, changes: [ch({ type: "exercise", id: "e1", data: { name: "Cable Y-Raise", primary: "sideDelts" } })] },
  });
  assert.equal(push.status, 200);
  const pull = await call(app, "POST", "/sync", { token, body: { cursor: 0, changes: [] } });
  const { changes } = await pull.json() as { changes: { type: string; id: string; data: { name: string } }[] };
  assert.equal(changes.length, 1);
  assert.equal(changes[0].type, "exercise");
  assert.equal(changes[0].data.name, "Cable Y-Raise");
});

test("501 changes return 400", async () => {
  const { app } = apiApp();
  const { token } = await login(app);
  const changes = Array.from({ length: 501 }, (_, i) => ch({ id: `s${i}` }));
  const res = await call(app, "POST", "/sync", { token, body: { cursor: 0, changes } });
  assert.equal(res.status, 400);
  assert.match(((await res.json()) as { error: string }).error, /too many changes/);
});

test("invalid changes return 400: bad type, long id, big data, bad updatedAt, non-object data", async () => {
  const { app } = apiApp();
  const { token } = await login(app);
  const bad = [
    ch({ type: "virus" }),
    ch({ id: "x".repeat(65) }),
    ch({ data: { blob: "y".repeat(65 * 1024) } }),
    ch({ updatedAt: "yesterday" }),
    ch({ data: [1, 2] }),
  ];
  for (const change of bad) {
    const res = await call(app, "POST", "/sync", { token, body: { cursor: 0, changes: [change] } });
    assert.equal(res.status, 400, JSON.stringify(change).slice(0, 60));
  }
  assert.equal((await call(app, "POST", "/sync", { token, body: { changes: [] } })).status, 400); // cursor required
});

test("sync requires a Bearer session", async () => {
  const { app } = apiApp();
  await login(app);
  assert.equal((await call(app, "POST", "/sync", { body: { cursor: 0, changes: [] } })).status, 401);
});
