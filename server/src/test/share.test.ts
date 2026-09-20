import assert from "node:assert/strict";
import { readFileSync, readdirSync } from "node:fs";
import { dirname, join } from "node:path";
import { DatabaseSync } from "node:sqlite";
import test from "node:test";
import { fileURLToPath } from "node:url";
import {
    SHARE_MAX_ACTIVE_PER_OWNER,
    SHARE_REPORT_REVIEW_BATCH,
    SHARE_SCHEMA_VERSION,
    createApp,
    escapeHtml,
    parseShareProgram,
    sharePreviewHtml,
    type ShareableProgram,
} from "../app.js";
import { sha256hex } from "../auth.js";
import type { D1Database, D1PreparedStatement } from "../db.js";
import { d1Queries, memoryQueries, type ProgramShareRow, type Queries } from "../queries.js";
import { call, login } from "./helpers.js";

const PROGRAM: ShareableProgram = {
  v: SHARE_SCHEMA_VERSION,
  title: "Base block",
  days: [{ name: "Day 1", exercises: [{ name: "Back squat", sets: 3, reps: "5" }] }],
};

function shareApp(opts: { limiter?: (key: string) => Promise<boolean>; now?: () => Date; queries?: Queries } = {}) {
  const queries = opts.queries ?? memoryQueries();
  const app = createApp({
    chunks: [],
    complete: async () => ({ answer: "stub", provider: "gemini" }),
    secret: "test",
    providers: [],
    limiter: opts.limiter,
    api: {
      queries,
      env: { ENV: "dev" },
      verifyApple: async (t) => ({ sub: `apple-${t}`, email: "lifter@example.com" }),
      now: opts.now,
    },
  });
  return { app, queries };
}

interface Published {
  status: number;
  code?: string;
  url?: string;
  expiresAt?: string;
  error?: string;
  errorCode?: string;
  schemaVersion?: number;
}

async function publish(
  app: ReturnType<typeof createApp>,
  token: string,
  body: unknown = { program: PROGRAM, rightsConfirmed: true },
): Promise<Published> {
  const res = await call(app, "POST", "/programs/share", { token, body });
  const json = (await res.json()) as Omit<Published, "status">;
  return { status: res.status, ...json };
}

/** Publishes and asserts success, returning the token (kept non-optional for the assertions below). */
async function publishCode(app: ReturnType<typeof createApp>, token: string, body?: unknown): Promise<string> {
  const created = await publish(app, token, body);
  assert.equal(created.status, 201, created.error);
  assert.ok(created.code);
  return created.code;
}

async function rowFor(queries: Queries, code: string): Promise<ProgramShareRow | null> {
  return queries.getProgramShareByTokenHash(await sha256hex(code));
}

// ---------- auth, rights, entropy ----------

test("share create requires the app secret, a session and explicit rights confirmation", async () => {
  const { app } = shareApp();
  const u = await login(app, "s1");

  const noSecret = await app(
    new Request("http://x/programs/share", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ program: PROGRAM, rightsConfirmed: true }),
    }),
  );
  assert.equal(noSecret.status, 401);

  const noSession = await call(app, "POST", "/programs/share", { body: { program: PROGRAM, rightsConfirmed: true } });
  assert.equal(noSession.status, 401);

  assert.equal((await publish(app, u.token, { program: PROGRAM })).status, 400);
  assert.equal((await publish(app, u.token, { program: PROGRAM, rightsConfirmed: false })).status, 400);
  assert.equal((await publish(app, u.token, { program: PROGRAM, rightsConfirmed: "true" })).status, 400);
});

