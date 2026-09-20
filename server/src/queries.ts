import { D1DB, MemoryDB, type D1Database } from "./db.js";

export type Tier = "free" | "pro";

export interface UserRow {
  id: string;
  email: string | null;
  apple_sub: string | null;
  google_sub: string | null;
  tier: Tier;
  referral_code: string;
  referred_by: string | null;
  promo_code: string | null;
  created_at: string;
}
export interface SessionRow { token_hash: string; user_id: string; created_at: string; last_seen: string; }
export interface EmailCodeRow { email: string; code_hash: string; expires_at: string; attempts: number; }
export interface RecordRow { seq: number; user_id: string; type: string; id: string; updated_at: string; deleted: number; data: string; }
export interface SubEventRow {
  user_id: string; event: string; product_id: string | null; price: number | null;
  currency: string | null; promo_code: string | null; occurred_at: string; raw: string | null;
}
export interface ReferralRow { referee_id: string; referrer_id: string; redeemed_at: string; rewarded_at: string | null; }
export interface ProfileRow { user_id: string; handle: string; display_name: string; bio: string; updated_at: string; }
export interface FollowRow { follower_id: string; followee_id: string; created_at: string; }
export interface PostRow { id: string; user_id: string; type: string; payload: string; created_at: string; }
export interface KudoRow { post_id: string; user_id: string; created_at: string; }
export interface CommentRow { id: string; post_id: string; user_id: string; text: string; created_at: string; }
export interface FeedRow {
  id: string; user_id: string; handle: string | null; display_name: string | null;
  type: string; payload: string; created_at: string;
  kudos: number; comments: number; kudoed: number;
}
export interface RevshareRow { code: string; subscribers: number; events: number; revenue: number; }

/**
 * Unlisted program share. The payload is write-once (immutable) — only `status`,
 * `revoked_at` and the abuse-report columns may change after insert. Every column is an
 * allowlisted public field; no workout history, loads, health, goals, coach memory,
 * conversations, private notes or raw imported source is ever stored here.
 */
export type ProgramShareStatus = "active" | "revoked" | "flagged";
export interface ProgramShareRow {
  id: string;
  token_hash: string;
  token_prefix: string;
  owner_id: string;
  payload: string;
  payload_hash: string;
  schema_version: number;
  status: ProgramShareStatus;
  created_at: string;
  expires_at: string;
  revoked_at: string | null;
  report_count: number;
  last_reported_at: string | null;
  last_report_reason: string | null;
}

