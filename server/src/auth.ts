import type { Queries, UserRow } from "./queries.js";
import { json, EMAIL_RE } from "./http.js";

export interface Identity { sub: string; email?: string }
export type TokenVerifier = (token: string, aud: string) => Promise<Identity>;

export interface AuthEnv {
  GOOGLE_CLIENT_ID?: string;
  RESEND_API_KEY?: string;
  ENV?: string;
}
export interface AuthCtx {
  queries: Queries;
  env?: AuthEnv;
  now?: () => Date;
  verifyApple?: TokenVerifier;
  verifyGoogle?: TokenVerifier;
  sendEmail?: (to: string, code: string) => Promise<void>;
}

// ---------- RS256 JWT verification (Apple / Google identity tokens, Web Crypto) ----------

interface DecodedJwt {
  header: { alg?: string; kid?: string };
  payload: Record<string, unknown>;
  signingInput: string;
  signature: Uint8Array<ArrayBuffer>;
}

function b64urlJson(s: string): unknown {
  return JSON.parse(atob(s.replace(/-/g, "+").replace(/_/g, "/")));
}
function b64urlBytes(s: string): Uint8Array<ArrayBuffer> {
  const bin = atob(s.replace(/-/g, "+").replace(/_/g, "/"));
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

function decodeJwt(token: string): DecodedJwt {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("malformed token");
  return {
    header: b64urlJson(parts[0]) as DecodedJwt["header"],
    payload: b64urlJson(parts[1]) as Record<string, unknown>,
    signingInput: `${parts[0]}.${parts[1]}`,
    signature: b64urlBytes(parts[2]),
  };
}

const jwksCache = new Map<string, { keys: Record<string, unknown>[]; at: number }>();
const JWKS_TTL = 3600_000; // 1 h

async function jwksKeys(url: string): Promise<Record<string, unknown>[]> {
  const hit = jwksCache.get(url);
  if (hit && Date.now() - hit.at < JWKS_TTL) return hit.keys;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`jwks fetch failed: ${res.status}`);
  const { keys } = (await res.json()) as { keys: Record<string, unknown>[] };
  jwksCache.set(url, { keys, at: Date.now() });
  return keys;
}

async function verifyRs256(token: string, jwksUrl: string, aud: string, issuers: string[]): Promise<Identity> {
  const { header, payload, signingInput, signature } = decodeJwt(token);
  if (header.alg !== "RS256") throw new Error("unsupported alg");
  const keys = await jwksKeys(jwksUrl);
  const candidates = header.kid ? keys.filter((k) => k.kid === header.kid) : keys;
  const input = new TextEncoder().encode(signingInput);
  let verified = false;
  for (const k of candidates.length ? candidates : keys) {
    try {
      const key = await crypto.subtle.importKey(
        "jwk", k as JsonWebKey, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, ["verify"],
      );
      if (await crypto.subtle.verify("RSASSA-PKCS1-v1_5", key, signature, input)) {
        verified = true;
        break;
      }
    } catch {
      // wrong key shape (e.g. EC key during rotation) — try the next candidate
    }
  }
  if (!verified) throw new Error("bad signature");
  if (typeof payload.iss !== "string" || !issuers.includes(payload.iss)) throw new Error("bad iss");
  if (payload.aud !== aud) throw new Error("bad aud");
  if (typeof payload.exp !== "number" || payload.exp * 1000 < Date.now()) throw new Error("token expired");
  if (typeof payload.sub !== "string" || !payload.sub) throw new Error("bad sub");
  return { sub: payload.sub, email: typeof payload.email === "string" ? payload.email : undefined };
}

export function verifyAppleToken(token: string, aud: string): Promise<Identity> {
  return verifyRs256(token, "https://appleid.apple.com/auth/keys", aud, ["https://appleid.apple.com"]);
}

export function verifyGoogleToken(token: string, aud: string): Promise<Identity> {
  return verifyRs256(token, "https://www.googleapis.com/oauth2/v3/certs", aud, [
    "https://accounts.google.com",
    "accounts.google.com",
  ]);
}

// ---------- sessions ----------

export async function sha256hex(s: string): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(s));
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}

