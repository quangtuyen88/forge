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

/** ISO week key of a "YYYY-MM-DD" local date (treated as UTC). */
function weekKeyOfLocalDate(localDate: string): string {
  return isoWeekKey(new Date(`${localDate}T00:00:00Z`));
}

// ---------- crew (GET /social/crew) ----------

const LOCAL_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const LIFT_ID_RE = /^[a-z0-9_]{1,64}$/;
export const CREW_MAX_FOLLOWED = 50;
const CREW_STREAK_WEEKS = 26;
const CREW_LIFT_WEEKS = 16;
const CREW_LIFT_POINTS = 12;

/** A crew post: payload parsed once, crew-relevant fields validated. Malformed pieces are dropped, never thrown. */
export interface CrewPost {
  id: string;
  userId: string;
  type: string;
  createdAt: string;
  localDate: string;
  weekTarget: number | null;
  lifts: { id: string; e1rm: number }[];
  pr: { exerciseId: string | null; exercise: string; e1rm: number | null; weightKg: number | null; reps: number | null } | null;
}

export interface CrewLiftLine { userId: string; deltas: number[]; changeKg: number; record: boolean; lastDate: string }

function finiteNumber(v: unknown): number | null {
  return typeof v === "number" && Number.isFinite(v) ? v : null;
}

/** kg-typed values the server accepts: finite and in (0, 1000]. */
function inKgBounds(n: number): boolean {
  return n > 0 && n <= 1000;
}

/** `payload.lifts` as validated points: the object map `{ "<id>": e1rm }` (preferred) or the
 * legacy array `[{ id, e1rm }]`. Entries with a bad id or an e1rm outside (0, 1000] are skipped. */
function parseLifts(v: unknown): { id: string; e1rm: number }[] {
  const lifts: { id: string; e1rm: number }[] = [];
  if (Array.isArray(v)) {
    for (const entry of v) {
      const e = entry && typeof entry === "object" && !Array.isArray(entry) ? (entry as Record<string, unknown>) : null;
      const id = e && typeof e.id === "string" ? e.id : null;
      const e1rm = e ? finiteNumber(e.e1rm) : null;
      if (id === null || !LIFT_ID_RE.test(id) || e1rm === null || !inKgBounds(e1rm)) continue;
      lifts.push({ id, e1rm });
    }
    return lifts;
  }
  if (v && typeof v === "object") {
    for (const [id, raw] of Object.entries(v)) {
      const e1rm = finiteNumber(raw);
      if (!LIFT_ID_RE.test(id) || e1rm === null || !inKgBounds(e1rm)) continue;
      lifts.push({ id, e1rm });
    }
  }
  return lifts;
}

/** A post's local date: `payload.localDate` when it matches YYYY-MM-DD, else the UTC date of `created_at`. */
export function localDateOf(payload: unknown, createdAt: string): string {
  const ld = payload && typeof payload === "object" && !Array.isArray(payload) ? (payload as Record<string, unknown>).localDate : undefined;
  return typeof ld === "string" && LOCAL_DATE_RE.test(ld) ? ld : createdAt.slice(0, 10);
}

/** Parses one post into a CrewPost; null only when the payload is not valid JSON. */
export function parseCrewPost(post: PostRow): CrewPost | null {
  let payload: unknown;
  try {
    payload = JSON.parse(post.payload);
  } catch {
    return null;
  }
  const o = payload && typeof payload === "object" && !Array.isArray(payload) ? (payload as Record<string, unknown>) : {};
  const lifts = post.type === "session" ? parseLifts(o.lifts) : [];
  let pr: CrewPost["pr"] = null;
  if (post.type === "pr") {
    const reps = finiteNumber(o.reps);
    const weightKg = finiteNumber(o.weightKg);
    const e1rm = finiteNumber(o.e1rm);
    pr = {
      exerciseId: typeof o.exerciseId === "string" && LIFT_ID_RE.test(o.exerciseId) ? o.exerciseId : null,
      exercise: typeof o.exercise === "string" ? o.exercise : "",
      // outside (0, 1000] → null, which drops the record entirely downstream
      e1rm: e1rm !== null && inKgBounds(e1rm) ? e1rm : null,
      weightKg: weightKg !== null && inKgBounds(weightKg) ? weightKg : null,
      reps: reps !== null && Number.isInteger(reps) && reps >= 1 && reps <= 100 ? reps : null,
    };
  }
  return {
    id: post.id,
    userId: post.user_id,
    type: post.type,
    createdAt: post.created_at,
    localDate: localDateOf(o, post.created_at),
    weekTarget: finiteNumber(o.weekTarget),
    lifts,
    pr,
  };
}

