import test from "node:test";
import assert from "node:assert/strict";
import { apiApp, call, login } from "./helpers.js";
import { isoWeekKey } from "../social.js";

const FIXED = new Date("2025-06-11T12:00:00Z"); // Wednesday, ISO week 2025-W24

function socialApp(now?: () => Date) {
  return apiApp(now ? { now } : {}).app;
}

async function withProfile(app: ReturnType<typeof socialApp>, key: string, handle: string) {
  const u = await login(app, key);
  const res = await call(app, "PUT", "/social/profile", {
    token: u.token,
    body: { handle, displayName: "Lifter", bio: "gains" },
  });
  if (res.status !== 200) throw new Error(await res.text());
  return u;
}

async function addPost(app: ReturnType<typeof socialApp>, token: string, body: unknown) {
  const res = await call(app, "POST", "/social/posts", { token, body });
  if (res.status !== 200) throw new Error(await res.text());
  return (await res.json()) as { post: { id: string } };
}

test("profile: GET 404 before creation, PUT creates, GET returns it", async () => {
  const app = socialApp();
  const u = await login(app, "p1");
  assert.equal((await call(app, "GET", "/social/profile", { token: u.token })).status, 404);
  const put = await call(app, "PUT", "/social/profile", { token: u.token, body: { handle: "Lifter_One", displayName: "Lifter", bio: "" } });
  assert.equal(put.status, 200);
  const { profile } = await put.json() as { profile: { handle: string; displayName: string } };
  assert.equal(profile.handle, "lifter_one"); // lowercased
  const get = await call(app, "GET", "/social/profile", { token: u.token });
  assert.equal((await get.json() as { profile: { handle: string } }).profile.handle, "lifter_one");
});

test("profile: duplicate handle 409, owner may keep theirs; regex and limits enforced", async () => {
  const app = socialApp();
  const a = await withProfile(app, "a", "taken_handle");
  const b = await login(app, "b");
  const clash = await call(app, "PUT", "/social/profile", { token: b.token, body: { handle: "taken_handle", displayName: "X", bio: "" } });
  assert.equal(clash.status, 409);
  assert.deepEqual(await clash.json(), { error: "Handle taken" });
  const rePut = await call(app, "PUT", "/social/profile", { token: a.token, body: { handle: "taken_handle", displayName: "New Name", bio: "" } });
  assert.equal(rePut.status, 200);
  assert.equal(((await rePut.json()) as { profile: { displayName: string } }).profile.displayName, "New Name");

  for (const [body, why] of [
    [{ handle: "ab", displayName: "X" }, "too short"],
    [{ handle: "has space", displayName: "X" }, "space"],
    [{ handle: "ok_handle", displayName: "x".repeat(41) }, "long displayName"],
    [{ handle: "ok_handle", displayName: "X", bio: "y".repeat(161) }, "long bio"],
  ] as [Record<string, string>, string][]) {
    const res = await call(app, "PUT", "/social/profile", { token: b.token, body });
    assert.equal(res.status, 400, why);
  }
});

test("follow: self 400, unknown 404, idempotent; unfollow idempotent", async () => {
  const app = socialApp();
  const a = await withProfile(app, "a", "follow_me");
  const b = await withProfile(app, "b", "follower1");
  assert.equal((await call(app, "POST", `/social/follow/${a.user.id}`, { token: a.token })).status, 400);
  assert.equal((await call(app, "POST", "/social/follow/no-such-user", { token: b.token })).status, 404);
  for (let i = 0; i < 2; i++) {
    assert.equal((await call(app, "POST", `/social/follow/${a.user.id}`, { token: b.token })).status, 200);
  }
  const view = await call(app, "GET", "/social/users/follow_me", { token: b.token });
  assert.equal(((await view.json()) as { following: boolean }).following, true);
  for (let i = 0; i < 2; i++) {
    assert.equal((await call(app, "DELETE", `/social/follow/${a.user.id}`, { token: b.token })).status, 200);
  }
  const after = await call(app, "GET", "/social/users/follow_me", { token: b.token });
  assert.equal(((await after.json()) as { following: boolean }).following, false);
});

test("users/:handle returns profile, stats and following; unknown 404", async () => {
  const app = socialApp(() => FIXED);
  const a = await withProfile(app, "a", "stats_pro");
  await addPost(app, a.token, { type: "session", payload: { tonnageKg: 120 } });
  await addPost(app, a.token, { type: "pr", payload: { exercise: "barbell_bench", e1rm: 100 } });
  await addPost(app, a.token, { type: "pr", payload: { exercise: "back_squat", e1rm: 180 } });
  const b = await withProfile(app, "b", "watcher99");
  await call(app, "POST", `/social/follow/${a.user.id}`, { token: b.token });
  const res = await call(app, "GET", "/social/users/stats_pro", { token: b.token });
  assert.equal(res.status, 200);
  const data = await res.json() as {
    profile: { handle: string };
    stats: { sessions: number; streakWeeks: number; topPRs: { exercise: string; e1rm: number }[] };
    following: boolean;
  };
  assert.equal(data.profile.handle, "stats_pro");
  assert.equal(data.stats.sessions, 1);
  assert.equal(data.stats.streakWeeks, 1);
  assert.deepEqual(data.stats.topPRs, [
    { exercise: "back_squat", e1rm: 180 },
    { exercise: "barbell_bench", e1rm: 100 },
  ]);
  assert.equal(data.following, true);
  assert.equal((await call(app, "GET", "/social/users/ghost_____", { token: b.token })).status, 404);
});