test("share create returns a high-entropy code and an unlisted URL", async () => {
  const { app } = shareApp();
  const u = await login(app, "s1");
  const created = await publish(app, u.token);
  assert.equal(created.status, 201);
  assert.match(created.code!, /^[A-Za-z0-9_-]{43}$/); // 32 random bytes → base64url
  assert.equal(created.url, `https://regulift.app/p/${created.code}`);
  assert.ok(Date.parse(created.expiresAt!) > Date.now());

  const codes = new Set<string>();
  for (let i = 0; i < 8; i++) codes.add((await publish(app, u.token)).code!);
  assert.equal(codes.size, 8, "tokens must never repeat");
});

test("public fetch is cache-safe, returns only allowlisted fields, never the owner", async () => {
  const { app, queries } = shareApp();
  const u = await login(app, "s1");
  const code = await publishCode(app, u.token);

  const res = await call(app, "GET", `/programs/share/${code}`);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("cache-control"), "no-store, no-cache, must-revalidate, private");
  assert.equal(res.headers.get("x-content-type-options"), "nosniff");
  const body = (await res.json()) as { program: ShareableProgram; code: string; expiresAt: string };
  assert.deepEqual(body.program, PROGRAM);
  assert.equal(body.code, code);
  assert.equal(JSON.stringify(body).includes(u.user.id), false, "no personal data in a public response");

  const row = (await rowFor(queries, code))!;
  assert.equal(row.owner_id, u.user.id);
  assert.equal(row.status, "active");
  assert.equal(row.token_prefix, code.slice(0, 8));
  assert.notEqual(row.token_hash, code, "only the hash is stored");
  assert.equal(row.payload_hash, await sha256hex(row.payload));
});

// ---------- payload validation ----------

test("malformed, unknown and sensitive payloads are refused before anything is stored", async () => {
  const { app } = shareApp();
  const u = await login(app, "s1");
  const cases: [unknown, number][] = [
    [null, 400],
    ["nope", 400],
    [[], 400],
    [{ ...PROGRAM, weeks: 6 }, 400],
    [{ ...PROGRAM, history: [{ set: 1 }] }, 400],
    [{ ...PROGRAM, weightKg: 100 }, 400],
    [{ ...PROGRAM, coachMemory: "knee hurts" }, 400],
    [{ ...PROGRAM, conversations: [] }, 400],
    [{ ...PROGRAM, privateNotes: "deload next week" }, 400],
    [{ ...PROGRAM, rawSource: "imported html" }, 400],
    [{ ...PROGRAM, v: 99 }, 400],
    [{ ...PROGRAM, v: "1" }, 400],
    [{ ...PROGRAM, title: "" }, 400],
    [{ ...PROGRAM, title: "a".repeat(81) }, 400],
    [{ ...PROGRAM, title: "mail me at lifter@example.com" }, 400],
    [{ ...PROGRAM, title: "see https://example.com" }, 400],
    [{ ...PROGRAM, days: [] }, 400],
    [{ ...PROGRAM, days: [{ name: "Day 1", exercises: [] }] }, 400],
    [{ ...PROGRAM, days: [{ name: "Day 1", exercises: [{ name: "Squat", sets: 0 }] }] }, 400],
    [{ ...PROGRAM, days: [{ name: "Day 1", exercises: [{ name: "Squat", sets: 3, reps: "5", rpe: 8 }] }] }, 400],
    [{ ...PROGRAM, days: [{ name: "Day 1", exercises: [{ name: "Squat", load: 100 }] }] }, 400],
    [{ ...PROGRAM, days: [{ name: "Day 1", exercises: [{ name: "Squat" }], notes: "x" }] }, 400],
  ];
  for (const [program, status] of cases) {
    const res = await publish(app, u.token, { program, rightsConfirmed: true });
    assert.equal(res.status, status, JSON.stringify(program).slice(0, 90));
    assert.equal(res.code, undefined);
  }
  // the sensitive ones are labelled so the client can explain the refusal
  const sensitive = await call(app, "POST", "/programs/share", {
    token: u.token,
    body: { program: { ...PROGRAM, history: [] }, rightsConfirmed: true },
  });
  assert.equal(((await sensitive.json()) as { errorCode: string }).errorCode, "sensitive_field");
});

