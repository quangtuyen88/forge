import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";
import { d1Queries } from "../queries.js";
import type { D1Database, D1PreparedStatement } from "../db.js";

/** node:sqlite adapter with the D1 statement shape, running every real migration in order. */
function sqliteD1(): D1Database {
  const db = new DatabaseSync(":memory:");
  const dir = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "migrations");
  for (const file of readdirSync(dir).filter((f) => f.endsWith(".sql")).sort()) {
    db.exec(readFileSync(join(dir, file), "utf8"));
  }
  return {
    prepare(text: string): D1PreparedStatement {
      const stmt = db.prepare(text);
      let params: unknown[] = [];
      const bound: D1PreparedStatement = {
        bind: (...p: unknown[]) => {
          params = p;
          return bound;
        },
        first: async <T = unknown>() => (stmt.get(...(params as Parameters<typeof stmt.get>)) as T | null) ?? null,
        all: async <T = unknown>() => ({ results: stmt.all(...(params as Parameters<typeof stmt.all>)) as T[] }),
        run: async () => ({ meta: { changes: Number(stmt.run(...(params as Parameters<typeof stmt.run>)).changes) } }),
      };
      return bound;
    },
  };
}

test("d1 applyChange bumps seq on update and keeps inserts monotonic (real SQLite)", async () => {
  const q = d1Queries(sqliteD1());
  const u = await q.upsertUserByAppleSub("sub-1", "a@b.co", new Date().toISOString());
  assert.equal(await q.applyChange(u.id, "session", "a", "2025-01-01T00:00:00Z", false, '{"v":1}'), true); // seq 1
  assert.equal(await q.applyChange(u.id, "session", "a", "2025-02-01T00:00:00Z", false, '{"v":2}'), true); // bump → seq 2
  const afterA = await q.maxSeq(u.id);
  assert.equal(afterA, 2);
  assert.equal(await q.applyChange(u.id, "session", "a", "2025-01-15T00:00:00Z", false, '{"v":0}'), false); // older → rejected
  assert.equal(await q.applyChange(u.id, "session", "a", "2025-02-01T00:00:00Z", false, '{"tie":1}'), false); // equal → rejected
  assert.equal(await q.applyChange(u.id, "session", "b", "2025-01-01T00:00:00Z", false, '{"v":1}'), true); // new id after bumps
  const rows = await q.recordsSince(u.id, afterA);
  assert.equal(rows.length, 1);
  assert.equal(rows[0].id, "b");
  assert.ok(rows[0].seq > afterA, `new insert seq ${rows[0].seq} must exceed the updated row's ${afterA}`);
  const a = (await q.recordsSince(u.id, 0)).find((r) => r.id === "a")!;
  assert.equal(a.seq, 2);
  assert.equal(JSON.parse(a.data).v, 2);
});

test("d1 social queries: feed enrich, idempotent follows/kudos, comment order (real SQLite)", async () => {
  const q = d1Queries(sqliteD1());
  const u1 = await q.upsertUserByAppleSub("s1", null, new Date().toISOString());
  const u2 = await q.upsertUserByAppleSub("s2", null, new Date().toISOString());
  await q.upsertProfile(u1.id, "feedone", "One", "", "2025-06-01T00:00:00Z");
  await q.insertFollow(u1.id, u2.id, "2025-06-01T00:00:00Z");
  await q.insertFollow(u1.id, u2.id, "2025-06-01T00:00:00Z"); // idempotent
  assert.deepEqual(await q.followedIds(u1.id), [u2.id]);
  assert.equal(await q.isFollowing(u1.id, u2.id), true);
  await q.insertPost("p1", u1.id, "session", '{"n":1}', "2025-06-01T10:00:00Z");
  await q.insertPost("p2", u2.id, "pr", '{"e1rm":100}', "2025-06-02T10:00:00Z");
  await q.addKudos("p2", u1.id, "2025-06-02T11:00:00Z");
  await q.addKudos("p2", u1.id, "2025-06-02T11:00:00Z"); // idempotent
  await q.insertComment("c1", "p2", u1.id, "first", "2025-06-02T12:00:00Z");
  await q.insertComment("c2", "p2", u1.id, "second", "2025-06-02T12:00:00Z"); // same ts → rowid order

  const rows = await q.feedPosts([u1.id, u2.id], null, 31, u1.id);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].id, "p2"); // newest first
  assert.equal(rows[0].handle, null); // u2 has no profile
  assert.equal(rows[1].handle, "feedone");
  assert.equal(rows[0].kudos, 1); // idempotent kudos counted once
  assert.equal(rows[0].kudoed, 1); // viewer gave the kudos
  assert.equal(rows[0].comments, 2);
  const paged = await q.feedPosts([u1.id, u2.id], rows[0].created_at, 31, u1.id);
  assert.deepEqual(paged.map((r) => r.id), ["p1"]); // cursor excludes the newer post

  const comments = await q.commentsForPost("p2", 100);
  assert.deepEqual(comments.map((c) => c.text), ["first", "second"]); // rowid tiebreak

  const week = await q.postsForWeek([u1.id, u2.id], "2025-06-01T00:00:00Z", "2025-06-08T00:00:00Z");
  assert.deepEqual(week.map((p) => p.id), ["p1"]); // session posts only — pr posts excluded (leaderboard semantics)
  await q.deleteUser(u1.id);
  assert.equal(await q.getProfileByHandle("feedone"), null);
  assert.deepEqual((await q.feedPosts([u2.id], null, 31, u2.id)).map((r) => r.id), ["p2"]);
});

test("d1 users and coach usage round-trip on the real schema", async () => {
  const q = d1Queries(sqliteD1());
  const u = await q.upsertUserByAppleSub("sub-1", "a@b.co", new Date().toISOString());
  const same = await q.upsertUserByAppleSub("sub-1", "new@b.co", new Date().toISOString());
  assert.equal(same.id, u.id);
  assert.equal(same.email, "new@b.co");
  assert.equal(await q.getCoachUsage(u.id, "2025-06-15"), 0);
  await q.incrementCoachUsage(u.id, "2025-06-15");
  await q.incrementCoachUsage(u.id, "2025-06-15");
  assert.equal(await q.getCoachUsage(u.id, "2025-06-15"), 2);
  assert.equal(await q.getCoachUsage(u.id, "2025-06-16"), 0);
  await q.deleteUser(u.id);
  assert.equal(await q.getUserById(u.id), null);
  assert.equal(await q.getCoachUsage(u.id, "2025-06-15"), 0);
});