test("feed shows own + followed posts only, newest first", async () => {
  const app = socialApp();
  const a = await withProfile(app, "a", "feeda");
  const b = await withProfile(app, "b", "feedb");
  const c = await withProfile(app, "c", "feedc");
  await call(app, "POST", `/social/follow/${b.user.id}`, { token: a.token });
  const own = await addPost(app, a.token, { type: "pr", payload: { exercise: "bench", e1rm: 60 } });
  const theirs = await addPost(app, b.token, { type: "session", payload: { tonnageKg: 80 } });
  await addPost(app, c.token, { type: "session", payload: { tonnageKg: 999 } }); // not followed
  const res = await call(app, "GET", "/social/feed", { token: a.token });
  assert.equal(res.status, 200);
  const { posts, nextCursor } = await res.json() as { posts: { id: string; user: { handle: string }; kudos: number; comments: number }[]; nextCursor: string | null };
  assert.deepEqual(posts.map((p) => p.id), [theirs.post.id, own.post.id]); // newest first
  assert.equal(posts[0].user.handle, "feedb");
  assert.equal(nextCursor, null);
});

test("feed paginates 30 per page with nextCursor", async () => {
  let t = Date.UTC(2025, 5, 2, 8); // advance per insert so created_at values are distinct
  const app = socialApp(() => new Date(t));
  const a = await withProfile(app, "a", "pager11");
  const ids: string[] = [];
  for (let i = 0; i < 35; i++) {
    const { post } = await addPost(app, a.token, { type: "session", payload: { n: i } });
    ids.push(post.id);
    t += 60_000;
  }
  const page1 = await (await call(app, "GET", "/social/feed", { token: a.token })).json() as { posts: { id: string }[]; nextCursor: string };
  assert.equal(page1.posts.length, 30);
  assert.equal(page1.posts[0].id, ids[34]); // newest
  assert.ok(page1.nextCursor);
  const page2 = await (await call(app, "GET", `/social/feed?cursor=${encodeURIComponent(page1.nextCursor)}`, { token: a.token })).json() as { posts: { id: string }[]; nextCursor: string | null };
  assert.equal(page2.posts.length, 5);
  assert.equal(page2.posts[0].id, ids[4]);
  assert.equal(page2.nextCursor, null);
});

test("post validation: type and payload size", async () => {
  const app = socialApp();
  const a = await withProfile(app, "a", "poster11");
  assert.equal((await call(app, "POST", "/social/posts", { token: a.token, body: { type: "note", payload: {} } })).status, 400);
  assert.equal((await call(app, "POST", "/social/posts", { token: a.token, body: { type: "session", payload: { blob: "x".repeat(9 * 1024) } } })).status, 400);
});

test("kudos toggle is idempotent and reflected in the feed", async () => {
  const app = socialApp();
  const a = await withProfile(app, "a", "kudos_me");
  const b = await withProfile(app, "b", "kudos_g");
  const { post: p } = await addPost(app, a.token, { type: "pr", payload: { exercise: "deadlift", e1rm: 220 } });
  await call(app, "POST", `/social/follow/${a.user.id}`, { token: b.token }); // so the post lands in b's feed
  const kudos = (id: string) => call(app, "POST", `/social/posts/${id}/kudos`, { token: b.token });
  assert.equal((await kudos(p.id)).status, 200);
  assert.equal((await kudos(p.id)).status, 200); // idempotent
  let feed = await (await call(app, "GET", "/social/feed", { token: b.token })).json() as { posts: { kudos: number; kudoed: boolean }[] };
  assert.equal(feed.posts[0].kudos, 1);
  assert.equal(feed.posts[0].kudoed, true);
  assert.equal((await call(app, "DELETE", `/social/posts/${p.id}/kudos`, { token: b.token })).status, 200);
  feed = await (await call(app, "GET", "/social/feed", { token: b.token })).json() as { posts: { kudos: number; kudoed: boolean }[] };
  assert.equal(feed.posts[0].kudos, 0);
  assert.equal(feed.posts[0].kudoed, false);
  assert.equal((await kudos("no-such-post")).status, 404);
});

test("comments: create, oldest first, length limits, unknown post 404", async () => {
  const app = socialApp();
  const a = await withProfile(app, "a", "talker1");
  const b = await withProfile(app, "b", "reply_g");
  const { post: p } = await addPost(app, a.token, { type: "session", payload: {} });
  for (const text of ["first", "second", "third"]) {
    const res = await call(app, "POST", `/social/posts/${p.id}/comments`, { token: b.token, body: { text } });
    assert.equal(res.status, 200);
  }
  const list = await call(app, "GET", `/social/posts/${p.id}/comments`, { token: a.token });
  const { comments } = await list.json() as { comments: { text: string; userId: string }[] };
  assert.deepEqual(comments.map((c) => c.text), ["first", "second", "third"]);
  assert.equal(comments[0].userId, b.user.id);
  assert.equal((await call(app, "POST", `/social/posts/${p.id}/comments`, { token: b.token, body: { text: "x".repeat(501) } })).status, 400);
  assert.equal((await call(app, "POST", `/social/posts/${p.id}/comments`, { token: b.token, body: { text: "  " } })).status, 400);
  assert.equal((await call(app, "GET", "/social/posts/nope/comments", { token: a.token })).status, 404);
});