test("oversized program is refused with 413", async () => {
  const { app } = shareApp();
  const u = await login(app, "s1");
  const days = Array.from({ length: 14 }, (_, d) => ({
    name: `Day ${d + 1}`,
    exercises: Array.from({ length: 30 }, () => ({ name: "X".repeat(80), sets: 4, reps: "8-12" })),
  }));
  const res = await publish(app, u.token, { program: { v: SHARE_SCHEMA_VERSION, title: "Huge", days }, rightsConfirmed: true });
  assert.equal(res.status, 413);
});

test("validation is a pure function with an exact allowlist", () => {
  assert.equal(parseShareProgram(PROGRAM).ok, true);
  const rejected = parseShareProgram({ ...PROGRAM, sleepHours: 7 });
  assert.equal(rejected.ok, false);
  assert.equal(rejected.ok === false && rejected.code, "sensitive_field");
});

// ---------- immutability ----------

test("payload is immutable: revoke/report never rewrite it and duplicate tokens are refused", async () => {
  const { app, queries } = shareApp();
  const u = await login(app, "s1");
  const code = await publishCode(app, u.token);
  const before = (await rowFor(queries, code))!;

  await call(app, "DELETE", `/programs/share/${code}`, { token: u.token });
  await call(app, "POST", `/programs/share/${code}/report`, { body: { reason: "spam" } });
  const after = (await rowFor(queries, code))!;
  assert.equal(after.payload, before.payload);
  assert.equal(after.payload_hash, before.payload_hash);
  assert.equal(after.created_at, before.created_at);
  assert.equal(after.expires_at, before.expires_at);
  assert.equal(after.schema_version, before.schema_version);
  assert.equal(after.status, "revoked");
  assert.ok(after.revoked_at);

  await assert.rejects(() => queries.insertProgramShare({ ...before }));
  // no update path exists: the payload can only be written once
  assert.equal(typeof (queries as unknown as { updateProgramShare?: unknown }).updateProgramShare, "undefined");
});

// ---------- expiry + revocation ----------

test("expired links are indistinguishable from unknown links", async () => {
  let clock = new Date("2025-06-01T00:00:00Z");
  const { app } = shareApp({ now: () => clock });
  const u = await login(app, "s1");
  const code = await publishCode(app, u.token, { program: PROGRAM, rightsConfirmed: true, expiresInDays: 1 });
  assert.equal((await call(app, "GET", `/programs/share/${code}`)).status, 200);
  assert.equal((await call(app, "GET", `/p/${code}`)).status, 200);
  clock = new Date("2025-06-02T00:00:01Z");
  assert.equal((await call(app, "GET", `/programs/share/${code}`)).status, 404);
  assert.equal((await call(app, "GET", `/p/${code}`)).status, 404); // HTML page never says why
});

test("only the owner can revoke; revocation is immediate and idempotent", async () => {
  const { app } = shareApp();
  const owner = await login(app, "owner");
  const other = await login(app, "other");
  const code = await publishCode(app, owner.token);

  assert.equal((await call(app, "DELETE", `/programs/share/${code}`, { token: other.token })).status, 403);
  assert.equal((await call(app, "GET", `/programs/share/${code}`)).status, 200, "a failed revoke must not touch the share");
  assert.equal((await call(app, "DELETE", `/programs/share/${code}`)).status, 401);

  assert.equal((await call(app, "DELETE", `/programs/share/${code}`, { token: owner.token })).status, 200);
  assert.equal((await call(app, "DELETE", `/programs/share/${code}`, { token: owner.token })).status, 200);
  assert.equal((await call(app, "GET", `/programs/share/${code}`)).status, 404);
  assert.equal((await call(app, "GET", `/p/${code}`)).status, 404);
  assert.equal((await call(app, "GET", "/programs/share/not-a-token")).status, 404);
  assert.equal((await call(app, "GET", `/programs/share/${"z".repeat(43)}`)).status, 404);
});

