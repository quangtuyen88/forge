import { bm25, type Chunk } from "./rag.js";
import { classify } from "./guard.js";
import { buildSystem } from "./prompt.js";
import type { Message } from "./providers.js";
import { json, readJsonBody, EMAIL_RE } from "./http.js";
import type { Queries } from "./queries.js";
import {
  appleLogin, emailStart, emailVerify, getUser, googleLogin, publicUser, sha256hex,
  type TokenVerifier,
} from "./auth.js";
import { syncHandler } from "./sync.js";
import { referralRedeem, revenuecatWebhook, revshare } from "./billing.js";
import { handleSocial } from "./social.js";

export type CompleteFn = (
  system: string,
  messages: Message[],
) => Promise<{ answer: string; provider: string }>;

/** Auth / sync / billing context. Omitted → those routes 404 (coach-only deployments). */
export interface ApiContext {
  queries: Queries;
  env?: {
    GOOGLE_CLIENT_ID?: string;
    RESEND_API_KEY?: string;
    RC_WEBHOOK_SECRET?: string;
    RC_SECRET_KEY?: string;
    ADMIN_SECRET?: string;
    ENV?: string;
  };
  now?: () => Date;
  verifyApple?: TokenVerifier;
  verifyGoogle?: TokenVerifier;
  sendEmail?: (to: string, code: string) => Promise<void>;
  rcGrant?: (appUserId: string) => Promise<void>;
}

export interface AppDeps {
  chunks: Chunk[];
  complete: CompleteFn;
  secret: string;
  providers: string[];
  limiter?: (key: string) => Promise<boolean>;
  retrieve?: (q: string) => Promise<Chunk[]>;
  events?: EventsBinding;
  api?: ApiContext;
}

/** Cloudflare Analytics Engine binding (writes are fire-and-forget). */
export interface EventsBinding {
  writeDataPoint(event: {
    blobs?: (string | number | undefined)[];
    doubles?: (number | undefined)[];
    indexes?: (string | undefined)[];
  }): void;
}

export type CoachAction =
  | { type: "swap"; from: string; to: string }
  | { type: "earlyDeload" }
  | { type: "restartBlock" }
  | { type: "remember"; note: string };

/** Strips a trailing `ACTION {...}` fragment (own line or inline); malformed fragments leave the text untouched. */
export function parseAction(answer: string): { text: string; action: CoachAction | null } {
  const trimmed = answer.trimEnd();
  const m = trimmed.match(/\s*ACTION\s*(\{[^{}]*\})\s*$/);
  if (!m || m.index === undefined) {
    return { text: answer, action: null };
  }
  let action: CoachAction | null = null;
  try {
    const raw = JSON.parse(m[1]) as Record<string, unknown>;
    if (
      raw.type === "swap" &&
      typeof raw.from === "string" && raw.from.length > 0 &&
      typeof raw.to === "string" && raw.to.length > 0
    ) {
      action = { type: "swap", from: raw.from, to: raw.to };
    } else if (raw.type === "earlyDeload" || raw.type === "restartBlock") {
      action = { type: raw.type };
    } else if (raw.type === "remember" && typeof raw.note === "string" && raw.note.length > 0 && raw.note.length <= 140) {
      action = { type: "remember", note: raw.note };
    } else if (raw.type === "none") {
      return { text: trimmed.slice(0, m.index).trim(), action: null };
    }
  } catch {
    action = null;
  }
  if (!action) return { text: answer, action: null };
  return { text: trimmed.slice(0, m.index).trim(), action };
}

/** Strips `[Heading]` echoes and generic `[Source: …]` tags from an answer; keeps unrelated brackets. */
export function stripCitationTags(answer: string, headings: string[]): string {
  const wanted = new Set(headings.map((h) => h.trim().toLowerCase()).filter(Boolean));
  const stripped = answer.replace(/\[([^\]\[\n]+)\]/g, (tag, inner: string) => {
    const key = inner.trim().toLowerCase();
    return wanted.has(key) || /^(source|citation)\s*:/i.test(key) ? "" : tag;
  });
  return stripped.replace(/ {2,}/g, " ").replace(/ +([.,;:!?])/g, "$1");
}

const PAYWALL = {
  A: { headline: "Train with the coach", subline: "Week 1 is built. Start the trial to lift it.", annualBadge: "SAVE 49%" },
  B: { headline: "Your programming, done", subline: "Adaptive loads, deloads and swaps, every session.", annualBadge: "BEST VALUE" },
} as const;

