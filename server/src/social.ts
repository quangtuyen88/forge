import type { PostRow, ProfileRow, Queries, UserRow } from "./queries.js";
import { json, readJsonBody } from "./http.js";

export interface SocialDeps {
  now?: () => Date;
}

const HANDLE_RE = /^[a-z0-9_]{3,20}$/;
const WEEK_RE = /^\d{4}-W(0[1-9]|[1-4]\d|5[0-3])$/;

// ---------- ISO week helpers (UTC) ----------

/** "YYYY-Www" for a date (the Thursday trick). */
export function isoWeekKey(d: Date): string {
  const t = new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate()));
  const day = t.getUTCDay() || 7;
  t.setUTCDate(t.getUTCDate() + 4 - day); // this ISO week's Thursday
  const y = t.getUTCFullYear();
  const week = Math.ceil((Math.floor((t.getTime() - Date.UTC(y, 0, 1)) / 86400_000) + 1) / 7);
  return `${y}-W${String(week).padStart(2, "0")}`;
}

/** Monday 00:00 UTC of an ISO week key, or null when malformed. */
export function isoWeekStart(key: string): Date | null {
  if (!WEEK_RE.test(key)) return null;
  const y = Number(key.slice(0, 4));
  const w = Number(key.slice(6));
  const jan4 = new Date(Date.UTC(y, 0, 4)); // always in week 1
  const day = jan4.getUTCDay() || 7;
  const start = new Date(jan4);
  start.setUTCDate(4 + 1 - day + (w - 1) * 7);
  return start;
}

function weekShift(key: string, weeks: number): string {
  const s = isoWeekStart(key)!;
  s.setUTCDate(s.getUTCDate() + weeks * 7);
  return isoWeekKey(s);
}

// ---------- helpers ----------

function publicProfile(p: ProfileRow) {
  return { userId: p.user_id, handle: p.handle, displayName: p.display_name, bio: p.bio };
}

/** Profile stats from a user's posts: session count, consecutive-week streak (12-week window), top 3 PRs by e1rm. */
export function statsFrom(posts: PostRow[], now: Date): { sessions: number; streakWeeks: number; topPRs: { exercise: string; e1rm: number }[] } {
  const sessions = posts.filter((p) => p.type === "session");
  const cutoff = now.getTime() - 12 * 7 * 86400_000;
  const weeks = new Set(
    sessions.filter((p) => Date.parse(p.created_at) >= cutoff).map((p) => isoWeekKey(new Date(p.created_at))),
  );
  let cursor = isoWeekKey(now);
  if (!weeks.has(cursor)) cursor = weekShift(cursor, -1); // streak may end last week
  let streak = 0;
  while (weeks.has(cursor)) {
    streak++;
    cursor = weekShift(cursor, -1);
  }
  const topPRs = posts
    .filter((p) => p.type === "pr")
    .map((p) => JSON.parse(p.payload) as { exercise?: unknown; e1rm?: unknown })
    .filter((x) => typeof x.exercise === "string" && typeof x.e1rm === "number")
    .sort((a, b) => (b.e1rm as number) - (a.e1rm as number))
    .slice(0, 3)
    .map((x) => ({ exercise: x.exercise as string, e1rm: x.e1rm as number }));
  return { sessions: sessions.length, streakWeeks: streak, topPRs };
}