/** `target` = the newest session post's numeric weekTarget, rounded and clamped to 1..7; default 3. */
export function crewTarget(posts: CrewPost[]): number {
  const sessions = posts.filter((p) => p.type === "session").sort(byNewest);
  for (const s of sessions) {
    if (s.weekTarget !== null) return Math.min(7, Math.max(1, Math.round(s.weekTarget)));
  }
  return 3;
}

/** Lift lines per exercise id for the given users: last 12 points of the window, deltas vs the first kept point (1 decimal). */
export function crewLifts(posts: CrewPost[], userIds: Set<string>, windowStart: string, windowEnd: string): Map<string, CrewLiftLine[]> {
  const grouped = new Map<string, Map<string, { localDate: string; createdAt: string; e1rm: number }[]>>();
  for (const c of posts) {
    if (c.type !== "session" || !userIds.has(c.userId) || c.localDate < windowStart || c.localDate > windowEnd) continue;
    for (const l of c.lifts) {
      const perUser = grouped.get(l.id) ?? new Map<string, { localDate: string; createdAt: string; e1rm: number }[]>();
      const points = perUser.get(c.userId) ?? [];
      points.push({ localDate: c.localDate, createdAt: c.createdAt, e1rm: l.e1rm });
      perUser.set(c.userId, points);
      grouped.set(l.id, perUser);
    }
  }
  const out = new Map<string, CrewLiftLine[]>();
  for (const [liftId, perUser] of grouped) {
    const lines: CrewLiftLine[] = [];
    for (const [userId, points] of perUser) {
      points.sort((a, b) => cmp3(a.localDate, b.localDate) || cmp3(a.createdAt, b.createdAt));
      const kept = points.slice(-CREW_LIFT_POINTS);
      const deltas = kept.map((p) => Math.round((p.e1rm - kept[0]!.e1rm) * 10) / 10);
      const last = kept[kept.length - 1]!;
      lines.push({
        userId,
        deltas,
        changeKg: deltas[deltas.length - 1]!,
        record: kept.length >= 2 && kept.slice(0, -1).every((p) => p.e1rm < last.e1rm),
        lastDate: last.localDate,
      });
    }
    out.set(liftId, lines);
  }
  return out;
}

/** Consecutive qualifying weeks (max 26): ≥ 2 members active by that week and every one trained in it.
 * `firstDates` (date part of each member's first session post EVER, from `firstSessionDates`)
 * decides when a member starts counting — not the loaded post window. */
export function crewStreak(posts: CrewPost[], firstDates: Map<string, string>, weekKey: string): number {
  const weeks = new Map<string, Set<string>>();
  for (const c of posts) {
    if (c.type !== "session") continue;
    const w = weeks.get(c.userId) ?? new Set<string>();
    w.add(weekKeyOfLocalDate(c.localDate));
    weeks.set(c.userId, w);
  }
  const sundayOf = (key: string): string => {
    const s = isoWeekStart(key)!;
    s.setUTCDate(s.getUTCDate() + 6);
    return s.toISOString().slice(0, 10);
  };
  const qualifies = (key: string): boolean => {
    const sunday = sundayOf(key);
    const counting: string[] = [];
    for (const [id, first] of firstDates) if (first <= sunday) counting.push(id);
    return counting.length >= 2 && counting.every((id) => weeks.get(id)?.has(key) ?? false);
  };
  let cursor = weekKey;
  if (!qualifies(cursor)) cursor = weekShift(cursor, -1); // the requested week may still be in progress
  let streak = 0;
  while (streak < CREW_STREAK_WEEKS && qualifies(cursor)) {
    streak++;
    cursor = weekShift(cursor, -1);
  }
  return streak;
}

function cmp3(a: string, b: string): number {
  return a < b ? -1 : a > b ? 1 : 0;
}