// ---------- rate limiting + abuse report ----------

test("publish is rate-limited by authenticated owner + IP; public fetch/report stay limited", async () => {
  const keys: string[] = [];
  let block = false;
  const { app, queries } = shareApp({ limiter: async (key) => { keys.push(key); return !block; } });
  const u = await login(app, "s1");

  const created = await call(app, "POST", "/programs/share", {
    token: u.token,
    body: { program: PROGRAM, rightsConfirmed: true },
    headers: { "cf-connecting-ip": "9.9.9.9" },
  });
  assert.equal(created.status, 201);
  assert.ok(keys.includes(`share:publish:${u.user.id}:9.9.9.9`), "the publish budget is keyed by owner + IP");
  const code = ((await created.json()) as { code: string }).code;

  block = true;
  const over = await call(app, "POST", "/programs/share", {
    token: u.token,
    body: { program: PROGRAM, rightsConfirmed: true },
    headers: { "cf-connecting-ip": "9.9.9.9" },
  });
  assert.equal(over.status, 429);
  assert.equal(over.headers.get("cache-control"), "no-store, no-cache, must-revalidate, private");
  assert.equal((await call(app, "GET", `/programs/share/${code}`)).status, 429);
  assert.equal((await call(app, "GET", `/p/${code}`)).status, 429);
  assert.equal((await call(app, "POST", `/programs/share/${code}/report`, { body: { reason: "spam" } })).status, 429);
  assert.equal((await rowFor(queries, code))!.report_count, 0, "a rate-limited report never touches the row");

  block = false;
  assert.equal((await call(app, "GET", `/programs/share/${code}`)).status, 200);
});

test("abuse reports are rate-limited, bounded, and remain review-only", async () => {
  const { app, queries } = shareApp();
  const u = await login(app, "s1");
  const code = await publishCode(app, u.token);

  assert.equal((await call(app, "POST", `/programs/share/${code}/report`, { body: { reason: "harassment" } })).status, 400);
  assert.equal((await call(app, "POST", `/programs/share/${code}/report`, { body: { reason: "lifter@example.com" } })).status, 400);
  assert.equal((await call(app, "POST", `/programs/share/${"z".repeat(43)}/report`, { body: { reason: "spam" } })).status, 404);

  for (let i = 0; i < SHARE_REPORT_REVIEW_BATCH; i++) {
    assert.equal((await call(app, "POST", `/programs/share/${code}/report`, { body: { reason: "abuse" } })).status, 202);
  }
  const row = (await rowFor(queries, code))!;
  assert.equal(row.report_count, SHARE_REPORT_REVIEW_BATCH);
  assert.equal(row.last_report_reason, "abuse");
  assert.equal(row.status, "active");
  assert.equal((await call(app, "GET", `/programs/share/${code}`)).status, 200);
  assert.equal((await call(app, "GET", `/p/${code}`)).status, 200);
});

// ---------- active-share cap ----------

test("a hard per-owner cap on live shares refuses excess with 429 and frees a slot on revoke", async () => {
  const { app, queries } = shareApp();
  const owner = await login(app, "cap-owner");
  const other = await login(app, "cap-other");

  const codes: string[] = [];
  for (let i = 0; i < SHARE_MAX_ACTIVE_PER_OWNER; i++) codes.push(await publishCode(app, owner.token));
  assert.equal(
    await queries.countActiveProgramShares(owner.user.id, new Date().toISOString()),
    SHARE_MAX_ACTIVE_PER_OWNER,
  );

  const over = await publish(app, owner.token);
  assert.equal(over.status, 429);
  assert.equal(over.code, undefined);
  assert.match(String(over.error), /active shares/);

  // the cap is per owner, not global
  assert.equal((await publish(app, other.token)).status, 201);

  // revoking frees a slot; a revoked share no longer occupies the cap
  assert.equal((await call(app, "DELETE", `/programs/share/${codes[0]}`, { token: owner.token })).status, 200);
  assert.equal(
    await queries.countActiveProgramShares(owner.user.id, new Date().toISOString()),
    SHARE_MAX_ACTIVE_PER_OWNER - 1,
  );
  assert.equal((await publish(app, owner.token)).status, 201);
  assert.equal((await publish(app, owner.token)).status, 429, "back at the cap");
});