/** 32 random bytes → base64url (the raw session token; only its SHA-256 is stored). */
export function randomToken(): string {
  const b = crypto.getRandomValues(new Uint8Array(32));
  return btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

const SESSION_TTL = 180 * 24 * 3600_000;

export async function createSession(q: Queries, userId: string, now: string): Promise<string> {
  const token = randomToken();
  await q.insertSession(await sha256hex(token), userId, now);
  return token;
}

/** Resolves the Bearer session to a user; sliding 180-day expiry, last_seen touched at most hourly. */
export async function getUser(req: Request, q: Queries, now = new Date()): Promise<UserRow | null> {
  const h = req.headers.get("authorization") ?? "";
  if (!h.startsWith("Bearer ")) return null;
  const tokenHash = await sha256hex(h.slice(7));
  const s = await q.getSessionByHash(tokenHash);
  if (!s) return null;
  const last = Date.parse(s.last_seen);
  if (now.getTime() - last > SESSION_TTL) {
    await q.deleteSession(tokenHash);
    return null;
  }
  if (now.getTime() - last > 3600_000) await q.touchSession(tokenHash, now.toISOString());
  return q.getUserById(s.user_id);
}

export function publicUser(u: UserRow): { id: string; email?: string; tier: UserRow["tier"]; referralCode: string } {
  const out: { id: string; email?: string; tier: UserRow["tier"]; referralCode: string } = {
    id: u.id, tier: u.tier, referralCode: u.referral_code,
  };
  if (u.email) out.email = u.email;
  return out;
}

// ---------- email codes ----------

function sixDigits(): string {
  return String(crypto.getRandomValues(new Uint32Array(1))[0] % 1_000_000).padStart(6, "0");
}

async function sendWithResend(apiKey: string, to: string, code: string): Promise<void> {
  const res = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
    body: JSON.stringify({
      from: "Forge <coach@vnbnode.com>",
      to,
      subject: "Your Forge sign-in code",
      text: `Your Forge code is ${code}. It expires in 10 minutes.`,
    }),
  });
  if (!res.ok) throw new Error(`email send failed: ${res.status}`);
}

export async function emailStart(ctx: AuthCtx, email: string): Promise<Response> {
  const now = ctx.now?.() ?? new Date();
  const code = sixDigits();
  await ctx.queries.upsertEmailCode(email, await sha256hex(code), new Date(now.getTime() + 600_000).toISOString());
  if (ctx.env?.RESEND_API_KEY) {
    await (ctx.sendEmail ?? ((to, c) => sendWithResend(ctx.env!.RESEND_API_KEY!, to, c)))(email, code);
    return json(200, { ok: true });
  }
  if (ctx.env?.ENV === "production") return json(500, { error: "email delivery not configured" });
  return json(200, { ok: true, devCode: code });
}

export async function emailVerify(ctx: AuthCtx, email: string, code: string): Promise<Response> {
  const q = ctx.queries;
  const now = ctx.now?.() ?? new Date();
  const row = await q.getEmailCode(email);
  if (!row) return json(400, { error: "no code requested" });
  if (Date.parse(row.expires_at) < now.getTime()) return json(400, { error: "code expired" });
  if (row.attempts >= 5) return json(429, { error: "too many attempts" });
  if ((await sha256hex(code)) !== row.code_hash) {
    await q.incrementCodeAttempts(email);
    return json(401, { error: "invalid code" });
  }
  await q.deleteEmailCode(email);
  const user = await q.upsertUserByEmail(email, now.toISOString());
  return json(200, { token: await createSession(q, user.id, now.toISOString()), user: publicUser(user) });
}

// ---------- provider logins ----------

export async function appleLogin(ctx: AuthCtx, identityToken: string): Promise<Response> {
  let identity: Identity;
  try {
    identity = await (ctx.verifyApple ?? verifyAppleToken)(identityToken, "com.vnbnode.forge");
  } catch {
    return json(401, { error: "invalid identity token" });
  }
  const now = (ctx.now?.() ?? new Date()).toISOString();
  const user = await ctx.queries.upsertUserByAppleSub(identity.sub, identity.email ?? null, now);
  return json(200, { token: await createSession(ctx.queries, user.id, now), user: publicUser(user) });
}

export async function googleLogin(ctx: AuthCtx, idToken: string): Promise<Response> {
  const aud = ctx.env?.GOOGLE_CLIENT_ID;
  if (!aud) return json(500, { error: "google login not configured" });
  let identity: Identity;
  try {
    identity = await (ctx.verifyGoogle ?? verifyGoogleToken)(idToken, aud);
  } catch {
    return json(401, { error: "invalid id token" });
  }
  const now = (ctx.now?.() ?? new Date()).toISOString();
  const user = await ctx.queries.upsertUserByGoogleSub(identity.sub, identity.email ?? null, now);
  return json(200, { token: await createSession(ctx.queries, user.id, now), user: publicUser(user) });
}

export { EMAIL_RE };
