import { bm25, type Chunk } from "./rag.js";
import { classify } from "./guard.js";
import { buildSystem } from "./prompt.js";
import type { Message } from "./providers.js";

export type CompleteFn = (
  system: string,
  messages: Message[],
) => Promise<{ answer: string; provider: string }>;

export interface AppDeps {
  chunks: Chunk[];
  complete: CompleteFn;
  secret: string;
  providers: string[];
  limiter?: (key: string) => Promise<boolean>;
  retrieve?: (q: string) => Promise<Chunk[]>;
  events?: EventsBinding;
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
  | { type: "restartBlock" };

/** Strips a trailing `ACTION {...}` line; malformed lines leave the text untouched. */
export function parseAction(answer: string): { text: string; action: CoachAction | null } {
  const trimmed = answer.trimEnd();
  const nl = trimmed.lastIndexOf("\n");
  const last = (nl === -1 ? trimmed : trimmed.slice(nl + 1)).trim();
  if (!last.startsWith("ACTION {") || !last.endsWith("}")) {
    return { text: answer, action: null };
  }
  let action: CoachAction | null = null;
  try {
    const raw = JSON.parse(last.slice("ACTION ".length)) as Record<string, unknown>;
    if (
      raw.type === "swap" &&
      typeof raw.from === "string" && raw.from.length > 0 &&
      typeof raw.to === "string" && raw.to.length > 0
    ) {
      action = { type: "swap", from: raw.from, to: raw.to };
    } else if (raw.type === "earlyDeload" || raw.type === "restartBlock") {
      action = { type: raw.type };
    }
  } catch {
    action = null;
  }
  if (!action) return { text: answer, action: null };
  return { text: (nl === -1 ? "" : trimmed.slice(0, nl)).trimEnd(), action };
}

const PAYWALL = {
  A: { headline: "Train with the coach", subline: "Week 1 is built. Start the trial to lift it.", annualBadge: "SAVE 50%" },
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
const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
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

function json(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

type JsonBody = { error: Response } | { value: unknown };

async function readJsonBody(req: Request): Promise<JsonBody> {
  if (!String(req.headers.get("content-type") ?? "").includes("application/json")) {
    return { error: json(415, { error: "content-type must be application/json" }) };
  }
  const raw = await req.text();
  if (raw.length > 64 * 1024) return { error: json(413, { error: "body too large" }) };
  try {
    return { value: JSON.parse(raw) };
  } catch {
    return { error: json(400, { error: "invalid JSON" }) };
  }
}

function unauthorized(deps: AppDeps, req: Request): boolean {
  return !deps.secret || req.headers.get("x-forge-secret") !== deps.secret;
}

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
        return Response.redirect(`https://vnbnode.com/forge/?ref=${encodeURIComponent(code)}`, 302);
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
      const parsed = body.value as { question?: unknown; context?: unknown; history?: unknown; coach?: unknown };
      const question = typeof parsed.question === "string" ? parsed.question : "";
      if (!question.trim()) return json(400, { error: "question required" });
      const context = typeof parsed.context === "string" ? parsed.context : "";
      const coach =
        typeof parsed.coach === "string" && parsed.coach.trim() === "Kai" ? "Kai" : "Nova";
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
      const system = buildSystem(context, top, coach);
      const { answer, provider } = await deps.complete(system, [
        ...history,
        { role: "user", content: question },
      ]);
      const { text, action } = parseAction(answer);
      return json(200, {
        answer: text,
        refused: false,
        citations: top.map((c) => c.heading),
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