export interface Queries {
  // users
  upsertUserByAppleSub(sub: string, email: string | null, now: string): Promise<UserRow>;
  upsertUserByGoogleSub(sub: string, email: string | null, now: string): Promise<UserRow>;
  upsertUserByEmail(email: string, now: string): Promise<UserRow>;
  getUserById(id: string): Promise<UserRow | null>;
  getUserByReferralCode(code: string): Promise<UserRow | null>;
  setReferredBy(userId: string, referrerId: string): Promise<void>;
  setPromoCode(userId: string, promoCode: string): Promise<void>;
  setTier(userId: string, tier: Tier): Promise<void>;
  deleteUser(userId: string): Promise<void>;
  // sessions
  insertSession(tokenHash: string, userId: string, now: string): Promise<void>;
  getSessionByHash(tokenHash: string): Promise<SessionRow | null>;
  touchSession(tokenHash: string, now: string): Promise<void>;
  deleteSession(tokenHash: string): Promise<void>;
  // email codes
  upsertEmailCode(email: string, codeHash: string, expiresAt: string): Promise<void>;
  getEmailCode(email: string): Promise<EmailCodeRow | null>;
  incrementCodeAttempts(email: string): Promise<void>;
  deleteEmailCode(email: string): Promise<void>;
  // sync records (last-writer-wins per (type, id) by updated_at)
  applyChange(userId: string, type: string, id: string, updatedAt: string, deleted: boolean, data: string): Promise<boolean>;
  recordsSince(userId: string, cursor: number): Promise<RecordRow[]>;
  maxSeq(userId: string): Promise<number>;
  // subscription events
  insertSubscriptionEvent(e: SubEventRow): Promise<void>;
  revshareByCode(month: string): Promise<RevshareRow[]>;
  // referrals
  insertReferral(refereeId: string, referrerId: string, now: string): Promise<void>;
  getReferralByReferee(refereeId: string): Promise<ReferralRow | null>;
  markReferralRewarded(refereeId: string, at: string): Promise<void>;
  referralCounts(referrerId: string): Promise<{ referred: number; rewarded: number }>;
  // coach usage
  getCoachUsage(userId: string, day: string): Promise<number>;
  incrementCoachUsage(userId: string, day: string): Promise<void>;
  // social
  getProfile(userId: string): Promise<ProfileRow | null>;
  getProfileByHandle(handle: string): Promise<ProfileRow | null>;
  upsertProfile(userId: string, handle: string, displayName: string, bio: string, now: string): Promise<ProfileRow>;
  insertFollow(followerId: string, followeeId: string, now: string): Promise<void>;
  deleteFollow(followerId: string, followeeId: string): Promise<void>;
  followedIds(followerId: string): Promise<string[]>;
  isFollowing(followerId: string, followeeId: string): Promise<boolean>;
  insertPost(id: string, userId: string, type: string, payload: string, now: string): Promise<void>;
  getPost(postId: string): Promise<PostRow | null>;
  feedPosts(authors: string[], cursor: string | null, limit: number, viewerId: string): Promise<FeedRow[]>;
  addKudos(postId: string, userId: string, now: string): Promise<void>;
  removeKudos(postId: string, userId: string): Promise<void>;
  insertComment(id: string, postId: string, userId: string, text: string, now: string): Promise<void>;
  commentsForPost(postId: string, limit: number): Promise<CommentRow[]>;
  userPosts(userId: string): Promise<PostRow[]>;
  postsForWeek(authors: string[], fromISO: string, toISO: string): Promise<PostRow[]>;
  profilesFor(userIds: string[]): Promise<ProfileRow[]>;
  // program shares (unlisted bearer links; immutable payload, owner lifecycle)
  insertProgramShare(row: ProgramShareRow): Promise<void>;
  getProgramShareByTokenHash(tokenHash: string): Promise<ProgramShareRow | null>;
  getProgramShareById(id: string): Promise<ProgramShareRow | null>;
  revokeProgramShare(id: string, ownerId: string, at: string): Promise<boolean>;
  reportProgramShare(tokenHash: string, reason: string, at: string, threshold: number): Promise<ProgramShareRow | null>;
  /** Live shares owned by `ownerId`: status active AND expires_at strictly after `now`. */
  countActiveProgramShares(ownerId: string, now: string): Promise<number>;
}

const B32 = "abcdefghijklmnopqrstuvwxyz234567";

function randomReferralCode(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(8));
  let out = "";
  for (const b of bytes) out += B32[b % 32];
  return out;
}