test("expired shares never count against the cap", async () => {
  let clock = new Date("2025-06-01T00:00:00Z");
  const { app, queries } = shareApp({ now: () => clock });
  const u = await login(app, "exp-owner");
  await publishCode(app, u.token, { program: PROGRAM, rightsConfirmed: true, expiresInDays: 1 });
  assert.equal(await queries.countActiveProgramShares(u.user.id, clock.toISOString()), 1);
  clock = new Date("2025-06-02T00:00:01Z");
  assert.equal(await queries.countActiveProgramShares(u.user.id, clock.toISOString()), 0);
});

test("unknown, revoked, expired and tampered shares are indistinguishable 404s", async () => {
  const { d1, db } = sqliteD1();
  const queries = d1Queries(d1);
  let clock = new Date("2025-06-01T00:00:00Z");
  const { app } = shareApp({ queries, now: () => clock });
  const u = await login(app, "same-owner");

  const revokedCode = await publishCode(app, u.token);
  await call(app, "DELETE", `/programs/share/${revokedCode}`, { token: u.token });
  const expiredCode = await publishCode(app, u.token, { program: PROGRAM, rightsConfirmed: true, expiresInDays: 1 });
  const tamperedCode = await publishCode(app, u.token);
  // The payload is write-once, so editing it out of band is exactly the tamper case.
  db.prepare("UPDATE program_shares SET payload = ? WHERE token_hash = ?").run(
    JSON.stringify({ v: SHARE_SCHEMA_VERSION, title: "tampered", days: [{ name: "Day 1", exercises: [{ name: "Squat" }] }] }),
    await sha256hex(tamperedCode),
  );

  clock = new Date("2025-06-02T00:00:01Z"); // the 1-day share is now expired; revoked/tampered rows are unchanged
  const responses = [
    await call(app, "GET", `/programs/share/${"z".repeat(43)}`),
    await call(app, "GET", `/programs/share/${revokedCode}`),
    await call(app, "GET", `/programs/share/${expiredCode}`),
    await call(app, "GET", `/programs/share/${tamperedCode}`),
  ];
  for (const res of responses) {
    assert.equal(res.status, 404);
    assert.equal(res.headers.get("cache-control"), "no-store, no-cache, must-revalidate, private");
  }
  const bodies = await Promise.all(responses.map((r) => r.text()));
  assert.equal(new Set(bodies).size, 1, "no failure mode may be distinguishable from unknown");

  // the inert HTML fallback is equally silent about why
  const htmlUnknown = await call(app, "GET", `/p/${"z".repeat(43)}`);
  const htmlTampered = await call(app, "GET", `/p/${tamperedCode}`);
  assert.equal(htmlUnknown.status, 404);
  assert.equal(htmlTampered.status, 404);
  assert.equal(await htmlUnknown.text(), await htmlTampered.text());
});

// ---------- HTML preview ----------