test("leaderboard aggregates the week for self + followed and sorts", async () => {
  const app = socialApp(() => FIXED);
  const a = await withProfile(app, "a", "leader_a");
  const b = await withProfile(app, "b", "leader_b");
  const c = await withProfile(app, "c", "outsider"); // not followed by a
  await call(app, "POST", `/social/follow/${b.user.id}`, { token: a.token });
  await addPost(app, a.token, { type: "session", payload: { tonnageKg: 100 } });
  await addPost(app, a.token, { type: "session", payload: { tonnageKg: 50 } });
  for (let i = 0; i < 3; i++) await addPost(app, b.token, { type: "session", payload: { tonnageKg: 10 } });
  for (let i = 0; i < 5; i++) await addPost(app, c.token, { type: "session", payload: { tonnageKg: 999 } });
  await addPost(app, a.token, { type: "pr", payload: { exercise: "bench", e1rm: 1 } }); // PRs do not count as sessions

  const res = await call(app, "GET", `/social/leaderboard?week=${isoWeekKey(FIXED)}`, { token: a.token });
  assert.equal(res.status, 200);
  const entries = await res.json() as { userId: string; handle: string | null; sessions: number; tonnageKg: number }[];
  assert.deepEqual(entries, [
    { userId: b.user.id, handle: "leader_b", sessions: 3, tonnageKg: 30 },
    { userId: a.user.id, handle: "leader_a", sessions: 2, tonnageKg: 150 },
  ]);
  const defaultWeek = await call(app, "GET", "/social/leaderboard", { token: a.token });
  assert.deepEqual(await defaultWeek.json(), entries); // default = current (fixed) week
  assert.equal((await call(app, "GET", "/social/leaderboard?week=2025-W99", { token: a.token })).status, 400);
});

test("stats streak counts consecutive ISO weeks with sessions; gaps reset it", async () => {
  // mutable clock: posts land in W22, W23, W24; view from W24 Wednesday (2025-06-11)
  let t = Date.UTC(2025, 4, 28);
  const streaky = socialApp(() => new Date(t));
  const s = await withProfile(streaky, "s", "streaky1");
  await addPost(streaky, s.token, { type: "session", payload: {} });
  t = Date.UTC(2025, 5, 4); // W23
  await addPost(streaky, s.token, { type: "session", payload: {} });
  t = Date.UTC(2025, 5, 11); // W24 (final view time)
  await addPost(streaky, s.token, { type: "session", payload: {} });
  const stats = await (await call(streaky, "GET", "/social/users/streaky1", { token: s.token })).json() as { stats: { streakWeeks: number; sessions: number } };
  assert.equal(stats.stats.streakWeeks, 3);
  assert.equal(stats.stats.sessions, 3);

  // gap (W24 + W22, no W23) → streak 1
  let g = Date.UTC(2025, 4, 28);
  const gappy = socialApp(() => new Date(g));
  const gp = await withProfile(gappy, "g", "gappy_1");
  await addPost(gappy, gp.token, { type: "session", payload: {} });
  g = Date.UTC(2025, 5, 11);
  await addPost(gappy, gp.token, { type: "session", payload: {} });
  const gap = await (await call(gappy, "GET", "/social/users/gappy_1", { token: gp.token })).json() as { stats: { streakWeeks: number } };
  assert.equal(gap.stats.streakWeeks, 1);
});

test("social routes require a Bearer session", async () => {
  const app = socialApp();
  await withProfile(app, "a", "authcheck");
  assert.equal((await call(app, "GET", "/social/profile")).status, 401);
  assert.equal((await call(app, "GET", "/social/feed")).status, 401);
  assert.equal((await call(app, "POST", "/social/posts", { body: { type: "pr", payload: {} } })).status, 401);
  assert.equal((await call(app, "GET", "/social/leaderboard")).status, 401);
});

// ---------- crew (GET /social/crew) ----------

const CREW_NOW = new Date("2026-09-24T12:00:00Z"); // Thursday of ISO week 2026-W39 (Mon 09-21 .. Sun 09-27)

interface CrewBody {
  week: string;
  weekStart: string;
  members: { userId: string; handle: string | null; displayName: string | null; isSelf: boolean; target: number; days: string[]; sessions: number }[];
  streakWeeks: number;
  records: {
    postId: string; userId: string; handle: string | null; displayName: string | null; isSelf: boolean;
    exerciseId: string | null; exercise: string; e1rm: number; weightKg: number | null; reps: number | null;
    date: string; kudos: number; kudoed: boolean;
  }[];
  lifts: Record<string, { userId: string; deltas: number[]; changeKg: number; record: boolean; lastDate: string }[]>;
}

/** Fixed-clock app defaulting to CREW_NOW; `at` moves the insert clock for distinct created_at values. */
function crewApp() {
  let t = CREW_NOW.getTime();
  const { app, queries } = apiApp({ now: () => new Date(t) });
  return { app, queries, at: (iso: string) => void (t = Date.parse(iso)) };
}

async function crewProfile(app: ReturnType<typeof socialApp>, key: string, handle: string, displayName: string) {
  const u = await login(app, key);
  const res = await call(app, "PUT", "/social/profile", { token: u.token, body: { handle, displayName, bio: "" } });
  if (res.status !== 200) throw new Error(await res.text());
  return u;
}

async function crewGet(app: ReturnType<typeof socialApp>, token: string, query = ""): Promise<CrewBody> {
  const res = await call(app, "GET", `/social/crew${query}`, { token });
  if (res.status !== 200) throw new Error(`crew GET failed: ${res.status} ${await res.text()}`);
  return (await res.json()) as CrewBody;
}