export function d1Queries(d1: D1Database): Queries {
  const db = new D1DB(d1);

  const findUserBy = async (sql: string, param: string): Promise<UserRow | null> =>
    db.get<UserRow>(sql, param);

  const createUser = async (
    cols: { email: string | null; apple_sub?: string | null; google_sub?: string | null },
    now: string,
  ): Promise<UserRow> => {
    const id = crypto.randomUUID();
    // ponytail: pre-check referral-code uniqueness; the UNIQUE index still guards races
    let code = randomReferralCode();
    for (let i = 0; i < 8 && (await db.get("SELECT id FROM users WHERE referral_code = ?", code)); i++) {
      code = randomReferralCode();
    }
    await db.run(
      "INSERT INTO users(id, email, apple_sub, google_sub, referral_code, created_at) VALUES(?,?,?,?,?,?)",
      id, cols.email, cols.apple_sub ?? null, cols.google_sub ?? null, code, now,
    );
    return (await db.get<UserRow>("SELECT * FROM users WHERE id = ?", id))!;
  };

  const upsertBySub = async (
    subCol: "apple_sub" | "google_sub",
    sub: string,
    email: string | null,
    now: string,
  ): Promise<UserRow> => {
    const existing = await findUserBy(`SELECT * FROM users WHERE ${subCol} = ?`, sub);
    if (existing) {
      if (email && existing.email !== email) {
        await db.run("UPDATE users SET email = ? WHERE id = ?", email, existing.id);
        existing.email = email;
      }
      return existing;
    }
    return createUser({ email, [subCol]: sub }, now);
  };

  return {
    upsertUserByAppleSub: (sub, email, now) => upsertBySub("apple_sub", sub, email, now),
    upsertUserByGoogleSub: (sub, email, now) => upsertBySub("google_sub", sub, email, now),
    async upsertUserByEmail(email, now) {
      const existing = await db.get<UserRow>("SELECT * FROM users WHERE email = ?", email);
      return existing ?? createUser({ email }, now);
    },
    getUserById: (id) => db.get<UserRow>("SELECT * FROM users WHERE id = ?", id),
    getUserByReferralCode: (code) => db.get<UserRow>("SELECT * FROM users WHERE referral_code = ?", code),
    setReferredBy: (userId, referrerId) => db.run("UPDATE users SET referred_by = ? WHERE id = ?", referrerId, userId),
    setPromoCode: (userId, promoCode) => db.run("UPDATE users SET promo_code = ? WHERE id = ?", promoCode, userId),
    setTier: (userId, tier) => db.run("UPDATE users SET tier = ? WHERE id = ?", tier, userId),
    async deleteUser(userId) {
      const user = await db.get<UserRow>("SELECT * FROM users WHERE id = ?", userId);
      if (!user) return;
      // ponytail: sequential deletes; use db.batch() if account deletion becomes hot
      if (user.email) await db.run("DELETE FROM email_codes WHERE email = ?", user.email);
      await db.run("DELETE FROM coach_usage WHERE user_id = ?", userId);
      await db.run("DELETE FROM auth_sessions WHERE user_id = ?", userId);
      await db.run("DELETE FROM records WHERE user_id = ?", userId);
      await db.run("DELETE FROM subscription_events WHERE user_id = ?", userId);
      await db.run("DELETE FROM referrals WHERE referee_id = ? OR referrer_id = ?", userId, userId);
      await db.run("DELETE FROM profiles WHERE user_id = ?", userId);
      await db.run("DELETE FROM follows WHERE follower_id = ? OR followee_id = ?", userId, userId);
      await db.run("DELETE FROM kudos WHERE user_id = ?", userId);
      await db.run("DELETE FROM comments WHERE user_id = ?", userId);
      await db.run("DELETE FROM posts WHERE user_id = ?", userId);
      await db.run("DELETE FROM program_shares WHERE owner_id = ?", userId);
      await db.run("DELETE FROM users WHERE id = ?", userId);
    },
    insertSession: (tokenHash, userId, now) =>
      db.run("INSERT INTO auth_sessions(token_hash, user_id, created_at, last_seen) VALUES(?,?,?,?)", tokenHash, userId, now, now),
    getSessionByHash: (tokenHash) => db.get<SessionRow>("SELECT * FROM auth_sessions WHERE token_hash = ?", tokenHash),
    touchSession: (tokenHash, now) => db.run("UPDATE auth_sessions SET last_seen = ? WHERE token_hash = ?", now, tokenHash),
    deleteSession: (tokenHash) => db.run("DELETE FROM auth_sessions WHERE token_hash = ?", tokenHash),
    upsertEmailCode: (email, codeHash, expiresAt) =>
      db.run(
        "INSERT INTO email_codes(email, code_hash, expires_at, attempts) VALUES(?,?,?,0) " +
          "ON CONFLICT(email) DO UPDATE SET code_hash = excluded.code_hash, expires_at = excluded.expires_at, attempts = 0",
        email, codeHash, expiresAt,
      ),
    getEmailCode: (email) => db.get<EmailCodeRow>("SELECT * FROM email_codes WHERE email = ?", email),
    incrementCodeAttempts: (email) => db.run("UPDATE email_codes SET attempts = attempts + 1 WHERE email = ?", email),
    deleteEmailCode: (email) => db.run("DELETE FROM email_codes WHERE email = ?", email),
    async applyChange(userId, type, id, updatedAt, deleted, data) {
      // Atomic LWW upsert that bumps seq on every accepted write (contract: every accepted
      // write gets a new seq) — meta.changes is 0 when the WHERE filtered an older/equal row.
      // ponytail: updated_at compared lexically — ISO strings must share one format/precision
      const r = await d1
        .prepare(
          "INSERT INTO records(user_id, type, id, updated_at, deleted, data) VALUES(?,?,?,?,?,?) " +
            "ON CONFLICT(user_id, type, id) DO UPDATE SET " +
            "seq = (SELECT IFNULL(MAX(s.seq),0)+1 FROM records s), " +
            "updated_at = excluded.updated_at, deleted = excluded.deleted, data = excluded.data " +
            "WHERE excluded.updated_at > records.updated_at",
        )
        .bind(userId, type, id, updatedAt, deleted ? 1 : 0, data)
        .run();
      return (r.meta?.changes ?? 0) > 0;
    },
    recordsSince: (userId, cursor) =>
      db.all<RecordRow>("SELECT * FROM records WHERE user_id = ? AND seq > ? ORDER BY seq", userId, cursor),
    async maxSeq(userId) {
      const row = await db.get<{ m: number }>("SELECT COALESCE(MAX(seq), 0) AS m FROM records WHERE user_id = ?", userId);
      return row?.m ?? 0;
    },
    insertSubscriptionEvent: (e) =>
      db.run(
        "INSERT INTO subscription_events(user_id, event, product_id, price, currency, promo_code, occurred_at, raw) VALUES(?,?,?,?,?,?,?,?)",
        e.user_id, e.event, e.product_id, e.price, e.currency, e.promo_code, e.occurred_at, e.raw,
      ),
    revshareByCode: (month) =>
      db.all<RevshareRow>(
        "SELECT promo_code AS code, COUNT(DISTINCT user_id) AS subscribers, COUNT(*) AS events, COALESCE(SUM(price), 0) AS revenue " +
          "FROM subscription_events WHERE event IN ('INITIAL_PURCHASE','RENEWAL') AND promo_code IS NOT NULL AND occurred_at LIKE ? " +
          "GROUP BY promo_code ORDER BY revenue DESC",
        `${month}-%`,
      ),
    insertReferral: (refereeId, referrerId, now) =>
      db.run("INSERT INTO referrals(referee_id, referrer_id, redeemed_at) VALUES(?,?,?)", refereeId, referrerId, now),
    getReferralByReferee: (refereeId) => db.get<ReferralRow>("SELECT * FROM referrals WHERE referee_id = ?", refereeId),
    markReferralRewarded: (refereeId, at) => db.run("UPDATE referrals SET rewarded_at = ? WHERE referee_id = ?", at, refereeId),
    async referralCounts(referrerId) {
      const row = await db.get<{ referred: number; rewarded: number }>(
        "SELECT COUNT(*) AS referred, COALESCE(SUM(rewarded_at IS NOT NULL), 0) AS rewarded FROM referrals WHERE referrer_id = ?",
        referrerId,
      );
      return row ?? { referred: 0, rewarded: 0 };
    },
    getCoachUsage: async (userId, day) =>
      (await db.get<{ count: number }>("SELECT count FROM coach_usage WHERE user_id = ? AND day = ?", userId, day))?.count ?? 0,
    incrementCoachUsage: (userId, day) =>
      db.run(
        "INSERT INTO coach_usage(user_id, day, count) VALUES(?,?,1) ON CONFLICT(user_id, day) DO UPDATE SET count = count + 1",
        userId, day,
      ),
    // social
    getProfile: (userId) => db.get<ProfileRow>("SELECT * FROM profiles WHERE user_id = ?", userId),
    getProfileByHandle: (handle) => db.get<ProfileRow>("SELECT * FROM profiles WHERE handle = ?", handle),
    async upsertProfile(userId, handle, displayName, bio, iso) {
      await db.run(
        "INSERT INTO profiles(user_id, handle, display_name, bio, updated_at) VALUES(?,?,?,?,?) " +
          "ON CONFLICT(user_id) DO UPDATE SET handle = excluded.handle, display_name = excluded.display_name, bio = excluded.bio, updated_at = excluded.updated_at",
        userId, handle, displayName, bio, iso,
      );
      return (await db.get<ProfileRow>("SELECT * FROM profiles WHERE user_id = ?", userId))!;
    },
    insertFollow: (followerId, followeeId, iso) =>
      db.run("INSERT OR IGNORE INTO follows(follower_id, followee_id, created_at) VALUES(?,?,?)", followerId, followeeId, iso),
    deleteFollow: (followerId, followeeId) =>
      db.run("DELETE FROM follows WHERE follower_id = ? AND followee_id = ?", followerId, followeeId),
    followedIds: async (followerId) =>
      (await db.all<{ followee_id: string }>("SELECT followee_id FROM follows WHERE follower_id = ?", followerId)).map((r) => r.followee_id),
    isFollowing: async (followerId, followeeId) =>
      !!(await db.get("SELECT 1 FROM follows WHERE follower_id = ? AND followee_id = ?", followerId, followeeId)),
    insertPost: (id, userId, type, payload, iso) =>
      db.run("INSERT INTO posts(id, user_id, type, payload, created_at) VALUES(?,?,?,?,?)", id, userId, type, payload, iso),
    getPost: (postId) => db.get<PostRow>("SELECT * FROM posts WHERE id = ?", postId),
    feedPosts: (authors, cursor, limit, viewerId) =>
      db.all<FeedRow>(
        "SELECT p.id, p.user_id, pr.handle, pr.display_name, p.type, p.payload, p.created_at, " +
          "(SELECT COUNT(*) FROM kudos k WHERE k.post_id = p.id) AS kudos, " +
          "(SELECT COUNT(*) FROM comments c WHERE c.post_id = p.id) AS comments, " +
          "EXISTS(SELECT 1 FROM kudos k2 WHERE k2.post_id = p.id AND k2.user_id = ?) AS kudoed " +
          "FROM posts p LEFT JOIN profiles pr ON pr.user_id = p.user_id " +
          `WHERE p.user_id IN (${authors.map(() => "?").join(",")}) ${cursor ? "AND p.created_at < ? " : ""}` +
          "ORDER BY p.created_at DESC, p.rowid DESC LIMIT ?",
        viewerId, ...authors, ...(cursor ? [cursor] : []), limit,
      ),
    addKudos: (postId, userId, iso) =>
      db.run("INSERT OR IGNORE INTO kudos(post_id, user_id, created_at) VALUES(?,?,?)", postId, userId, iso),
    removeKudos: (postId, userId) => db.run("DELETE FROM kudos WHERE post_id = ? AND user_id = ?", postId, userId),
    insertComment: (id, postId, userId, text, iso) =>
      db.run("INSERT INTO comments(id, post_id, user_id, text, created_at) VALUES(?,?,?,?,?)", id, postId, userId, text, iso),
    commentsForPost: (postId, limit) =>
      db.all<CommentRow>("SELECT * FROM comments WHERE post_id = ? ORDER BY created_at ASC, rowid ASC LIMIT ?", postId, limit),
    userPosts: (userId) => db.all<PostRow>("SELECT * FROM posts WHERE user_id = ?", userId),
    postsForWeek: (authors, fromISO, toISO) =>
      db.all<PostRow>(
        `SELECT * FROM posts WHERE type = 'session' AND user_id IN (${authors.map(() => "?").join(",")}) AND created_at >= ? AND created_at < ?`,
        ...authors, fromISO, toISO,
      ),
    profilesFor: (userIds) =>
      userIds.length
        ? db.all<ProfileRow>(`SELECT * FROM profiles WHERE user_id IN (${userIds.map(() => "?").join(",")})`, ...userIds)
        : Promise.resolve([]),
      // Program shares: insert-only payload (`token_hash` UNIQUE ⇒ a duplicate throws),
      // so a retry can never silently overwrite someone else's share.
    insertProgramShare: (r) =>
      db.run(
        "INSERT INTO program_shares(id, token_hash, token_prefix, owner_id, payload, payload_hash, schema_version, status, created_at, expires_at, revoked_at, report_count, last_reported_at, last_report_reason) " +
          "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        r.id, r.token_hash, r.token_prefix, r.owner_id, r.payload, r.payload_hash, r.schema_version,
        r.status, r.created_at, r.expires_at, r.revoked_at, r.report_count, r.last_reported_at, r.last_report_reason,
      ),
    getProgramShareByTokenHash: (tokenHash) =>
      db.get<ProgramShareRow>("SELECT * FROM program_shares WHERE token_hash = ?", tokenHash),
    getProgramShareById: (id) => db.get<ProgramShareRow>("SELECT * FROM program_shares WHERE id = ?", id),
    async revokeProgramShare(id, ownerId, at) {
      const r = await d1
        .prepare("UPDATE program_shares SET status = 'revoked', revoked_at = ? WHERE id = ? AND owner_id = ? AND status != 'revoked'")
        .bind(at, id, ownerId)
        .run();
      return (r.meta?.changes ?? 0) > 0;
    },
    async reportProgramShare(tokenHash, reason, at, _threshold) {
      await db.run(
        "UPDATE program_shares SET report_count = report_count + 1, last_reported_at = ?, last_report_reason = ? WHERE token_hash = ?",
        at, reason, tokenHash,
      );
      return db.get<ProgramShareRow>("SELECT * FROM program_shares WHERE token_hash = ?", tokenHash);
    },
    async countActiveProgramShares(ownerId, now) {
      const row = await db.get<{ n: number }>(
        "SELECT COUNT(*) AS n FROM program_shares WHERE owner_id = ? AND status = 'active' AND expires_at > ?",
        ownerId, now,
      );
      return row?.n ?? 0;
    },
  };
}