test("preview page escapes every allowlisted field and runs no script", async () => {
  const { app } = shareApp();
  const u = await login(app, "s1");
  const evil: ShareableProgram = {
    v: SHARE_SCHEMA_VERSION,
    title: `<script>alert("x")</script>`,
    days: [{ name: `Day "1" & <b>`, exercises: [{ name: `<img src=x onerror=alert(1)>`, sets: 2, reps: `<5>` }] }],
  };
  const code = await publishCode(app, u.token, { program: evil, rightsConfirmed: true });
  const res = await call(app, "GET", `/p/${code}`);
  assert.equal(res.status, 200);
  assert.equal(res.headers.get("content-type"), "text/html; charset=utf-8");
  assert.equal(res.headers.get("cache-control"), "no-store, no-cache, must-revalidate, private");
  assert.ok(res.headers.get("content-security-policy")?.includes("default-src 'none'"));
  const html = await res.text();
  assert.equal(html.includes("<script"), false);
  assert.equal(html.includes("<img"), false);
  assert.ok(html.includes("&lt;script&gt;alert(&quot;x&quot;)&lt;/script&gt;"));
  assert.ok(html.includes("&lt;img src=x onerror=alert(1)&gt;"));
  assert.ok(html.includes("Day &quot;1&quot; &amp; &lt;b&gt;"));
  assert.ok(html.includes("&lt;5&gt;"));
  assert.ok(html.includes(code), "the import code is shown");
  assert.equal(html.includes(u.user.id), false);

  assert.equal(escapeHtml(`<&">'`), "&lt;&amp;&quot;&gt;&#39;");
  assert.equal(sharePreviewHtml(PROGRAM, "abc", "2025-07-01T00:00:00.000Z").includes("<script"), false);
});

// ---------- D1 parity ----------

