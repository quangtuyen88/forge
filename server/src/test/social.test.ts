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