test("crew: requires a Bearer session", async () => {
  const app = socialApp(() => CREW_NOW);
  await withProfile(app, "a", "crewnoau");
  assert.equal((await call(app, "GET", "/social/crew")).status, 401);
});

test("crew: malformed week → 400 with the contract error", async () => {
  const app = socialApp(() => CREW_NOW);
  const a = await withProfile(app, "a", "weekcheck");
  for (const bad of ["2026-W99", "bad"]) {
    const res = await call(app, "GET", `/social/crew?week=${encodeURIComponent(bad)}`, { token: a.token });
    assert.equal(res.status, 400, bad);
    assert.deepEqual(await res.json(), { error: "week must be YYYY-Www" });
  }
});

test("crew: solo lifter — self only, defaults, empty aggregates", async () => {
  const app = socialApp(() => CREW_NOW);
  const a = await withProfile(app, "a", "solo_lift");
  assert.deepEqual(await crewGet(app, a.token), {
    week: "2026-W39",
    weekStart: "2026-09-21",
    members: [{ userId: a.user.id, handle: "solo_lift", displayName: "Lifter", isSelf: true, target: 3, days: [], sessions: 0 }],
    streakWeeks: 0,
    records: [],
    lifts: {},
  });
});

test("crew: week placement uses payload.localDate, not created_at", async () => {
  const c = crewApp();
  const a = await withProfile(c.app, "a", "placeful1");
  c.at("2026-09-28T01:00:00Z"); // Monday of W40
  await addPost(c.app, a.token, { type: "session", payload: { localDate: "2026-09-27" } });
  const w39 = await crewGet(c.app, a.token, "?week=2026-W39");
  assert.equal(w39.members[0].sessions, 1);
  assert.deepEqual(w39.members[0].days, ["2026-09-27"]);
  const w40 = await crewGet(c.app, a.token, "?week=2026-W40");
  assert.equal(w40.members[0].sessions, 0);
  assert.deepEqual(w40.members[0].days, []);
});

test("crew: session post without localDate falls back to the UTC date of created_at", async () => {
  const c = crewApp();
  const a = await withProfile(c.app, "a", "fallback1");
  c.at("2026-09-25T23:30:00Z");
  await addPost(c.app, a.token, { type: "session", payload: {} });
  const data = await crewGet(c.app, a.token);
  assert.equal(data.members[0].sessions, 1);
  assert.deepEqual(data.members[0].days, ["2026-09-25"]);
});

test("crew: sessions count posts, days are distinct and ascending", async () => {
  const c = crewApp();
  const a = await withProfile(c.app, "a", "daycount");
  for (const [at, ld] of [
    ["2026-09-24T09:00:00Z", "2026-09-24"],
    ["2026-09-22T08:00:00Z", "2026-09-22"],
    ["2026-09-22T20:00:00Z", "2026-09-22"],
  ] as const) {
    c.at(at);
    await addPost(c.app, a.token, { type: "session", payload: { localDate: ld } });
  }
  const data = await crewGet(c.app, a.token);
  assert.equal(data.members[0].sessions, 3);
  assert.deepEqual(data.members[0].days, ["2026-09-22", "2026-09-24"]);
});

test("crew: target = most recent numeric weekTarget, rounded and clamped 1-7; default 3", async () => {
  // newest numeric wins; a string weekTarget is ignored; 0 clamps up to 1
  const one = crewApp();
  const a = await crewProfile(one.app, "a", "targeting", "A");
  for (const [at, wt] of [
    ["2026-09-21T09:00:00Z", 9],
    ["2026-09-22T09:00:00Z", "4"],
    ["2026-09-23T09:00:00Z", 0],
  ] as const) {
    one.at(at);
    await addPost(one.app, a.token, { type: "session", payload: { localDate: at.slice(0, 10), weekTarget: wt } });
  }
  assert.equal((await crewGet(one.app, a.token)).members[0].target, 1);

  // 9 clamps down to 7
  const two = crewApp();
  const b = await crewProfile(two.app, "b", "target_hi", "B");
  two.at("2026-09-22T09:00:00Z");
  await addPost(two.app, b.token, { type: "session", payload: { localDate: "2026-09-22", weekTarget: 9 } });
  assert.equal((await crewGet(two.app, b.token)).members[0].target, 7);

  // nothing numeric anywhere → default 3 (already covered by the solo test, kept explicit)
  const three = crewApp();
  const d = await crewProfile(three.app, "d", "target_no", "D");
  three.at("2026-09-22T09:00:00Z");
  await addPost(three.app, d.token, { type: "session", payload: { localDate: "2026-09-22", weekTarget: "4" } });
  assert.equal((await crewGet(three.app, d.token)).members[0].target, 3);
});

test("crew: members ordered self, then displayName case-insensitive; profileless followed user keeps nulls", async () => {
  const app = socialApp(() => CREW_NOW);
  const a = await crewProfile(app, "a", "order_self", "Zed");
  const anna = await crewProfile(app, "n", "order_anna", "anna");
  const bob = await crewProfile(app, "m", "order_bob", "Bob");
  const noProfile = await login(app, "x");
  for (const u of [noProfile, bob, anna]) await call(app, "POST", `/social/follow/${u.user.id}`, { token: a.token });
  const data = await crewGet(app, a.token);
  assert.deepEqual(data.members.map((m) => [m.userId, m.isSelf]), [[a.user.id, true], [noProfile.user.id, false], [anna.user.id, false], [bob.user.id, false]]);
  const profileless = data.members[1]!;
  assert.equal(profileless.handle, null);
  assert.equal(profileless.displayName, null);
  assert.equal(data.members[2]!.displayName, "anna");
});