function byNewest(a: CrewPost, b: CrewPost): number {
  return cmp3(b.createdAt, a.createdAt);
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

  if (req.method === "GET" && p === "/social/crew") {
    const week = url.searchParams.get("week") ?? isoWeekKey(now());
    const start = isoWeekStart(week);
    if (!start) return json(400, { error: "week must be YYYY-Www" });
    const dayMs = 86400_000;
    const weekStart = start.toISOString().slice(0, 10);
    const sunday = new Date(start.getTime() + 6 * dayMs);
    const weekSunday = sunday.toISOString().slice(0, 10);
    const inWeek = (d: string) => d >= weekStart && d <= weekSunday;

    // crew = self + followed users, minus any legacy self-follow row, first 50 followed
    const followed = (await q.followedIds(user.id)).filter((id) => id !== user.id).slice(0, CREW_MAX_FOLLOWED);
    const authors = [user.id, ...followed];
    const since = new Date(start.getTime() - CREW_STREAK_WEEKS * 7 * dayMs).toISOString();
    // pr posts: created_at within [Monday − 1 day, Sunday + 2 days) — UTC slack around the
    // week's local dates — then placed by local date in code, so old pr posts never load.
    const prFrom = new Date(start.getTime() - dayMs).toISOString();
    const prTo = new Date(start.getTime() + 8 * dayMs).toISOString();
    const [sessionRows, prRows] = await Promise.all([q.crewSessionPosts(authors, since), q.crewPrPosts(authors, prFrom, prTo)]);
    const posts = [...sessionRows, ...prRows].map(parseCrewPost).filter((c): c is CrewPost => c !== null);
    const firstDates = new Map((await q.firstSessionDates(authors)).map((r) => [r.user_id, r.first.slice(0, 10)]));
    const profileOf = new Map((await q.profilesFor(authors)).map((pr) => [pr.user_id, pr]));

    const byAuthor = new Map<string, CrewPost[]>(authors.map((id) => [id, []]));
    for (const c of posts) byAuthor.get(c.userId)?.push(c);

    const members = authors
      .map((id) => {
        const mine = byAuthor.get(id) ?? [];
        const sessions = mine.filter((c) => c.type === "session" && inWeek(c.localDate));
        const profile = profileOf.get(id);
        return {
          userId: id,
          handle: profile?.handle ?? null,
          displayName: profile?.display_name ?? null,
          isSelf: id === user.id,
          target: crewTarget(mine),
          days: [...new Set(sessions.map((s) => s.localDate))].sort(),
          sessions: sessions.length,
        };
      })
      .sort(
        (a, b) =>
          Number(b.isSelf) - Number(a.isSelf) ||
          cmp3((a.displayName ?? "").toLowerCase(), (b.displayName ?? "").toLowerCase()) ||
          cmp3(a.handle ?? "", b.handle ?? "") ||
          cmp3(a.userId, b.userId),
      );

    const weekPRs = posts
      .filter((c) => c.type === "pr" && c.pr !== null && c.pr.e1rm !== null && inWeek(c.localDate))
      .sort(byNewest);
    const kudosOf = new Map((await q.kudosFor(weekPRs.map((c) => c.id), user.id)).map((k) => [k.post_id, k]));
    const records = weekPRs.map((c) => ({
      postId: c.id,
      userId: c.userId,
      handle: profileOf.get(c.userId)?.handle ?? null,
      displayName: profileOf.get(c.userId)?.display_name ?? null,
      isSelf: c.userId === user.id,
      exerciseId: c.pr!.exerciseId,
      exercise: c.pr!.exercise,
      e1rm: c.pr!.e1rm!,
      weightKg: c.pr!.weightKg,
      reps: c.pr!.reps,
      date: c.localDate,
      kudos: kudosOf.get(c.id)?.kudos ?? 0,
      kudoed: (kudosOf.get(c.id)?.kudoed ?? 0) === 1,
    }));

    // 16 weekly blocks ending on the week's Sunday: Monday of (week − 15) .. Sunday of the week.
    const liftsStart = new Date(sunday.getTime() - (CREW_LIFT_WEEKS * 7 - 1) * dayMs).toISOString().slice(0, 10);
    const lifts = Object.fromEntries(crewLifts(posts, new Set(followed), liftsStart, weekSunday));

    return json(200, { week, weekStart, members, streakWeeks: crewStreak(posts, firstDates, week), records, lifts });
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