/** Social routes per API.md. Returns null when no /social route matches. */
export async function handleSocial(
  req: Request,
  url: URL,
  user: UserRow,
  q: Queries,
  deps: SocialDeps = {},
): Promise<Response | null> {
  const p = url.pathname;
  const now = () => deps.now?.() ?? new Date();
  const body = async (): Promise<Record<string, unknown> | null> => {
    const b = await readJsonBody(req);
    return "error" in b ? null : (b.value as Record<string, unknown>);
  };

  if (p === "/social/profile") {
    if (req.method === "GET") {
      const profile = await q.getProfile(user.id);
      return profile ? json(200, { profile: publicProfile(profile) }) : json(404, { error: "profile not found" });
    }
    if (req.method === "PUT") {
      const b = await body();
      if (b === null) return json(400, { error: "invalid JSON" });
      const handle = typeof b.handle === "string" ? b.handle.trim().toLowerCase() : "";
      const displayName = typeof b.displayName === "string" ? b.displayName.trim() : "";
      const bio = typeof b.bio === "string" ? b.bio : "";
      if (!HANDLE_RE.test(handle)) return json(400, { error: "handle must be 3-20 chars of a-z, 0-9, _" });
      if (!displayName || displayName.length > 40) return json(400, { error: "displayName must be 1-40 chars" });
      if (bio.length > 160) return json(400, { error: "bio must be at most 160 chars" });
      const clash = await q.getProfileByHandle(handle);
      if (clash && clash.user_id !== user.id) return json(409, { error: "Handle taken" });
      const profile = await q.upsertProfile(user.id, handle, displayName, bio, now().toISOString());
      return json(200, { profile: publicProfile(profile) });
    }
  }

  if (req.method === "GET" && p.startsWith("/social/users/")) {
    const handle = p.slice("/social/users/".length);
    if (!HANDLE_RE.test(handle)) return json(404, { error: "user not found" });
    const profile = await q.getProfileByHandle(handle);
    if (!profile) return json(404, { error: "user not found" });
    return json(200, {
      profile: publicProfile(profile),
      stats: statsFrom(await q.userPosts(profile.user_id), now()),
      following: await q.isFollowing(user.id, profile.user_id),
    });
  }

  if ((req.method === "POST" || req.method === "DELETE") && p.startsWith("/social/follow/")) {
    const target = await q.getUserById(p.slice("/social/follow/".length));
    if (!target) return json(404, { error: "user not found" });
    if (req.method === "POST") {
      if (target.id === user.id) return json(400, { error: "cannot follow yourself" });
      await q.insertFollow(user.id, target.id, now().toISOString());
    } else {
      await q.deleteFollow(user.id, target.id);
    }
    return json(200, { ok: true });
  }

  if (req.method === "GET" && p === "/social/feed") {
    const authors = [user.id, ...(await q.followedIds(user.id))];
    const rawCursor = url.searchParams.get("cursor");
    const cursor = rawCursor && rawCursor.trim() ? rawCursor.trim() : null;
    if (cursor !== null && !Number.isFinite(Date.parse(cursor))) return json(400, { error: "invalid cursor" });
    const rows = await q.feedPosts(authors, cursor, 31, user.id);
    const hasMore = rows.length > 30;
    const page = rows.slice(0, 30);
    return json(200, {
      posts: page.map((r) => ({
        id: r.id,
        user: { id: r.user_id, handle: r.handle, displayName: r.display_name },
        type: r.type,
        payload: JSON.parse(r.payload),
        createdAt: r.created_at,
        kudos: r.kudos,
        kudoed: r.kudoed === 1,
        comments: r.comments,
      })),
      nextCursor: hasMore ? page[29]!.created_at : null,
    });
  }

  if (req.method === "POST" && p === "/social/posts") {
    const b = await body();
    if (b === null) return json(400, { error: "invalid JSON" });
    if (b.type !== "session" && b.type !== "pr") return json(400, { error: "type must be session or pr" });
    if (!b.payload || typeof b.payload !== "object" || Array.isArray(b.payload)) {
      return json(400, { error: "payload must be an object" });
    }
    const payload = JSON.stringify(b.payload);
    if (payload.length > 8192) return json(400, { error: "payload too large (max 8 KB)" });
    const id = crypto.randomUUID();
    const createdAt = now().toISOString();
    await q.insertPost(id, user.id, b.type, payload, createdAt);
    const profile = await q.getProfile(user.id);
    return json(200, {
      post: {
        id,
        user: { id: user.id, handle: profile?.handle ?? null, displayName: profile?.display_name ?? null },
        type: b.type,
        payload: b.payload,
        createdAt,
        kudos: 0,
        kudoed: false,
        comments: 0,
      },
    });
  }

  if ((req.method === "POST" || req.method === "DELETE") && p.endsWith("/kudos") && p.startsWith("/social/posts/")) {
    const postId = p.slice("/social/posts/".length, -"/kudos".length);
    const post = await q.getPost(postId);
    if (!post) return json(404, { error: "post not found" });
    if (req.method === "POST") await q.addKudos(post.id, user.id, now().toISOString());
    else await q.removeKudos(post.id, user.id);
    return json(200, { ok: true });
  }

  if (p.startsWith("/social/posts/") && p.endsWith("/comments") && (req.method === "GET" || req.method === "POST")) {
    const postId = p.slice("/social/posts/".length, -"/comments".length);
    const post = await q.getPost(postId);
    if (!post) return json(404, { error: "post not found" });
    if (req.method === "GET") {
      const rows = await q.commentsForPost(post.id, 100);
      return json(200, {
        comments: rows.map((c) => ({ id: c.id, userId: c.user_id, text: c.text, createdAt: c.created_at })),
      });
    }
    const b = await body();
    if (b === null) return json(400, { error: "invalid JSON" });
    const text = typeof b.text === "string" ? b.text.trim() : "";
    if (!text || text.length > 500) return json(400, { error: "text must be 1-500 chars" });
    const id = crypto.randomUUID();
    const createdAt = now().toISOString();
    await q.insertComment(id, post.id, user.id, text, createdAt);
    return json(200, { comment: { id, userId: user.id, text, createdAt } });
  }

  if (req.method === "GET" && p === "/social/leaderboard") {
    const week = url.searchParams.get("week") ?? isoWeekKey(now());
    const start = isoWeekStart(week);
    if (!start) return json(400, { error: "week must be YYYY-Www" });
    const end = new Date(start.getTime() + 7 * 86400_000);
    const authors = [user.id, ...(await q.followedIds(user.id))];
    const weekPosts = await q.postsForWeek(authors, start.toISOString(), end.toISOString());
    const agg = new Map<string, { sessions: number; tonnageKg: number }>();
    for (const post of weekPosts) {
      const a = agg.get(post.user_id) ?? { sessions: 0, tonnageKg: 0 };
      a.sessions++;
      const t = (JSON.parse(post.payload) as { tonnageKg?: unknown }).tonnageKg;
      if (typeof t === "number") a.tonnageKg += t;
      agg.set(post.user_id, a);
    }
    const profiles = await q.profilesFor(authors);
    const handleOf = new Map(profiles.map((pr) => [pr.user_id, pr.handle]));
    return json(
      200,
      authors
        .map((id) => ({
          userId: id,
          handle: handleOf.get(id) ?? null,
          sessions: agg.get(id)?.sessions ?? 0,
          tonnageKg: agg.get(id)?.tonnageKg ?? 0,
        }))
        .sort((a, b) => b.sessions - a.sessions || b.tonnageKg - a.tonnageKg),
    );
  }

  return null;
}