test("crew: a follower self does not follow never appears in members, records or lifts", async () => {
  const c = crewApp();
  const a = await crewProfile(c.app, "a", "private_a", "A");
  const b = await crewProfile(c.app, "b", "private_b", "B");
  const fan = await crewProfile(c.app, "f", "private_f", "F");
  await call(c.app, "POST", `/social/follow/${b.user.id}`, { token: a.token }); // crew = a + b
  await call(c.app, "POST", `/social/follow/${a.user.id}`, { token: fan.token }); // fan follows a, not reciprocal
  c.at("2026-09-22T09:00:00Z");
  await addPost(c.app, fan.token, { type: "session", payload: { localDate: "2026-09-22", lifts: [{ id: "deadlift", e1rm: 500 }] } });
  await addPost(c.app, fan.token, { type: "pr", payload: { exercise: "Fan Lift", exerciseId: "fan_lift", e1rm: 500, localDate: "2026-09-22" } });
  const data = await crewGet(c.app, a.token);
  assert.deepEqual(data.members.map((m) => m.userId), [a.user.id, b.user.id]);
  assert.deepEqual(data.records, []);
  assert.deepEqual(data.lifts, {});
});

test("crew: records — pr posts in the week, newest first, kudos reflect the viewer, nulls for missing fields", async () => {
  const c = crewApp();
  const a = await crewProfile(c.app, "a", "record_aa", "A");
  const b = await crewProfile(c.app, "b", "record_bb", "B");
  await call(c.app, "POST", `/social/follow/${b.user.id}`, { token: a.token });

  c.at("2026-09-21T08:00:00Z");
  const bare = await addPost(c.app, b.token, { type: "pr", payload: { e1rm: 90, weightKg: "102", reps: 2.5, localDate: "2026-09-21" } }); // exerciseId/weightKg/reps null
  c.at("2026-09-20T08:00:00Z");
  await addPost(c.app, b.token, { type: "pr", payload: { exercise: "Squat", exerciseId: "squat", e1rm: 300, localDate: "2026-09-20" } }); // W38 → outside
  c.at("2026-09-22T09:00:00Z");
  const full = await addPost(c.app, b.token, {
    type: "pr", payload: { exercise: "Deadlift", exerciseId: "deadlift", e1rm: 220.5, weightKg: 200, reps: 3, localDate: "2026-09-22" },
  });
  await call(c.app, "POST", `/social/posts/${full.post.id}/kudos`, { token: a.token });
  c.at("2026-09-23T09:00:00Z");
  await addPost(c.app, b.token, { type: "pr", payload: { exercise: "Bench", localDate: "2026-09-23" } }); // no numeric e1rm → skipped
  c.at("2026-09-24T09:00:00Z");
  const own = await addPost(c.app, a.token, { type: "pr", payload: { exercise: "Row", e1rm: 150, localDate: "2026-09-24" } });

  const data = await crewGet(c.app, a.token);
  assert.deepEqual(data.records, [
    { postId: own.post.id, userId: a.user.id, handle: "record_aa", displayName: "A", isSelf: true, exerciseId: null, exercise: "Row", e1rm: 150, weightKg: null, reps: null, date: "2026-09-24", kudos: 0, kudoed: false },
    { postId: full.post.id, userId: b.user.id, handle: "record_bb", displayName: "B", isSelf: false, exerciseId: "deadlift", exercise: "Deadlift", e1rm: 220.5, weightKg: 200, reps: 3, date: "2026-09-22", kudos: 1, kudoed: true },
    { postId: bare.post.id, userId: b.user.id, handle: "record_bb", displayName: "B", isSelf: false, exerciseId: null, exercise: "", e1rm: 90, weightKg: null, reps: null, date: "2026-09-21", kudos: 0, kudoed: false },
  ]);
});

test("crew: lifts — last 12 of 14 points, deltas vs first kept, cutoff 16 weeks, self excluded", async () => {
  const c = crewApp();
  const a = await crewProfile(c.app, "a", "lifts_aa", "A");
  const b = await crewProfile(c.app, "b", "lifts_bb", "B");
  const d = await crewProfile(c.app, "d", "lifts_dd", "D");
  const e = await crewProfile(c.app, "e", "lifts_ee", "E");
  for (const u of [b, d, e]) await call(c.app, "POST", `/social/follow/${u.user.id}`, { token: a.token });

  // 14 daily points, e1rm = 100 + i * 0.5 → kept are i = 2..13
  for (let i = 0; i < 14; i++) {
    const day = `2026-09-${String(14 + i).padStart(2, "0")}`; // 09-14 .. 09-27
    c.at(`${day}T18:00:00Z`);
    await addPost(c.app, b.token, { type: "session", payload: { localDate: day, lifts: [{ id: "deadlift", e1rm: 100 + i * 0.5 }] } });
  }
  // self trains too — never in lifts
  c.at("2026-09-26T09:00:00Z");
  await addPost(c.app, a.token, { type: "session", payload: { localDate: "2026-09-26", lifts: [{ id: "deadlift", e1rm: 999 }] } });
  // single point → deltas [0]
  c.at("2026-09-20T09:00:00Z");
  await addPost(c.app, d.token, { type: "session", payload: { localDate: "2026-09-20", lifts: [{ id: "squat", e1rm: 140 }] } });
  // 16-week window ends on the week's Sunday 2026-09-27: 2026-06-08 is in, 2026-06-07 is out
  c.at("2026-06-08T09:00:00Z");
  await addPost(c.app, e.token, { type: "session", payload: { localDate: "2026-06-08", lifts: [{ id: "row", e1rm: 60 }] } });
  c.at("2026-06-07T09:00:00Z");
  await addPost(c.app, e.token, { type: "session", payload: { localDate: "2026-06-07", lifts: [{ id: "bench", e1rm: 61 }] } });
  // after the week's Sunday → out of the window
  c.at("2026-09-28T09:00:00Z");
  await addPost(c.app, d.token, { type: "session", payload: { localDate: "2026-09-28", lifts: [{ id: "press", e1rm: 70 }] } });

  c.at("2026-09-24T12:00:00Z"); // view from inside W39
  const data = await crewGet(c.app, a.token);
  assert.deepEqual(data.lifts, {
    deadlift: [{ userId: b.user.id, deltas: [0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 5.5], changeKg: 5.5, record: true, lastDate: "2026-09-27" }],
    squat: [{ userId: d.user.id, deltas: [0], changeKg: 0, record: false, lastDate: "2026-09-20" }],
    row: [{ userId: e.user.id, deltas: [0], changeKg: 0, record: false, lastDate: "2026-06-08" }],
  });
});

