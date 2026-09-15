import type { Queries, RecordRow, UserRow } from "./queries.js";
import { json } from "./http.js";

export const SYNC_TYPES = new Set(["profile", "session", "checkin", "measurement", "nutrition"]);
export const MAX_CHANGES = 500;
export const MAX_DATA_BYTES = 64 * 1024;

export interface SyncChange {
  type: string;
  id: string;
  updatedAt: string;
  deleted?: boolean;
  data: Record<string, unknown>;
}

export function validateChanges(raw: unknown): { error: string } | { changes: SyncChange[] } {
  if (!Array.isArray(raw)) return { error: "changes must be an array" };
  if (raw.length > MAX_CHANGES) return { error: `too many changes (max ${MAX_CHANGES})` };
  const out: SyncChange[] = [];
  for (const c of raw) {
    if (!c || typeof c !== "object" || Array.isArray(c)) return { error: "invalid change" };
    const ch = c as Record<string, unknown>;
    if (typeof ch.type !== "string" || !SYNC_TYPES.has(ch.type)) return { error: `invalid type: ${String(ch.type)}` };
    if (typeof ch.id !== "string" || !ch.id || ch.id.length > 64) return { error: "id must be 1-64 chars" };
    if (typeof ch.updatedAt !== "string" || !Number.isFinite(Date.parse(ch.updatedAt))) {
      return { error: "updatedAt must be ISO 8601" };
    }
    if (!ch.data || typeof ch.data !== "object" || Array.isArray(ch.data)) return { error: "data must be an object" };
    if (JSON.stringify(ch.data).length > MAX_DATA_BYTES) return { error: `data too large (max ${MAX_DATA_BYTES} bytes)` };
    if (ch.deleted !== undefined && typeof ch.deleted !== "boolean") return { error: "deleted must be a boolean" };
    out.push({ type: ch.type, id: ch.id, updatedAt: ch.updatedAt, deleted: ch.deleted === true, data: ch.data as Record<string, unknown> });
  }
  return { changes: out };
}

export function recordToChange(r: RecordRow): SyncChange {
  return { type: r.type, id: r.id, updatedAt: r.updated_at, deleted: r.deleted === 1, data: JSON.parse(r.data) };
}

/**
 * POST /sync per contract: LWW push of `changes`, then pull everything with seq > cursor
 * excluding the ids accepted from this request (rejected ids come back so the device
 * learns the newer server version).
 */
export async function syncHandler(queries: Queries, user: UserRow, body: unknown, now: Date): Promise<Response> {
  const b = (body ?? {}) as Record<string, unknown>;
  const cursor = typeof b.cursor === "number" && Number.isInteger(b.cursor) && b.cursor >= 0 ? b.cursor : null;
  if (cursor === null) return json(400, { error: "cursor must be a non-negative integer" });
  const v = validateChanges(b.changes);
  if ("error" in v) return json(400, { error: v.error });
  const accepted = new Set<string>();
  for (const ch of v.changes) {
    if (await queries.applyChange(user.id, ch.type, ch.id, ch.updatedAt, ch.deleted === true, JSON.stringify(ch.data))) {
      accepted.add(`${ch.type}|${ch.id}`);
    }
  }
  const rows = await queries.recordsSince(user.id, cursor);
  const changes = rows.filter((r) => !accepted.has(`${r.type}|${r.id}`)).map(recordToChange);
  return json(200, { cursor: await queries.maxSeq(user.id), changes, serverTime: now.toISOString() });
}
