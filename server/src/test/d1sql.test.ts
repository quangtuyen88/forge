import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { DatabaseSync } from "node:sqlite";
import { d1Queries, memoryQueries } from "../queries.js";
import type { Queries } from "../queries.js";
import type { D1Database, D1PreparedStatement } from "../db.js";
import { apiApp, login } from "./helpers.js";

/** node:sqlite adapter with the D1 statement shape, running every real migration in order.
 * Enforces D1's real per-statement limit of 100 bound parameters. */
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
          if (p.length > 100) throw new Error(`too many bound parameters: ${p.length} (D1 limit is 100)`);
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

test("d1 crew queries: crewSessionPosts/crewPrPosts/firstSessionDates match memoryQueries (real SQLite)", async () => {
  const now = "2026-09-24T12:00:00Z";
  const since = "2026-03-23T00:00:00Z"; // W39 Monday − 26 weeks
  const seed = async (q: Queries) => {
    const u1 = await q.upsertUserByAppleSub("crew-1", null, now);
    const u2 = await q.upsertUserByAppleSub("crew-2", null, now);
    const u3 = await q.upsertUserByAppleSub("crew-3", null, now);
    const u4 = await q.upsertUserByAppleSub("crew-4", null, now); // not an author
    await q.insertPost("k0", u1.id, "session", '{"n":0}', "2026-02-01T10:00:00Z"); // u1's first session ever — outside the 26-week window
    await q.insertPost("k1", u1.id, "session", '{"n":1}', "2026-09-20T10:00:00Z");
    await q.insertPost("k2", u2.id, "pr", '{"e1rm":100}', "2026-09-22T10:00:00Z");
    await q.insertPost("k3", u3.id, "session", '{"n":3}', "2026-09-23T10:00:00Z");
    await q.insertPost("k4", u4.id, "session", '{"n":4}', "2026-09-24T10:00:00Z"); // not an author
    await q.insertPost("k5", u2.id, "pr", '{"e1rm":90}', "2026-09-29T10:00:00Z"); // at the week's to-bound
    await q.addKudos("k2", u1.id, now);
    await q.addKudos("k2", u3.id, now);
    await q.addKudos("k3", u1.id, now);
    await q.addKudos("k3", u4.id, now); // kudos from a non-author still counts
    return { u1, u2, u3 };
  };
  const d1q = d1Queries(sqliteD1());
  const memq = memoryQueries();
  const d = await seed(d1q);
  const m = await seed(memq);
  const dAuthors = [d.u1.id, d.u2.id, d.u3.id];
  const mAuthors = [m.u1.id, m.u2.id, m.u3.id];

  // session posts: type-filtered, author-scoped, since-cutoff honored (k0 too old, k2/k5 pr, k4 not an author)
  assert.deepEqual((await d1q.crewSessionPosts(dAuthors, since)).map((r) => r.id).sort(), ["k1", "k3"]);
  assert.deepEqual((await memq.crewSessionPosts(mAuthors, since)).map((r) => r.id).sort(), ["k1", "k3"]);

  // pr posts: [from, to) window around the week (k5 at the to-bound excluded)
  assert.deepEqual((await d1q.crewPrPosts(dAuthors, "2026-09-20T00:00:00Z", "2026-09-29T00:00:00Z")).map((r) => r.id), ["k2"]);
  assert.deepEqual((await memq.crewPrPosts(mAuthors, "2026-09-20T00:00:00Z", "2026-09-29T00:00:00Z")).map((r) => r.id), ["k2"]);
  assert.deepEqual(await d1q.crewPrPosts(dAuthors, "2026-09-23T00:00:00Z", "2026-09-29T00:00:00Z"), []);
  assert.deepEqual(await memq.crewPrPosts(mAuthors, "2026-09-23T00:00:00Z", "2026-09-29T00:00:00Z"), []);

  // first session dates: MIN(created_at) over ALL session posts, not just the loaded window
  const idxOf = (u: { u1: { id: string }; u2: { id: string }; u3: { id: string } }, id: string) =>
    id === u.u1.id ? 1 : id === u.u2.id ? 2 : 3;
  const normFirst = (rows: { user_id: string; first: string }[], u: { u1: { id: string }; u2: { id: string }; u3: { id: string } }) =>
    rows.map((r) => ({ who: idxOf(u, r.user_id), first: r.first })).sort((a, b) => a.who - b.who);
  assert.deepEqual(normFirst(await d1q.firstSessionDates(dAuthors), d), [
    { who: 1, first: "2026-02-01T10:00:00Z" },
    { who: 3, first: "2026-09-23T10:00:00Z" },
  ]);
  assert.deepEqual(normFirst(await memq.firstSessionDates(mAuthors), m), [
    { who: 1, first: "2026-02-01T10:00:00Z" },
    { who: 3, first: "2026-09-23T10:00:00Z" },
  ]);
  assert.deepEqual(await d1q.firstSessionDates([]), []);
  assert.deepEqual(await memq.firstSessionDates([]), []);

  const normKudos = (rows: { post_id: string; kudos: number; kudoed: number }[]) =>
    rows.map((r) => ({ ...r })).sort((a, b) => (a.post_id < b.post_id ? -1 : 1));
  for (const [dv, mv] of [[d.u2, m.u2], [d.u1, m.u1]] as const) {
    assert.deepEqual(
      normKudos(await d1q.kudosFor(["k2", "k3", "nope"], dv.id)),
      normKudos(await memq.kudosFor(["k2", "k3", "nope"], mv.id)),
    );
  }
  const byId = (rows: { post_id: string; kudos: number; kudoed: number }[]) =>
    Object.fromEntries(rows.map((r) => [r.post_id, { ...r }])); // spread: node:sqlite rows are null-prototype
  const seen = byId(await d1q.kudosFor(["k2", "k3"], d.u1.id));
  assert.deepEqual(seen["k2"], { post_id: "k2", kudos: 2, kudoed: 1 }); // viewer u1 kudoed k2
  assert.deepEqual(seen["k3"], { post_id: "k3", kudos: 2, kudoed: 1 });
  const notViewer = byId(await d1q.kudosFor(["k2", "k3"], d.u2.id));
  assert.deepEqual(notViewer["k2"], { post_id: "k2", kudos: 2, kudoed: 0 }); // u2 gave no kudos
  assert.deepEqual(await d1q.kudosFor([], d.u1.id), []);
  assert.deepEqual(await memq.kudosFor([], m.u1.id), []);
});