test("crew: malformed lift payloads are ignored, never a 500", async () => {
  const c = crewApp();
  const a = await crewProfile(c.app, "a", "malform_a", "A");
  const b = await crewProfile(c.app, "b", "malform_b", "B");
  await call(c.app, "POST", `/social/follow/${b.user.id}`, { token: a.token });
  c.at("2026-09-22T09:00:00Z");
  await addPost(c.app, b.token, { type: "session", payload: { localDate: "2026-09-22", lifts: "nope" } });
  c.at("2026-09-23T09:00:00Z");
  await addPost(c.app, b.token, {
    type: "session",
    payload: { localDate: "2026-09-23", lifts: [{ id: "Dead Lift", e1rm: 100 }, { id: "x".repeat(65), e1rm: 100 }, "junk"] },
  });
  c.at("2026-09-24T09:00:00Z");
  await addPost(c.app, b.token, {
    type: "session",
    payload: { localDate: "2026-09-24", lifts: [{ id: "bench", e1rm: 0 }, { id: "squat", e1rm: -5 }, { id: "row", e1rm: "220" }] },
  });
  const res = await call(c.app, "GET", "/social/crew", { token: a.token });
  assert.equal(res.status, 200);
  assert.deepEqual(((await res.json()) as CrewBody).lifts, {});
});

test("crew: streakWeeks — 3 full weeks + current = 4; current-week gap counts from last week; solo = 0", async () => {
  const TUESDAYS = ["2026-09-01", "2026-09-08", "2026-09-15", "2026-09-22"]; // W36..W39

  // self + 2 followed, everyone trains every week → 4
  const full = crewApp();
  const fa = await crewProfile(full.app, "a", "streak_a", "A");
  const fb = await crewProfile(full.app, "b", "streak_b", "B");
  const fc = await crewProfile(full.app, "c", "streak_c", "C");
  for (const u of [fb, fc]) await call(full.app, "POST", `/social/follow/${u.user.id}`, { token: fa.token });
  for (const ld of TUESDAYS) for (const u of [fa, fb, fc]) {
    full.at(`${ld}T10:00:00Z`);
    await addPost(full.app, u.token, { type: "session", payload: { localDate: ld } });
  }
  assert.equal((await crewGet(full.app, fa.token)).streakWeeks, 4);

  // one member has no session yet in the current week → count from last week → 3
  const gap = crewApp();
  const ga = await crewProfile(gap.app, "a", "gapw_a", "A");
  const gb = await crewProfile(gap.app, "b", "gapw_b", "B");
  const gc = await crewProfile(gap.app, "c", "gapw_c", "C");
  for (const u of [gb, gc]) await call(gap.app, "POST", `/social/follow/${u.user.id}`, { token: ga.token });
  for (const ld of TUESDAYS) for (const u of [ga, gb, gc]) {
    if (u === gc && ld === "2026-09-22") continue; // c skips the current week
    gap.at(`${ld}T10:00:00Z`);
    await addPost(gap.app, u.token, { type: "session", payload: { localDate: ld } });
  }
  assert.equal((await crewGet(gap.app, ga.token)).streakWeeks, 3);

  // a member whose first session is in the current week does not break earlier weeks → 3
  const late = crewApp();
  const la = await crewProfile(late.app, "a", "latew_a", "A");
  const lb = await crewProfile(late.app, "b", "latew_b", "B");
  const lc = await crewProfile(late.app, "c", "latew_c", "C");
  for (const u of [lb, lc]) await call(late.app, "POST", `/social/follow/${u.user.id}`, { token: la.token });
  for (const ld of TUESDAYS) for (const u of [la, lb] as const) {
    if (ld === "2026-09-22") continue; // a and b stop after W38
    late.at(`${ld}T10:00:00Z`);
    await addPost(late.app, u.token, { type: "session", payload: { localDate: ld } });
  }
  late.at("2026-09-22T10:00:00Z");
  await addPost(late.app, lc.token, { type: "session", payload: { localDate: "2026-09-22" } }); // c only joins now
  assert.equal((await crewGet(late.app, la.token)).streakWeeks, 3);

  // solo lifter → 0
  const solo = crewApp();
  const sa = await crewProfile(solo.app, "s", "solo_stk", "S");
  for (const ld of TUESDAYS) {
    solo.at(`${ld}T10:00:00Z`);
    await addPost(solo.app, sa.token, { type: "session", payload: { localDate: ld } });
  }
  assert.equal((await crewGet(solo.app, sa.token)).streakWeeks, 0);
});

