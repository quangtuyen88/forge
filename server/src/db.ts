import type { CommentRow, EmailCodeRow, FeedRow, FollowRow, KudoRow, PostRow, ProfileRow, ProgramShareRow, RecordRow, ReferralRow, SessionRow, SubEventRow, UserRow } from "./queries.js";

/**
 * Minimal D1 binding surface (avoids adding @cloudflare/workers-types).
 * Structurally compatible with the real binding.
 */
export interface D1Database {
  prepare(sql: string): D1PreparedStatement;
}
export interface D1PreparedStatement {
  bind(...params: unknown[]): D1PreparedStatement;
  first<T = unknown>(): Promise<T | null>;
  all<T = unknown>(): Promise<{ results: T[] }>;
  run(): Promise<{ meta?: { changes?: number } }>;
}

/** The generic storage surface: positional-parameter statements only. */
export interface DB {
  run(sql: string, ...params: unknown[]): Promise<void>;
  get<T>(sql: string, ...params: unknown[]): Promise<T | null>;
  all<T>(sql: string, ...params: unknown[]): Promise<T[]>;
}

export class D1DB implements DB {
  constructor(private d1: D1Database) {}
  async run(sql: string, ...params: unknown[]): Promise<void> {
    await this.d1.prepare(sql).bind(...params).run();
  }
  async get<T>(sql: string, ...params: unknown[]): Promise<T | null> {
    return (await this.d1.prepare(sql).bind(...params).first()) as T | null;
  }
  async all<T>(sql: string, ...params: unknown[]): Promise<T[]> {
    const r = await this.d1.prepare(sql).bind(...params).all<T>();
    return r.results;
  }
}

/** In-memory Maps backing memoryQueries(). Not a SQL engine — named queries live in queries.ts. */
export class MemoryDB {
  readonly users = new Map<string, UserRow>();
  readonly sessions = new Map<string, SessionRow>();
  readonly emailCodes = new Map<string, EmailCodeRow>();
  /** key: `${user_id}|${type}|${id}` */
  readonly records = new Map<string, RecordRow>();
  subscriptionEvents: SubEventRow[] = [];
  /** key: referee_id */
  readonly referrals = new Map<string, ReferralRow>();
  /** key: `${user_id}|${day}` */
  readonly coachUsage = new Map<string, number>();
  nextSeq = 0;
  // social
  /** key: user_id */
  readonly profiles = new Map<string, ProfileRow>();
  /** key: `${follower_id}|${followee_id}` */
  readonly follows = new Map<string, FollowRow>();
  /** key: post id (Map preserves insertion order — mirrors D1 rowid for tie-breaks) */
  readonly posts = new Map<string, PostRow>();
  /** key: `${post_id}|${user_id}` */
  readonly kudos = new Map<string, KudoRow>();
  comments: CommentRow[] = [];
  /** key: program share id (immutable payload; only status/report columns ever change) */
  readonly programShares = new Map<string, ProgramShareRow>();
}