test("d1 kudosFor chunks under the 100 bound-parameter limit; /social/crew survives 150 week pr posts", async () => {
  const q = d1Queries(sqliteD1()); // the adapter throws above 100 bound parameters
  const now = "2026-09-24T12:00:00Z"; // Thursday of ISO week 2026-W39
  const app = apiApp({ queries: q, now: () => new Date(now) }).app;
  const me = await login(app, "limit-me");
  const other = await q.upsertUserByAppleSub("limit-other", null, now);
  await q.insertFollow(me.user.id, other.id, now);

  const ids: string[] = [];
  let at = Date.UTC(2026, 8, 21, 6); // Monday of W39; distinct created_at per post
  for (let i = 0; i < 150; i++) {
    const id = `pr${String(i).padStart(3, "0")}`;
    await q.insertPost(
      id, other.id, "pr",
      JSON.stringify({ exercise: "Deadlift", exerciseId: "deadlift", e1rm: 200 + i, localDate: "2026-09-21" }),
      new Date(at).toISOString(),
    );
    if (i % 3 === 0) await q.addKudos(id, me.user.id, now);
    ids.push(id);
    at += 60_000;
  }

  // 250 ids (150 real + 100 filler) in one call: must chunk to at most 90 ids per statement
  const rows = await q.kudosFor([...ids, ...Array.from({ length: 100 }, (_, i) => `filler${i}`)], me.user.id);
  assert.equal(rows.length, 50); // only the kudoed posts come back
  const byId = new Map(rows.map((r) => [r.post_id, { ...r }])); // spread: node:sqlite rows are null-prototype
  for (let i = 0; i < 150; i++) {
    const id = `pr${String(i).padStart(3, "0")}`;
    if (i % 3 === 0) assert.deepEqual(byId.get(id), { post_id: id, kudos: 1, kudoed: 1 });
    else assert.equal(byId.get(id), undefined);
  }

  // end to end: /social/crew runs kudosFor over all 150 week pr posts through the strict stub
  const res = await app(new Request("http://x/social/crew", {
    headers: { "content-type": "application/json", "x-forge-secret": "test", authorization: `Bearer ${me.token}` },
  }));
  assert.equal(res.status, 200);
  const data = await res.json() as { week: string; records: { postId: string; kudos: number; kudoed: boolean }[] };
  assert.equal(data.week, "2026-W39");
  assert.equal(data.records.length, 150);
  assert.equal(data.records[0].postId, "pr149"); // newest first
  assert.equal(data.records.filter((r) => r.kudoed).length, 50);
  assert.ok(data.records.every((r) => r.kudos === (r.kudoed ? 1 : 0)));
});