export function memoryQueries(): Queries {
  const m = new MemoryDB();
  const findUser = (pred: (u: UserRow) => boolean): UserRow | null => {
    for (const u of m.users.values()) if (pred(u)) return u;
    return null;
  };
  const mkUser = (
    cols: { email: string | null; apple_sub?: string | null; google_sub?: string | null },
    now: string,
  ): UserRow => {
    let code = randomReferralCode();
    while (findUser((u) => u.referral_code === code)) code = randomReferralCode();
    const u: UserRow = {
      id: crypto.randomUUID(), email: cols.email, apple_sub: cols.apple_sub ?? null, google_sub: cols.google_sub ?? null,
      tier: "free", referral_code: code, referred_by: null, promo_code: null, created_at: now,
    };
    m.users.set(u.id, u);
    return u;
  };
  const upsertBySub = (subCol: "apple_sub" | "google_sub", sub: string, email: string | null, now: string): UserRow => {
    const existing = findUser((u) => u[subCol] === sub);
    if (existing) {
      if (email && existing.email !== email) existing.email = email;
      return existing;
    }
    return mkUser({ email, [subCol]: sub }, now);
  };

  return {
    upsertUserByAppleSub: (sub, email, now) => Promise.resolve(upsertBySub("apple_sub", sub, email, now)),
    upsertUserByGoogleSub: (sub, email, now) => Promise.resolve(upsertBySub("google_sub", sub, email, now)),
    upsertUserByEmail: (email, now) =>
      Promise.resolve(findUser((u) => u.email === email) ?? mkUser({ email }, now)),
    getUserById: (id) => Promise.resolve(m.users.get(id) ?? null),
    getUserByReferralCode: (code) => Promise.resolve(findUser((u) => u.referral_code === code)),
    setReferredBy: (userId, referrerId) => {
      const u = m.users.get(userId);
      if (u) u.referred_by = referrerId;
      return Promise.resolve();
    },
    setPromoCode: (userId, promoCode) => {
      const u = m.users.get(userId);
      if (u) u.promo_code = promoCode;
      return Promise.resolve();
    },
    setTier: (userId, tier) => {
      const u = m.users.get(userId);
      if (u) u.tier = tier;
      return Promise.resolve();
    },
    deleteUser(userId) {
      const u = m.users.get(userId);
      if (!u) return Promise.resolve();
      if (u.email) m.emailCodes.delete(u.email);
      for (const [k, s] of m.sessions) if (s.user_id === userId) m.sessions.delete(k);
      for (const [k, r] of m.records) if (r.user_id === userId) m.records.delete(k);
      m.subscriptionEvents = m.subscriptionEvents.filter((e) => e.user_id !== userId);
      for (const [k, r] of m.referrals) if (r.referee_id === userId || r.referrer_id === userId) m.referrals.delete(k);
      for (const [k] of m.coachUsage) if (k.startsWith(`${userId}|`)) m.coachUsage.delete(k);
      m.profiles.delete(userId);
      for (const [k, f] of m.follows) if (f.follower_id === userId || f.followee_id === userId) m.follows.delete(k);
      for (const [k, p] of m.posts) if (p.user_id === userId) m.posts.delete(k);
      for (const [k, ku] of m.kudos) if (ku.user_id === userId) m.kudos.delete(k);
      m.comments = m.comments.filter((c) => c.user_id !== userId);
      for (const [k, s] of m.programShares) if (s.owner_id === userId) m.programShares.delete(k);
      m.users.delete(userId);
      return Promise.resolve();
    },
    insertSession: (tokenHash, userId, now) => {
      m.sessions.set(tokenHash, { token_hash: tokenHash, user_id: userId, created_at: now, last_seen: now });
      return Promise.resolve();
    },
    getSessionByHash: (tokenHash) => Promise.resolve(m.sessions.get(tokenHash) ?? null),
    touchSession: (tokenHash, now) => {
      const s = m.sessions.get(tokenHash);
      if (s) s.last_seen = now;
      return Promise.resolve();
    },
    deleteSession: (tokenHash) => {
      m.sessions.delete(tokenHash);
      return Promise.resolve();
    },
    upsertEmailCode: (email, codeHash, expiresAt) => {
      m.emailCodes.set(email, { email, code_hash: codeHash, expires_at: expiresAt, attempts: 0 });
      return Promise.resolve();
    },
    getEmailCode: (email) => Promise.resolve(m.emailCodes.get(email) ?? null),
    incrementCodeAttempts: (email) => {
      const c = m.emailCodes.get(email);
      if (c) c.attempts++;
      return Promise.resolve();
    },
    deleteEmailCode: (email) => {
      m.emailCodes.delete(email);
      return Promise.resolve();
    },
    applyChange(userId, type, id, updatedAt, deleted, data) {
      const key = `${userId}|${type}|${id}`;
      const cur = m.records.get(key);
      // lexical compare mirrors the D1 implementation
      if (cur && !(updatedAt > cur.updated_at)) return Promise.resolve(false);
      m.records.set(key, { seq: ++m.nextSeq, user_id: userId, type, id, updated_at: updatedAt, deleted: deleted ? 1 : 0, data });
      return Promise.resolve(true);
    },
    recordsSince(userId, cursor) {
      return Promise.resolve(
        [...m.records.values()].filter((r) => r.user_id === userId && r.seq > cursor).sort((a, b) => a.seq - b.seq),
      );
    },
    maxSeq(userId) {
      return Promise.resolve([...m.records.values()].filter((r) => r.user_id === userId).reduce((mx, r) => Math.max(mx, r.seq), 0));
    },
    insertSubscriptionEvent(e) {
      m.subscriptionEvents.push(e);
      return Promise.resolve();
    },
    revshareByCode(month) {
      const byCode = new Map<string, { subscribers: Set<string>; events: number; revenue: number }>();
      for (const e of m.subscriptionEvents) {
        if (!e.promo_code) continue;
        if (e.event !== "INITIAL_PURCHASE" && e.event !== "RENEWAL") continue;
        if (!e.occurred_at.startsWith(month)) continue;
        const g = byCode.get(e.promo_code) ?? { subscribers: new Set<string>(), events: 0, revenue: 0 };
        g.subscribers.add(e.user_id);
        g.events++;
        g.revenue += e.price ?? 0;
        byCode.set(e.promo_code, g);
      }
      return Promise.resolve(
        [...byCode]
          .map(([code, g]) => ({ code, subscribers: g.subscribers.size, events: g.events, revenue: g.revenue }))
          .sort((a, b) => b.revenue - a.revenue),
      );
    },
    insertReferral(refereeId, referrerId, now) {
      m.referrals.set(refereeId, { referee_id: refereeId, referrer_id: referrerId, redeemed_at: now, rewarded_at: null });
      return Promise.resolve();
    },
    getReferralByReferee: (refereeId) => Promise.resolve(m.referrals.get(refereeId) ?? null),
    markReferralRewarded: (refereeId, at) => {
      const r = m.referrals.get(refereeId);
      if (r) r.rewarded_at = at;
      return Promise.resolve();
    },
    referralCounts(referrerId) {
      let referred = 0;
      let rewarded = 0;
      for (const r of m.referrals.values()) {
        if (r.referrer_id !== referrerId) continue;
        referred++;
        if (r.rewarded_at) rewarded++;
      }
      return Promise.resolve({ referred, rewarded });
    },
    getCoachUsage: (userId, day) => Promise.resolve(m.coachUsage.get(`${userId}|${day}`) ?? 0),
    incrementCoachUsage(userId, day) {
      const key = `${userId}|${day}`;
      m.coachUsage.set(key, (m.coachUsage.get(key) ?? 0) + 1);
      return Promise.resolve();
    },
    // social
    getProfile: (userId) => Promise.resolve(m.profiles.get(userId) ?? null),
    getProfileByHandle: (handle) => {
      for (const pr of m.profiles.values()) if (pr.handle === handle) return Promise.resolve(pr);
      return Promise.resolve(null);
    },
    upsertProfile(userId, handle, displayName, bio, iso) {
      const existing = m.profiles.get(userId);
      const row: ProfileRow = { user_id: userId, handle, display_name: displayName, bio, updated_at: iso };
      m.profiles.set(userId, existing ? Object.assign(existing, row) : row);
      return Promise.resolve(m.profiles.get(userId)!);
    },
    insertFollow(followerId, followeeId, iso) {
      m.follows.set(`${followerId}|${followeeId}`, { follower_id: followerId, followee_id: followeeId, created_at: iso });
      return Promise.resolve();
    },
    deleteFollow(followerId, followeeId) {
      m.follows.delete(`${followerId}|${followeeId}`);
      return Promise.resolve();
    },
    followedIds: (followerId) =>
      Promise.resolve([...m.follows.values()].filter((f) => f.follower_id === followerId).map((f) => f.followee_id)),
    isFollowing: (followerId, followeeId) => Promise.resolve(m.follows.has(`${followerId}|${followeeId}`)),
    insertPost(id, userId, type, payload, iso) {
      m.posts.set(id, { id, user_id: userId, type, payload, created_at: iso });
      return Promise.resolve();
    },
    getPost: (postId) => Promise.resolve(m.posts.get(postId) ?? null),
    feedPosts(authors, cursor, limit, viewerId) {
      const authorSet = new Set(authors);
      const entries = [...m.posts.entries()].map(([i, p], idx) => ({ p, idx, i })); // idx = insertion order, mirrors D1 rowid
      const rows = entries
        .filter(({ p }) => authorSet.has(p.user_id) && (cursor === null || p.created_at < cursor))
        .sort((a, b) => (a.p.created_at < b.p.created_at ? 1 : a.p.created_at > b.p.created_at ? -1 : b.idx - a.idx))
        .slice(0, limit)
        .map(({ p, i }) => {
          const profile = m.profiles.get(p.user_id);
          let kudos = 0;
          let kudoed = 0;
          for (const k of m.kudos.values()) {
            if (k.post_id !== i) continue;
            kudos++;
            if (k.user_id === viewerId) kudoed = 1;
          }
          const comments = m.comments.filter((c) => c.post_id === i).length;
          return { id: p.id, user_id: p.user_id, handle: profile?.handle ?? null, display_name: profile?.display_name ?? null, type: p.type, payload: p.payload, created_at: p.created_at, kudos, comments, kudoed };
        });
      return Promise.resolve(rows);
    },
    addKudos(postId, userId, iso) {
      m.kudos.set(`${postId}|${userId}`, { post_id: postId, user_id: userId, created_at: iso });
      return Promise.resolve();
    },
    removeKudos(postId, userId) {
      m.kudos.delete(`${postId}|${userId}`);
      return Promise.resolve();
    },
    insertComment(id, postId, userId, text, iso) {
      m.comments.push({ id, post_id: postId, user_id: userId, text, created_at: iso });
      return Promise.resolve();
    },
    commentsForPost: (postId, limit) =>
      Promise.resolve(m.comments.filter((c) => c.post_id === postId).slice(0, limit)), // array order = oldest first
    userPosts: (userId) => Promise.resolve([...m.posts.values()].filter((p) => p.user_id === userId)),
    postsForWeek: (authors, fromISO, toISO) =>
      Promise.resolve(
        [...m.posts.values()].filter(
          (p) => p.type === "session" && authors.includes(p.user_id) && p.created_at >= fromISO && p.created_at < toISO,
        ),
      ),
    profilesFor: (userIds) => Promise.resolve(userIds.flatMap((id) => { const pr = m.profiles.get(id); return pr ? [pr] : []; })),
      // Program shares: mirror the D1 UNIQUE(token_hash) constraint so duplicate inserts throw.
      async insertProgramShare(r) {
      for (const s of m.programShares.values()) {
        if (s.token_hash === r.token_hash) throw new Error("UNIQUE constraint failed: program_shares.token_hash");
      }
      // Stored as a copy: the payload string is immutable once written.
      m.programShares.set(r.id, { ...r });
      return Promise.resolve();
    },
    getProgramShareByTokenHash(tokenHash) {
      for (const s of m.programShares.values()) if (s.token_hash === tokenHash) return Promise.resolve({ ...s });
      return Promise.resolve(null);
    },
    getProgramShareById: (id) => Promise.resolve(m.programShares.get(id) ? { ...m.programShares.get(id)! } : null),
    revokeProgramShare(id, ownerId, at) {
      const s = m.programShares.get(id);
      if (!s || s.owner_id !== ownerId || s.status === "revoked") return Promise.resolve(false);
      s.status = "revoked";
      s.revoked_at = at;
      return Promise.resolve(true);
    },
    reportProgramShare(tokenHash, reason, at, _threshold) {
      let found: ProgramShareRow | null = null;
      for (const s of m.programShares.values()) if (s.token_hash === tokenHash) found = s;
      if (!found) return Promise.resolve(null);
      found.report_count += 1;
      found.last_reported_at = at;
      found.last_report_reason = reason;
      return Promise.resolve({ ...found });
    },
    // Owner-scoped cap query, mirroring the D1 `expires_at > now` lexical ISO comparison.
    countActiveProgramShares: (ownerId, now) =>
      Promise.resolve(
        [...m.programShares.values()].filter(
          (s) => s.owner_id === ownerId && s.status === "active" && s.expires_at > now,
        ).length,
      ),
  };
}