function sqliteD1(): { d1: D1Database; db: DatabaseSync } {
  const db = new DatabaseSync(":memory:");
  const dir = join(dirname(fileURLToPath(import.meta.url)), "..", "..", "migrations");
  for (const file of readdirSync(dir).filter((f) => f.endsWith(".sql")).sort()) {
    db.exec(readFileSync(join(dir, file), "utf8"));
  }
  const d1: D1Database = {
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
  return { d1, db };
}

function d1Row(over: Partial<ProgramShareRow> = {}): ProgramShareRow {
  return {
    id: crypto.randomUUID(),
    token_hash: "h".repeat(64),
    token_prefix: "abcdefgh",
    owner_id: "owner-1",
    payload: JSON.stringify(PROGRAM),
    payload_hash: "p".repeat(64),
    schema_version: SHARE_SCHEMA_VERSION,
    status: "active",
    created_at: "2025-06-01T00:00:00.000Z",
    expires_at: "2025-07-01T00:00:00.000Z",
    revoked_at: null,
    report_count: 0,
    last_reported_at: null,
    last_report_reason: null,
    ...over,
  };
}

test("d1 program share lifecycle on the real schema: insert, fetch, owner revoke, report flag", async () => {
  const { d1, db } = sqliteD1();
  const q = d1Queries(d1);
  const row = d1Row();
  await q.insertProgramShare(row);

  const fetched = (await q.getProgramShareByTokenHash(row.token_hash))!;
  assert.deepEqual({ ...fetched }, row);
  assert.equal((await q.getProgramShareById(row.id))!.payload, row.payload);
  assert.equal(await q.getProgramShareByTokenHash("nope"), null);

  // duplicate token_hash is rejected by the UNIQUE index (immutability boundary)
  await assert.rejects(() => q.insertProgramShare(d1Row({ id: crypto.randomUUID() })));

  // a non-owner revoke changes nothing
  assert.equal(await q.revokeProgramShare(row.id, "someone-else", "2025-06-05T00:00:00.000Z"), false);
  assert.equal((await q.getProgramShareById(row.id))!.status, "active");

  assert.equal(await q.revokeProgramShare(row.id, row.owner_id, "2025-06-05T00:00:00.000Z"), true);
  const revoked = (await q.getProgramShareById(row.id))!;
  assert.equal(revoked.status, "revoked");
  assert.equal(revoked.revoked_at, "2025-06-05T00:00:00.000Z");
  assert.equal(revoked.payload, row.payload, "revoke must not rewrite the payload");
  assert.equal(await q.revokeProgramShare(row.id, row.owner_id, "2025-06-06T00:00:00.000Z"), false);

  const reported = (await q.reportProgramShare(row.token_hash, "spam", "2025-06-07T00:00:00.000Z", 3))!;
  assert.equal(reported.report_count, 1);
  assert.equal(reported.last_report_reason, "spam");
  assert.equal(reported.status, "revoked", "a revoked share is never re-activated by a report");
  assert.equal(await q.reportProgramShare("missing", "spam", "2025-06-07T00:00:00.000Z", 3), null);

  // Reports remain review metadata; anonymous reports never unpublish a live share.
  const active = d1Row({ token_hash: "a".repeat(64), id: crypto.randomUUID() });
  await q.insertProgramShare(active);
  for (let i = 1; i <= 3; i++) await q.reportProgramShare(active.token_hash, "abuse", `2025-06-0${i}T00:00:00.000Z`, 3);
  const reportedActive = (await q.getProgramShareByTokenHash(active.token_hash))!;
  assert.equal(reportedActive.status, "active");
  assert.equal(reportedActive.report_count, 3);
  assert.equal(reportedActive.payload, active.payload);

  // account deletion removes the shares it owns
  const u = await q.upsertUserByAppleSub("sub-1", null, "2025-06-01T00:00:00.000Z");
  await q.insertProgramShare(d1Row({ token_hash: "d".repeat(64), id: crypto.randomUUID(), owner_id: u.id }));
  assert.equal(Number((db.prepare("SELECT COUNT(*) AS n FROM program_shares WHERE owner_id = ?").get(u.id) as { n: number }).n), 1);
  await q.deleteUser(u.id);
  assert.equal(Number((db.prepare("SELECT COUNT(*) AS n FROM program_shares WHERE owner_id = ?").get(u.id) as { n: number }).n), 0);
});

test("d1 and memory count only live shares for an owner (cap parity)", async () => {
  const rows = [
    d1Row({ id: crypto.randomUUID(), token_hash: "1".repeat(64), owner_id: "cap", status: "active", expires_at: "2025-07-01T00:00:00.000Z" }),
    d1Row({ id: crypto.randomUUID(), token_hash: "2".repeat(64), owner_id: "cap", status: "active", expires_at: "2025-06-01T00:00:00.000Z" }), // expired
    d1Row({ id: crypto.randomUUID(), token_hash: "3".repeat(64), owner_id: "cap", status: "revoked", expires_at: "2025-07-01T00:00:00.000Z" }),
    d1Row({ id: crypto.randomUUID(), token_hash: "4".repeat(64), owner_id: "other", status: "active", expires_at: "2025-07-01T00:00:00.000Z" }),
  ];
  const now = "2025-06-10T00:00:00.000Z";

  const q = d1Queries(sqliteD1().d1);
  const m = memoryQueries();
  for (const row of rows) {
    await q.insertProgramShare(row);
    await m.insertProgramShare(row);
  }
  assert.equal(await q.countActiveProgramShares("cap", now), 1, "D1 counts only active, unexpired shares for the owner");
  assert.equal(await m.countActiveProgramShares("cap", now), 1, "memory mirrors the D1 cap query");
});

test("d1 and memory report the same accept/reject decision for a sensitive payload", () => {
  for (const queries of [memoryQueries(), d1Queries(sqliteD1().d1)]) {
    assert.ok(queries);
  }
  const sensitive = parseShareProgram({ ...PROGRAM, coachMemory: [{ note: "x" }] });
  assert.equal(sensitive.ok, false);
  assert.equal(sensitive.ok === false && sensitive.code, "sensitive_field");
  const ok = parseShareProgram(JSON.parse(JSON.stringify(PROGRAM)) as unknown);
  assert.equal(ok.ok, true);
  assert.equal(ok.ok === true && JSON.stringify(ok.program), JSON.stringify(PROGRAM));
});