test("crew: lifts accepts the object map form (and the legacy array); bad map entries skip only that entry", async () => {
  const c = crewApp();
  const a = await crewProfile(c.app, "a", "mapform_a", "A");
  const b = await crewProfile(c.app, "b", "mapform_b", "B");
  await call(c.app, "POST", `/social/follow/${b.user.id}`, { token: a.token });
  c.at("2026-09-22T09:00:00Z");
  await addPost(c.app, b.token, { type: "session", payload: { localDate: "2026-09-22", lifts: { deadlift: 150.5, back_squat: 120 } } });
  c.at("2026-09-24T09:00:00Z");
  await addPost(c.app, b.token, { type: "session", payload: { localDate: "2026-09-24", lifts: [{ id: "deadlift", e1rm: 160 }] } }); // array form still works
  c.at("2026-09-25T09:00:00Z");
  await addPost(c.app, b.token, {
    type: "session",
    payload: {
      localDate: "2026-09-25",
      lifts: { "Dead Lift": 100, bad_zero: 0, bad_neg: -1, bad_str: "9", bad_big: 1001, bad_huge: 1e308, good_lift: 100 },
    },
  });
  const data = await crewGet(c.app, a.token);
  assert.deepEqual(data.lifts, {
    deadlift: [{ userId: b.user.id, deltas: [0, 9.5], changeKg: 9.5, record: true, lastDate: "2026-09-24" }],
    back_squat: [{ userId: b.user.id, deltas: [0], changeKg: 0, record: false, lastDate: "2026-09-22" }],
    good_lift: [{ userId: b.user.id, deltas: [0], changeKg: 0, record: false, lastDate: "2026-09-25" }],
  });
});

function assertAllNumbersFinite(v: unknown, path = "$"): void {
  if (typeof v === "number") assert.ok(Number.isFinite(v), `${path} is not finite`);
  else if (Array.isArray(v)) v.forEach((x, i) => assertAllNumbersFinite(x, `${path}[${i}]`));
  else if (v && typeof v === "object") for (const [k, x] of Object.entries(v)) assertAllNumbersFinite(x, `${path}.${k}`);
}

test("crew: value bounds — bad reps/weightKg become null, out-of-range e1rm skips the record, numbers stay finite", async () => {
  const c = crewApp();
  const a = await crewProfile(c.app, "a", "bounds_aa", "A");
  const b = await crewProfile(c.app, "b", "bounds_bb", "B");
  await call(c.app, "POST", `/social/follow/${b.user.id}`, { token: a.token });
  const pr = (exercise: string, extra: Record<string, unknown>) => ({ type: "pr", payload: { exercise, localDate: "2026-09-21", ...extra } });
  const cases: [string, string, Record<string, unknown>][] = [
    ["09:00", "Bench", { exerciseId: "bench", e1rm: 100, weightKg: 80, reps: 5 }],
    ["10:00", "R1", { e1rm: 100, reps: 1e21 }],
    ["11:00", "R2", { e1rm: 100, reps: 0 }],
    ["12:00", "R3", { e1rm: 100, reps: 101 }],
    ["13:00", "R4", { e1rm: 100, reps: 5.5 }],
  ];
  for (const [time, exercise, extra] of cases) {
    c.at(`2026-09-21T${time}:00Z`);
    await addPost(c.app, b.token, pr(exercise, extra));
  }
  for (const [time, exercise, extra] of [
    ["09", "W1", { e1rm: 100, weightKg: 0 }],
    ["10", "W2", { e1rm: 100, weightKg: 1001 }],
    ["11", "W3", { e1rm: 100, weightKg: "80" }],
  ] as [string, string, Record<string, unknown>][]) {
    c.at(`2026-09-22T${time}:00:00Z`);
    await addPost(c.app, b.token, pr(exercise, { ...extra, localDate: "2026-09-22" }));
  }
  c.at("2026-09-23T09:00:00Z");
  await addPost(c.app, b.token, pr("Ghost1", { e1rm: 1001, localDate: "2026-09-23" })); // e1rm above 1000 → skipped entirely
  await addPost(c.app, b.token, pr("Ghost2", { e1rm: 0, localDate: "2026-09-23" })); // e1rm at 0 → skipped entirely
  c.at("2026-09-24T09:00:00Z");
  await addPost(c.app, b.token, { type: "session", payload: { localDate: "2026-09-24", lifts: { huge: 1000.5, zero: 0 } } }); // session points out of bounds

  const data = await crewGet(c.app, a.token);
  assert.deepEqual(
    data.records.map((r) => [r.exercise, r.e1rm, r.weightKg, r.reps]),
    [
      ["W3", 100, null, null],
      ["W2", 100, null, null],
      ["W1", 100, null, null],
      ["R4", 100, null, null],
      ["R3", 100, null, null],
      ["R2", 100, null, null],
      ["R1", 100, null, null],
      ["Bench", 100, 80, 5],
    ],
  );
  assert.equal(data.records.some((r) => r.exercise.startsWith("Ghost")), false);
  assert.deepEqual(data.lifts, {}); // 1000.5 and 0 are outside (0, 1000]
  assertAllNumbersFinite(data);
});