export function fnv1a(s: string): number {
  let h = 0x811c9dc5;
  for (let i = 0; i < s.length; i++) {
    h ^= s.charCodeAt(i);
    h = Math.imul(h, 0x01000193);
  }
  return h >>> 0;
}

/** Deterministic 50/50 paywall split by device id. */
export function assignVariant(device: string): "A" | "B" {
  return fnv1a(device) % 2 === 0 ? "A" : "B";
}

const EVENT_NAME = /^[a-z_]{1,40}$/;
const WAITLIST_CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, OPTIONS",
  "access-control-allow-headers": "content-type",
};

/** First 8 hex chars of SHA-256(email + secret salt) — a stable per-email share code. */
export async function shareCode(email: string, salt: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(email + salt));
  return [...new Uint8Array(digest).slice(0, 4)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function unauthorized(deps: AppDeps, req: Request): boolean {
  return !deps.secret || req.headers.get("x-forge-secret") !== deps.secret;
}

type JsonBody = { error: Response } | { value: unknown };

export function createApp(deps: AppDeps): (req: Request) => Promise<Response> {
  const retrieve = deps.retrieve ?? ((q: string) => Promise.resolve(bm25(q, deps.chunks)));
  return async (req) => {
    const url = new URL(req.url);
    try {
      if (req.method === "GET" && url.pathname === "/health") {
        return json(200, { ok: true, providers: deps.providers, chunks: deps.chunks.length });
      }
      if (req.method === "GET" && url.pathname === "/config") {
        if (unauthorized(deps, req)) return json(401, { error: "unauthorized" });
        const device = url.searchParams.get("device") ?? "";
        if (!device.trim()) return json(400, { error: "device required" });
        const variant = assignVariant(device);
        return json(200, { paywall: { variant, ...PAYWALL[variant] } });
      }
      if (req.method === "POST" && url.pathname === "/events") {
        if (unauthorized(deps, req)) return json(401, { error: "unauthorized" });
        const body = await readJsonBody(req);
        if ("error" in body) return body.error;
        const parsed = body.value as { device?: unknown; events?: unknown };
        const device = typeof parsed.device === "string" ? parsed.device.trim() : "";
        if (!device) return json(400, { error: "device required" });
        const events = Array.isArray(parsed.events) ? (parsed.events as { name?: unknown; ts?: unknown; props?: unknown }[]) : [];
        if (events.length === 0) return json(400, { error: "events required" });
        if (events.length > 50) return json(400, { error: "too many events (max 50)" });
        const valid = events.flatMap((e): { name: string; ts: number; props?: unknown }[] => {
          if (!e || typeof e !== "object" || typeof e.name !== "string" || !EVENT_NAME.test(e.name) || typeof e.ts !== "number") return [];
          return [{ name: e.name, ts: e.ts, props: e.props }];
        });
        for (const e of valid) {
          const props = e.props && typeof e.props === "object" ? JSON.stringify(e.props) : "{}";
          if (deps.events) {
            deps.events.writeDataPoint({ blobs: [e.name, device, props], doubles: [e.ts], indexes: [e.name] });
          } else {
            console.log("event", e.name, device);
          }
        }
        return json(200, { ok: true, accepted: valid.length });
      }
      if (req.method === "POST" && url.pathname === "/feedback") {
        if (unauthorized(deps, req)) return json(401, { error: "unauthorized" });
        const ip = req.headers.get("cf-connecting-ip") ?? "anon";
        if (deps.limiter && !(await deps.limiter(ip))) {
          return json(429, { error: "Too many requests. Try again in a minute." });
        }
        const body = await readJsonBody(req);
        if ("error" in body) return body.error;
        const parsed = body.value as { device?: unknown; text?: unknown; screen?: unknown };
        const device = typeof parsed.device === "string" ? parsed.device.trim() : "";
        const text = typeof parsed.text === "string" ? parsed.text : "";
        if (!device) return json(400, { error: "device required" });
        if (!text.trim()) return json(400, { error: "text required" });
        if (text.length > 2000) return json(400, { error: "text too long (max 2000)" });
        if (deps.events) {
          deps.events.writeDataPoint({ blobs: ["feedback", device, text], indexes: ["feedback"] });
        } else {
          console.log("feedback", device, text.length);
        }
        return json(200, { ok: true });
      }
      if (req.method === "OPTIONS" && url.pathname === "/waitlist") {
        return new Response(null, { status: 204, headers: WAITLIST_CORS });
      }
      if (req.method === "POST" && url.pathname === "/waitlist") {
        const ip = req.headers.get("cf-connecting-ip") ?? "anon";
        if (deps.limiter && !(await deps.limiter(ip))) {
          return json(429, { error: "Too many signups. Try again in a minute." }, WAITLIST_CORS);
        }
        const body = await readJsonBody(req);
        if ("error" in body) return body.error;
        const parsed = body.value as { email?: unknown; ref?: unknown };
        const email = typeof parsed.email === "string" ? parsed.email.trim().toLowerCase() : "";
        if (!email || email.length > 120 || !EMAIL_RE.test(email)) {
          return json(400, { error: "valid email required" }, WAITLIST_CORS);
        }
        const ref = typeof parsed.ref === "string" && parsed.ref.trim() ? parsed.ref.trim() : "";
        if (deps.events) {
          deps.events.writeDataPoint({ blobs: ["waitlist", email, ref], indexes: ["waitlist"] });
        } else {
          console.log("waitlist", email, ref);
        }
        const code = await shareCode(email, deps.secret);
        return new Response(JSON.stringify({ ok: true, code }), {
          status: 200,
          headers: { "content-type": "application/json", ...WAITLIST_CORS },
        });
      }
      if (req.method === "GET" && url.pathname.startsWith("/r/")) {
        const code = url.pathname.slice(3);
        return Response.redirect(`https://regulift.app/?ref=${encodeURIComponent(code)}`, 302);
      }
      if (deps.api) {
        const res = await routeApi(deps, req, url);
        if (res) return res;
      }
      if (req.method !== "POST" || url.pathname !== "/coach") {
        return json(404, { error: "not found" });
      }
      if (unauthorized(deps, req)) return json(401, { error: "unauthorized" });
      const ip = req.headers.get("cf-connecting-ip") ?? "anon";
      if (deps.limiter && !(await deps.limiter(ip))) {
        return json(429, { error: "Too many questions. Try again in a minute." });
      }
      const body = await readJsonBody(req);
      if ("error" in body) return body.error;
      const parsed = body.value as { question?: unknown; context?: unknown; history?: unknown; coach?: unknown; notes?: unknown; language?: unknown };
      const question = typeof parsed.question === "string" ? parsed.question : "";
      if (!question.trim()) return json(400, { error: "question required" });
      // Optional per-user daily coach cap (free 5 / pro 60, UTC day) when a Bearer session is present.
      if (deps.api && (req.headers.get("authorization") ?? "").startsWith("Bearer ")) {
        const user = await getUser(req, deps.api.queries, deps.api.now?.());
        if (user) {
          const day = new Date().toISOString().slice(0, 10);
          const used = await deps.api.queries.getCoachUsage(user.id, day);
          if (used >= (user.tier === "pro" ? 60 : 5)) {
            return json(429, { error: "Daily coach limit reached. Upgrade for more." });
          }
          await deps.api.queries.incrementCoachUsage(user.id, day);
        }
      }
      const context = typeof parsed.context === "string" ? parsed.context : "";
      const notes = Array.isArray(parsed.notes)
        ? parsed.notes
            .filter((n): n is string => typeof n === "string")
            .map((n) => n.trim())
            .filter((n) => n.length > 0)
            .map((n) => n.slice(0, 140))
            .slice(0, 20)
        : [];
      const coach =
        typeof parsed.coach === "string" && parsed.coach.trim() === "Kai" ? "Kai" : "Nova";
      const language =
        typeof parsed.language === "string" && /^[a-zA-Z-]{2,10}$/.test(parsed.language)
          ? parsed.language.toLowerCase()
          : "en";
      const history: Message[] = Array.isArray(parsed.history)
        ? parsed.history.filter(
            (m): m is Message =>
              !!m &&
              typeof m === "object" &&
              ((m as Message).role === "user" || (m as Message).role === "assistant") &&
              typeof (m as Message).content === "string",
          )
        : [];

      if (classify(question) === "medical") {
        return json(200, {
          answer: "That's a medical question — please ask a doctor or physiotherapist.",
          refused: true,
          citations: [],
          action: null,
        });
      }
      const top = await retrieve(question);
      const system = buildSystem(context, top, coach, notes, language);
      const { answer, provider } = await deps.complete(system, [
        ...history,
        { role: "user", content: question },
      ]);
      const { text, action } = parseAction(answer);
      const citations = top.map((c) => c.heading);
      return json(200, {
        answer: stripCitationTags(text, citations),
        refused: false,
        citations,
        provider,
        action,
      });
    } catch (e) {
      const message = e instanceof Error ? e.message : String(e);
      const friendly =
        /^401/.test(message) || /no provider available/.test(message)
          ? "The coach server has no model configured yet. Ask the owner to enable the Workers AI binding or set GEMINI_API_KEY / ANTHROPIC_API_KEY."
          : message;
      return json(502, { error: friendly });
    }
  };
}

/** Auth, sync, billing, referral routes (contract: API.md). Returns null when no route matches. */
async function routeApi(deps: AppDeps, req: Request, url: URL): Promise<Response | null> {
  const api = deps.api!;
  const q = api.queries;
  const p = url.pathname;
  const bearerUser = () => getUser(req, q, api.now?.());
  const readBody = async (): Promise<Record<string, unknown> | null> => {
    const body = await readJsonBody(req);
    return "error" in body ? null : (body.value as Record<string, unknown>);
  };

  // RevenueCat cannot send the app secret; it authenticates with the RC webhook secret instead.
  if (req.method === "POST" && p === "/billing/revenuecat") {
    const body = await readBody();
    if (body === null) return json(400, { error: "invalid JSON" });
    return revenuecatWebhook(api, req.headers.get("authorization"), body);
  }
  if (unauthorized(deps, req)) return json(401, { error: "unauthorized" });

  if (req.method === "POST" && (p === "/auth/apple" || p === "/auth/google")) {
    const body = await readBody();
    if (body === null) return json(400, { error: "invalid JSON" });
    const token = p === "/auth/apple" ? body.identityToken : body.idToken;
    if (typeof token !== "string" || !token) return json(400, { error: "token required" });
    return p === "/auth/apple" ? appleLogin(api, token) : googleLogin(api, token);
  }
  if (req.method === "POST" && p === "/auth/email/start") {
    const body = await readBody();
    if (body === null) return json(400, { error: "invalid JSON" });
    const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
    if (!email || email.length > 120 || !EMAIL_RE.test(email)) return json(400, { error: "valid email required" });
    return emailStart(api, email);
  }
  if (req.method === "POST" && p === "/auth/email/verify") {
    const body = await readBody();
    if (body === null) return json(400, { error: "invalid JSON" });
    if (typeof body.email !== "string" || typeof body.code !== "string") {
      return json(400, { error: "email and code required" });
    }
    return emailVerify(api, body.email.trim().toLowerCase(), body.code);
  }
  if (req.method === "POST" && p === "/auth/logout") {
    const h = req.headers.get("authorization") ?? "";
    if (!h.startsWith("Bearer ")) return json(401, { error: "unauthorized" });
    await q.deleteSession(await sha256hex(h.slice(7)));
    return json(200, { ok: true });
  }
  if (req.method === "GET" && p === "/me") {
    const user = await bearerUser();
    return user ? json(200, { user: publicUser(user) }) : json(401, { error: "unauthorized" });
  }
  if (req.method === "DELETE" && p === "/me") {
    const user = await bearerUser();
    if (!user) return json(401, { error: "unauthorized" });
    await q.deleteUser(user.id);
    return json(200, { ok: true });
  }
  if (req.method === "POST" && p === "/sync") {
    const user = await bearerUser();
    if (!user) return json(401, { error: "unauthorized" });
    const body = await readBody();
    if (body === null) return json(400, { error: "invalid JSON" });
    return syncHandler(q, user, body, new Date());
  }
  if (req.method === "GET" && p === "/referral") {
    const user = await bearerUser();
    if (!user) return json(401, { error: "unauthorized" });
    const counts = await q.referralCounts(user.id);
    return json(200, { code: user.referral_code, ...counts });
  }
  if (req.method === "POST" && p === "/referral/redeem") {
    const user = await bearerUser();
    if (!user) return json(401, { error: "unauthorized" });
    const body = await readBody();
    if (body === null) return json(400, { error: "invalid JSON" });
    return referralRedeem(q, user, body.code);
  }
  if (req.method === "POST" && p === "/attribution") {
    const user = await bearerUser();
    if (!user) return json(401, { error: "unauthorized" });
    const body = await readBody();
    if (body === null) return json(400, { error: "invalid JSON" });
    const promo = body.promoCode;
    if (typeof promo !== "string" || !promo.trim() || promo.length > 64) return json(400, { error: "promoCode required" });
    await q.setPromoCode(user.id, promo.trim());
    return json(200, { ok: true });
  }
  if (req.method === "GET" && p === "/admin/revshare") {
    return revshare(q, api.env?.ADMIN_SECRET, req.headers.get("x-forge-admin"), url.searchParams.get("month"));
  }
  if (p.startsWith("/social/")) {
    const socialUser = await bearerUser();
    if (!socialUser) return json(401, { error: "unauthorized" });
    const r = await handleSocial(req, url, socialUser, q, { now: api.now });
    if (r) return r;
  }
  return null;
}