test("crew: streak counts from each member's first session EVER, not the 26-week window", async () => {
  const c = crewApp();
  const a = await crewProfile(c.app, "a", "anc_a", "A");
  const b = await crewProfile(c.app, "b", "anc_b", "B");
  const d = await crewProfile(c.app, "d", "anc_d", "D");
  for (const u of [b, d]) await call(c.app, "POST", `/social/follow/${u.user.id}`, { token: a.token });

  // B's first session ever: ~29 weeks before W39 — outside the 26-week fetch window
  c.at("2026-03-03T10:00:00Z");
  await addPost(c.app, b.token, { type: "session", payload: { localDate: "2026-03-03" } });

  // A and D train every week for 10 weeks (W30..W39); B only in the current and previous week
  const tuesdays = [...Array(10)].map((_, i) => new Date(Date.UTC(2026, 8, 22) - (9 - i) * 7 * 86400_000).toISOString().slice(0, 10));
  for (const ld of tuesdays) for (const u of [a, d] as const) {
    c.at(`${ld}T10:00:00Z`);
    await addPost(c.app, u.token, { type: "session", payload: { localDate: ld } });
  }
  for (const ld of tuesdays.slice(-2)) { // W38 + W39 only
    c.at(`${ld}T11:00:00Z`);
    await addPost(c.app, b.token, { type: "session", payload: { localDate: ld } });
  }

  c.at("2026-09-24T12:00:00Z");
  // B counts for every week since 2026-03-03, so W37 (no B session) breaks the streak → 2, not 10
  assert.equal((await crewGet(c.app, a.token)).streakWeeks, 2);
});

test("crew: a legacy self-follow row never duplicates self or puts self in lifts", async () => {
  const c = crewApp();
  const a = await crewProfile(c.app, "a", "selfy_a", "A");
  await c.queries.insertFollow(a.user.id, a.user.id, "2026-01-01T00:00:00Z"); // legacy row, direct insert
  c.at("2026-09-22T09:00:00Z");
  await addPost(c.app, a.token, { type: "session", payload: { localDate: "2026-09-22", lifts: { deadlift: 180 } } });
  await addPost(c.app, a.token, { type: "pr", payload: { exercise: "Row", e1rm: 120, localDate: "2026-09-22" } });
  const data = await crewGet(c.app, a.token);
  assert.deepEqual(data.members.map((m) => m.userId), [a.user.id]); // self exactly once
  assert.deepEqual(data.records.map((r) => r.userId), [a.user.id]); // record listed once
  assert.deepEqual(data.lifts, {}); // self never in lifts
});

test("crew: pr posts load only the week's bounds in SQL; sessions still load 26 weeks", async () => {
  const c = crewApp();
  const a = await crewProfile(c.app, "a", "spy_a", "A");
  const b = await crewProfile(c.app, "b", "spy_b", "B");
  await call(c.app, "POST", `/social/follow/${b.user.id}`, { token: a.token });
  c.at("2026-09-22T09:00:00Z");
  await addPost(c.app, b.token, { type: "pr", payload: { exercise: "Deadlift", e1rm: 220, localDate: "2026-09-22" } });
  c.at("2026-09-01T09:00:00Z"); // created 3 weeks early, localDate inside the week — never loaded
  await addPost(c.app, b.token, { type: "pr", payload: { exercise: "Ghost", e1rm: 300, localDate: "2026-09-23" } });

  const prCalls: [string, string][] = [];
  const sessionCalls: string[] = [];
  const origPr = c.queries.crewPrPosts.bind(c.queries);
  const origSession = c.queries.crewSessionPosts.bind(c.queries);
  c.queries.crewPrPosts = async (authors, fromISO, toISO) => {
    prCalls.push([fromISO, toISO]);
    return origPr(authors, fromISO, toISO);
  };
  c.queries.crewSessionPosts = async (authors, sinceISO) => {
    sessionCalls.push(sinceISO);
    return origSession(authors, sinceISO);
  };

  c.at("2026-09-24T12:00:00Z"); // view from inside W39
  const data = await crewGet(c.app, a.token);
  // Monday − 1 day .. Sunday + 2 days (UTC slack around the week's local dates)
  assert.deepEqual(prCalls, [["2026-09-20T00:00:00.000Z", "2026-09-29T00:00:00.000Z"]]);
  assert.deepEqual(sessionCalls, ["2026-03-23T00:00:00.000Z"]); // 26 weeks back
  assert.deepEqual(data.records.map((r) => r.exercise), ["Deadlift"]); // the ghost pr never loaded
});

test("crew invite page: GET /c/:handle is public inert HTML", async () => {
  const app = socialApp(() => CREW_NOW);
  await withProfile(app, "a", "ann_lifts");
  const res = await app(new Request("http://x/c/ann_lifts")); // no auth header, no app secret
  assert.equal(res.status, 200);
  assert.ok((res.headers.get("content-type") ?? "").startsWith("text/html"));
  assert.ok((res.headers.get("content-security-policy") ?? "").includes("default-src 'none'"));
  const body = await res.text();
  assert.ok(body.includes("regulift://crew/ann_lifts"), "deep link missing");
  assert.ok(body.includes("@ann_lifts"), "handle missing");
  assert.ok(body.includes("Train with @ann_lifts on Regulift"), "title missing");
  assert.ok(body.includes("https://regulift.app"), "fallback link missing");

  const upper = await app(new Request("http://x/c/Ann_Lifts"));
  assert.equal(upper.status, 200);
  assert.ok((await upper.text()).includes("regulift://crew/ann_lifts")); // lowercased

  assert.equal((await app(new Request("http://x/c/Bad-Handle!"))).status, 404);
  assert.equal((await app(new Request("http://x/c/AB"))).status, 404); // too short
});
