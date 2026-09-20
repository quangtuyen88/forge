import {
    appleLogin, emailStart, emailVerify, getUser, googleLogin, publicUser, randomToken, sha256hex,
    type TokenVerifier,
} from "./auth.js";
import { referralRedeem, revenuecatWebhook, revshare } from "./billing.js";
import { clampText, containsPromptAttack, isPromptAttack, sanitizeNote } from "./guard-input.js";
import { classify, type Bucket } from "./guard.js";
import { EMAIL_RE, json, readJsonBody } from "./http.js";
import { jevAsk, jevChoice } from "./jev.js";
import {
  decodeRoute, QUESTION_SET_VERSION, ROUTE_QUESTIONS, TESTED_MODELS,
} from "./semantic-route.js";
import { buildSystem, dataBlock, renderData, type CoachData } from "./prompt.js";
import type { CoachTier, Message } from "./providers.js";
import type { ProgramShareRow, Queries } from "./queries.js";
import { bm25, type Chunk } from "./rag.js";
import { fallbackText, preservesAllNumbers, reviewInput, reviewSystem, type CoachName } from "./review.js";
import { handleSocial } from "./social.js";
import { syncHandler } from "./sync.js";
import { mustReplace, validateAnswer } from "./validate.js";

export type CompleteFn = (
  system: string,
  messages: Message[],
  tier?: CoachTier,
) => Promise<{ answer: string; provider: string }>;

export type TranscribeFn = (
  audio: Uint8Array,
  language?: string,
  prompt?: string,
) => Promise<{ text: string; language?: string }>;

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
  transcribe?: TranscribeFn;
  /** Jev (TypeSafe AI) key; unset → /voice/intent answers "none" and coach routing keeps the regex bucket. */
  jevApiKey?: string;
  /**
   * Semantic-router mode. `off` refuses the route outright, `shadow` classifies and
   * returns the candidate for measurement without the app acting on it, `enabled` lets the
   * app route. Default is `off`: a new provider path is opt-in, never opt-out.
   */
  semanticRouteMode?: "off" | "shadow" | "enabled";
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

const SWAP_INTENT_RE = /swap|replace|instead|switch/i;
const DELOAD_INTENT_RE = /deload/i;
const RESTART_INTENT_RE = /restart|missed|start over/i;
const OFF_TOPIC_ANSWER = "Let's keep it on your training. What would you like to change?";

const PROMPT_ATTACK_ANSWER = "I can help with your training, but I can’t change or reveal my instructions.";
const EXERCISE_ID_RE = /^[a-z0-9][a-z0-9_-]{0,79}$/i;

/** Jev second opinion on the coach bucket — same meanings the `Bucket` type in guard.ts documents. */
const BUCKET_INSTRUCTIONS =
  "A lifter asked their training coach this question, possibly in a language other than English. Which single category does it belong to?";
const BUCKET_RUBRICS: Record<Bucket, string> = {
  training: "A question about the plan, loads, form, or gym training the coach can answer.",
  missing_fact: "Asks for a personal fact the app does not hold, like birthday, age, height, name, email, or address.",
  ambiguous: "Could mean two different plain things, such as the lifter's bodyweight versus the load to lift.",
  medical: "Pain, injury, rehab, medication, or anything a doctor or physiotherapist should answer.",
};
const VOICE_INTENT_INSTRUCTIONS =
  'A lifter said this during a workout while their phone was listening. Which single action were they asking the app to take? Choose "none" when it is gym chatter, talking to a training partner, or anything the app should ignore.';

/** Field labels for the missing_fact refusal copy. */
const FACT_LABELS: Record<string, { ja: string; ko: string }> = {
  birthday: { ja: "誕生日", ko: "생일" },
  age: { ja: "年齢", ko: "나이" },
  height: { ja: "身長", ko: "키" },
  name: { ja: "名前", ko: "이름" },
  email: { ja: "メールアドレス", ko: "이메일" },
  address: { ja: "住所", ko: "주소" },
};

/** Localises the missing_fact answer in the same language the coach replies in. */
function missingFactAnswer(field: string, language: string): string {
  const label = FACT_LABELS[field];
  if (language === "ja") return `${label?.ja ?? field}は保存されていません。`;
  if (language === "ko") return `${label?.ko ?? field}은(는) 저장되어 있지 않아요.`;
  return `I don't have your ${field} saved.`;
}

/** One-line clarifying question naming both ambiguous readings. */
function ambiguousAnswer(language: string): string {
  if (language === "ja") return "体重のことですか、それとも次に上げる重さですか？";
  if (language === "ko") return "체중을 말하는 건가요, 아니면 들어 올릴 무게를 말하는 건가요?";
  return "Do you mean your bodyweight, or the load you lift?";
}

/** Facts present in context/data, so a question about them stays a normal training question. */
function knownFieldsFrom(context: string, data?: CoachData): string[] {
  const text = `${context}\n${data ? renderData(data) : ""}`.toLowerCase();
  const out: string[] = [];
  if (/\bbody\s*weight\b|\bbodyweight\b/.test(text)) out.push("bodyweight");
  if (/\bbirthday\b|\bborn\b/.test(text)) out.push("birthday");
  if (/\bheight\b|\btall\b/.test(text)) out.push("height");
  if (/\bage\b|\byears? old\b/.test(text)) out.push("age");
  if (/\bemail\b/.test(text)) out.push("email");
  if (/\baddress\b/.test(text)) out.push("address");
  if (/\b(?:real\s+)?name\b/.test(text)) out.push("name");
  return out;
}

/** Accepts an ACTION only when the current question matches its intent; remember notes are re-sanitised. */
export function guardAction(action: CoachAction | null, question: string): CoachAction | null {
  if (!action) return null;
  switch (action.type) {
    case "swap":
      return SWAP_INTENT_RE.test(question) &&
        action.from !== action.to &&
        EXERCISE_ID_RE.test(action.from) &&
        EXERCISE_ID_RE.test(action.to)
        ? action
        : null;
    case "earlyDeload":
      return DELOAD_INTENT_RE.test(question) ? action : null;
    case "restartBlock":
      return RESTART_INTENT_RE.test(question) ? action : null;
    case "remember": {
      const note = sanitizeNote(action.note);
      return note ? { type: "remember", note } : null;
    }
  }
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

// ---------- unlisted program shares ----------

/** Public share schema version; a payload with any other `v` is refused. */
export const SHARE_SCHEMA_VERSION = 1;
/** Server-side cap on the serialized public program payload. */
export const SHARE_MAX_PAYLOAD_BYTES = 16 * 1024;
export const SHARE_DEFAULT_TTL_DAYS = 30;
export const SHARE_MAX_TTL_DAYS = 90;
/** Hard cap on live (active, unexpired) shares per owner — bounds moderation load and blast radius. */
export const SHARE_MAX_ACTIVE_PER_OWNER = 20;
/** Batch size for moderation review; reports never unpublish a share automatically. */
export const SHARE_REPORT_REVIEW_BATCH = 5;
export const SHARE_REPORT_REASONS = ["spam", "abuse", "copyright", "other"] as const;
export type ShareReportReason = (typeof SHARE_REPORT_REASONS)[number];
/** 32 random bytes → base64url: 43 chars / 256 bits. Anything else is a 404, never a lookup. */
export const SHARE_TOKEN_RE = /^[A-Za-z0-9_-]{43}$/;

const SHARE_MAX_DAYS = 14;
const SHARE_MAX_EXERCISES_PER_DAY = 30;
const SHARE_MAX_NAME = 80;
const SHARE_MAX_REPS = 24;
const SHARE_MAX_SETS = 20;
// Any key that even smells like workout history, loads, health, goals, coach memory,
// conversations, private notes or raw imported source is refused outright.
const SHARE_SENSITIVE_KEY_RE =
  /history|workout|load|weight|body_?fat|health|injur|pain|medical|goal|memor|conversation|chat|message|note|journal|email|phone|address|birth|hrv|heart|sleep|nutrition|calorie|macro|1rm|e1rm|\bpr\b|raw|source|import|token|secret|password|user|account|private/i;
const SHARE_EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/;
const SHARE_URL_RE = /(?:https?:|www\.)/i;
const SHARE_CONTROL_RE = /[\u0000-\u001f\u007f]/;

const SHARE_NO_STORE: Record<string, string> = {
  "cache-control": "no-store, no-cache, must-revalidate, private",
  "referrer-policy": "no-referrer",
  "x-content-type-options": "nosniff",
};
const SHARE_HTML_HEADERS: Record<string, string> = {
  ...SHARE_NO_STORE,
  "content-type": "text/html; charset=utf-8",
  // No script, no external fetches, no framing: the page is inert text.
  "content-security-policy":
    "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
};

/** The only shape a public share can ever hold. */
export interface ShareableExercise { name: string; sets?: number; reps?: string }
export interface ShareableDay { name: string; exercises: ShareableExercise[] }
export interface ShareableProgram { v: number; title: string; days: ShareableDay[] }

export type ShareErrorCode =
  | "malformed"
  | "unknown_field"
  | "sensitive_field"
  | "unsupported_version"
  | "oversized"
  | "out_of_bounds";

function shareObject(v: unknown): v is Record<string, unknown> {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

/** Trimmed, bounded, control-char/contact-detail-free string — or null. */
function shareText(v: unknown, max: number): string | null {
  if (typeof v !== "string") return null;
  const t = v.trim();
  if (!t || t.length > max || SHARE_CONTROL_RE.test(t)) return null;
  if (SHARE_EMAIL_RE.test(t) || SHARE_URL_RE.test(t)) return null;
  return t;
}

/**
 * Strict allowlist parse of the public program payload. Unknown keys are rejected (not dropped),
 * so nothing outside the allowlist can ever be persisted or rendered.
 */
export function parseShareProgram(raw: unknown):
  | { ok: true; program: ShareableProgram }
  | { ok: false; status: number; error: string; code: ShareErrorCode } {
  const bad = (status: number, error: string, code: ShareErrorCode) => ({ ok: false as const, status, error, code });
  if (!shareObject(raw)) return bad(400, "program must be an object", "malformed");
  for (const key of Object.keys(raw)) {
    if (SHARE_SENSITIVE_KEY_RE.test(key)) return bad(400, `program.${key} is not shareable`, "sensitive_field");
    if (key !== "v" && key !== "title" && key !== "days") return bad(400, `unknown field: ${key}`, "unknown_field");
  }
  if (raw.v !== SHARE_SCHEMA_VERSION) {
    return bad(400, `unsupported schema version (expected ${SHARE_SCHEMA_VERSION})`, "unsupported_version");
  }
  const title = shareText(raw.title, SHARE_MAX_NAME);
  if (!title) return bad(400, `title required (1-${SHARE_MAX_NAME} chars, no contact details)`, "out_of_bounds");
  if (!Array.isArray(raw.days) || raw.days.length < 1 || raw.days.length > SHARE_MAX_DAYS) {
    return bad(400, `days must have 1-${SHARE_MAX_DAYS} entries`, "out_of_bounds");
  }
  const days: ShareableDay[] = [];
  for (const rawDay of raw.days) {
    if (!shareObject(rawDay)) return bad(400, "each day must be an object", "malformed");
    for (const key of Object.keys(rawDay)) {
      if (SHARE_SENSITIVE_KEY_RE.test(key)) return bad(400, `day.${key} is not shareable`, "sensitive_field");
      if (key !== "name" && key !== "exercises") return bad(400, `unknown field: day.${key}`, "unknown_field");
    }
    const name = shareText(rawDay.name, SHARE_MAX_NAME);
    if (!name) return bad(400, `day.name required (1-${SHARE_MAX_NAME} chars)`, "out_of_bounds");
    if (
      !Array.isArray(rawDay.exercises) ||
      rawDay.exercises.length < 1 ||
      rawDay.exercises.length > SHARE_MAX_EXERCISES_PER_DAY
    ) {
      return bad(400, `each day needs 1-${SHARE_MAX_EXERCISES_PER_DAY} exercises`, "out_of_bounds");
    }
    const exercises: ShareableExercise[] = [];
    for (const rawEx of rawDay.exercises) {
      if (!shareObject(rawEx)) return bad(400, "each exercise must be an object", "malformed");
      for (const key of Object.keys(rawEx)) {
        if (SHARE_SENSITIVE_KEY_RE.test(key)) return bad(400, `exercise.${key} is not shareable`, "sensitive_field");
        if (key !== "name" && key !== "sets" && key !== "reps") {
          return bad(400, `unknown field: exercise.${key}`, "unknown_field");
        }
      }
      const exName = shareText(rawEx.name, SHARE_MAX_NAME);
      if (!exName) return bad(400, `exercise.name required (1-${SHARE_MAX_NAME} chars)`, "out_of_bounds");
      const exercise: ShareableExercise = { name: exName };
      if (rawEx.sets !== undefined) {
        if (typeof rawEx.sets !== "number" || !Number.isInteger(rawEx.sets) || rawEx.sets < 1 || rawEx.sets > SHARE_MAX_SETS) {
          return bad(400, `exercise.sets must be an integer 1-${SHARE_MAX_SETS}`, "out_of_bounds");
        }
        exercise.sets = rawEx.sets;
      }
      if (rawEx.reps !== undefined) {
        const reps = shareText(rawEx.reps, SHARE_MAX_REPS);
        if (!reps) return bad(400, `exercise.reps must be 1-${SHARE_MAX_REPS} chars`, "out_of_bounds");
        exercise.reps = reps;
      }
      exercises.push(exercise);
    }
    days.push({ name, exercises });
  }
  const program: ShareableProgram = { v: SHARE_SCHEMA_VERSION, title, days };
  if (new TextEncoder().encode(JSON.stringify(program)).length > SHARE_MAX_PAYLOAD_BYTES) {
    return bad(413, `program too large (max ${SHARE_MAX_PAYLOAD_BYTES} bytes)`, "oversized");
  }
  return { ok: true, program };
}

const HTML_ESCAPES: Record<string, string> = { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" };

/** The single escaping boundary for the preview page. */
export function escapeHtml(s: string): string {
  return s.replace(/[&<>"']/g, (c) => HTML_ESCAPES[c]);
}

/** Inert, self-contained HTML preview: allowlisted fields only, escaped, no script, no personal data. */
export function sharePreviewHtml(program: ShareableProgram, code: string, expiresAt: string): string {
  const lines = (e: ShareableExercise): string => {
    const parts = [escapeHtml(e.name)];
    if (e.sets !== undefined) parts.push(`${e.sets} sets`);
    if (e.reps) parts.push(`${escapeHtml(e.reps)} reps`);
    return `<li>${parts.join(" · ")}</li>`;
  };
  const days = program.days
    .map((d) => `<section><h2>${escapeHtml(d.name)}</h2><ul>${d.exercises.map(lines).join("")}</ul></section>`)
    .join("");
  return `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex, nofollow, noarchive">
<title>${escapeHtml(program.title)}</title>
<style>body{font:16px/1.5 system-ui,sans-serif;margin:0 auto;max-width:40rem;padding:1.5rem;color:#111}h1{font-size:1.4rem}h2{font-size:1rem;margin:1.25rem 0 .25rem}ul{margin:0;padding-left:1.1rem}p.meta{color:#555;font-size:.875rem}code{word-break:break-all}</style>
</head>
<body>
<h1>${escapeHtml(program.title)}</h1>
<p class="meta">Shared program · read-only preview. This unlisted link expires ${escapeHtml(expiresAt)}.</p>
${days}
<p class="meta">Import code: <code>${escapeHtml(code)}</code></p>
</body>
</html>`;
}

/** Raw share token from a path suffix; malformed input is rejected before any lookup. */
function shareTokenFromPath(pathname: string, prefix: string, suffix = ""): string | null {
  if (!pathname.startsWith(prefix) || !pathname.endsWith(suffix)) return null;
  const token = pathname.slice(prefix.length, pathname.length - suffix.length);
  return token && !token.includes("/") ? token : null;
}

type JsonBody = { error: Response } | { value: unknown };

export function createApp(deps: AppDeps): (req: Request) => Promise<Response> {
  const retrieve = deps.retrieve ?? ((q: string) => Promise.resolve(bm25(q, deps.chunks)));
  return async (req) => {
    const url = new URL(req.url);
    try {
      if (req.method === "GET" && url.pathname === "/health") {
        return json(200, { ok: true, chunks: deps.chunks.length });
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
      // Public unlisted-link routes: no app secret, rate-limited, never cached.
      if (req.method === "GET" && url.pathname.startsWith("/programs/share/")) {
        return await publicShareHandler(deps, req, url);
      }
      if (req.method === "POST" && url.pathname.startsWith("/programs/share/") && url.pathname.endsWith("/report")) {
        return await shareReportHandler(deps, req, url);
      }
      if (req.method === "GET" && url.pathname.startsWith("/p/")) {
        return await sharePreviewHandler(deps, req, url);
      }
      if (deps.api) {
        const res = await routeApi(deps, req, url);
        if (res) return res;
      }
      if (req.method === "POST" && url.pathname === "/transcribe") {
        return await transcribeHandler(deps, req, url);
      }
      if (req.method === "POST" && url.pathname === "/review") {
        return await reviewHandler(deps, req);
      }
      if (req.method === "POST" && url.pathname === "/voice/intent") {
        return await voiceIntentHandler(deps, req);
      }
      if (req.method === "POST" && url.pathname === "/coach/semantic-route") {
        return await semanticRouteHandler(deps, req);
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
      const parsed = body.value as { question?: unknown; context?: unknown; history?: unknown; coach?: unknown; notes?: unknown; language?: unknown; data?: unknown; tier?: unknown };
      const question = typeof parsed.question === "string" ? parsed.question : "";
      if (!question.trim()) return json(400, { error: "question required" });
      if (question.length > 1000) return json(413, { error: "too long" });
      if (isPromptAttack(question)) {
        return json(200, { answer: PROMPT_ATTACK_ANSWER, refused: true, citations: [], action: null });
      }
      const tier: CoachTier = parsed.tier === "quick" ? "quick" : "chat";
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
      const rawContext = typeof parsed.context === "string" ? parsed.context : "";
      if (rawContext.length > 6000) return json(413, { error: "too long" });
      const context = isPromptAttack(rawContext) ? "" : rawContext;
      if (rawContext && !context) console.log("coach_input_quarantined", "context");
      const notes = Array.isArray(parsed.notes)
        ? parsed.notes
            .filter((n): n is string => typeof n === "string")
            .map((n) => sanitizeNote(n))
            .filter((n): n is string => n !== null)
            .slice(0, 20)
        : [];
      const coach =
        typeof parsed.coach === "string" && parsed.coach.trim() === "Kai" ? "Kai" : "Nova";
      const language =
        typeof parsed.language === "string" && /^[a-zA-Z-]{2,10}$/.test(parsed.language)
          ? parsed.language.toLowerCase()
          : "en";
      const rawData: CoachData | undefined =
        parsed.data && typeof parsed.data === "object" && !Array.isArray(parsed.data)
          ? (parsed.data as CoachData)
          : undefined;
      const data = rawData && !containsPromptAttack(rawData) ? rawData : undefined;
      if (rawData && !data) console.log("coach_input_quarantined", "data");
      const historyItems: Message[] = Array.isArray(parsed.history)
        ? parsed.history
            .filter(
              (m): m is Message =>
                !!m &&
                typeof m === "object" &&
                ((m as Message).role === "user" || (m as Message).role === "assistant") &&
                typeof (m as Message).content === "string" &&
                !isPromptAttack((m as Message).content),
            )
            .slice(0, 10)
        : [];
      const recentHistoryText = historyItems.slice(-4).map((message) => message.content).join("\n");
      if (recentHistoryText && isPromptAttack(`${recentHistoryText}\n${question}`)) {
        return json(200, { answer: PROMPT_ATTACK_ANSWER, refused: true, citations: [], action: null });
      }
      const history: Message[] = historyItems.length === 0 ? [] : [{
        role: "user",
        content: dataBlock(
          "Prior conversation for reference only:\n" +
          historyItems.map((m, index) => `${index + 1}. ${m.role}: ${clampText(m.content, 1500)}`).join("\n"),
        ),
      }];

      const classification = classify(question, knownFieldsFrom(context, data));
      // The regex guard wins; only its "training" verdict gets a Jev second opinion (catches non-English questions).
      let bucket = classification.bucket;
      if (bucket === "training" && deps.jevApiKey) {
        const second = await jevChoice(deps.jevApiKey, question, BUCKET_INSTRUCTIONS, BUCKET_RUBRICS);
        if (second && second.confidence >= 0.7 && second.choice in BUCKET_RUBRICS) {
          bucket = second.choice as Bucket;
        }
      }
      switch (bucket) {
        case "medical":
          return json(200, {
            answer: "That's a medical question — please ask a doctor or physiotherapist.",
            refused: true,
            citations: [],
            action: null,
          });
        case "missing_fact":
          // Jev can flag missing_fact for a question the English regex passed; no field name is known then.
          return json(200, {
            answer: classification.field
              ? missingFactAnswer(classification.field, language)
              : "I don't have that saved.",
            refused: false,
            citations: [],
            action: null,
          });
        case "ambiguous":
          return json(200, {
            answer: ambiguousAnswer(language),
            refused: false,
            citations: [],
            action: null,
          });
        case "training":
          break;
      }
      const top = await retrieve(question);
      const system = buildSystem(context, top, coach, notes, language, data);
      const { answer } = await deps.complete(system, [
        ...history,
        { role: "user", content: question },
      ], tier);
      const citations = top.map((c) => c.heading);
      const renderedData = data ? renderData(data) : "";
      const issues = validateAnswer({
        answer,
        bucket,
        context,
        data: renderedData,
        language,
      });
      if (mustReplace(issues)) {
        return json(200, {
          answer: OFF_TOPIC_ANSWER,
          refused: false,
          citations,
          action: null,
        });
      }
      for (const issue of issues) {
        console.log("coach_validate", issue.kind, issue.detail);
      }
      const { text, action } = parseAction(answer);
      const guardedAction = guardAction(action, question);
      return json(200, {
        answer: stripCitationTags(text, citations),
        refused: false,
        citations,
        action: guardedAction,
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

const MAX_AUDIO_BYTES = 6 * 1024 * 1024;

/** `POST /transcribe`: raw audio bytes → Whisper text. Same auth + limiter as `/coach`. */
async function transcribeHandler(deps: AppDeps, req: Request, url: URL): Promise<Response> {
  if (unauthorized(deps, req)) return json(401, { error: "unauthorized" });
  const ip = req.headers.get("cf-connecting-ip") ?? "anon";
  if (deps.limiter && !(await deps.limiter(ip))) {
    return json(429, { error: "Too many recordings. Try again in a minute." });
  }
  const declared = Number(req.headers.get("content-length") ?? "0");
  if (Number.isFinite(declared) && declared > MAX_AUDIO_BYTES) {
    return json(413, { error: "audio too large (max 6 MB)" });
  }
  const bytes = new Uint8Array(await req.arrayBuffer());
  if (bytes.length === 0) return json(400, { error: "audio required" });
  if (bytes.length > MAX_AUDIO_BYTES) return json(413, { error: "audio too large (max 6 MB)" });
  const language = url.searchParams.get("language")?.trim() || undefined;
  const prompt = url.searchParams.get("prompt")?.trim().slice(0, 600) || undefined;
  if (!deps.transcribe) throw new Error("no transcriber configured");
  const result = await deps.transcribe(bytes, language, prompt);
  return json(200, { text: result.text, ...(result.language ? { language: result.language } : {}) });
}

async function reviewHandler(deps: AppDeps, req: Request): Promise<Response> {
  if (unauthorized(deps, req)) return json(401, { error: "unauthorized" });
  const ip = req.headers.get("cf-connecting-ip") ?? "anon";
  if (deps.limiter && !(await deps.limiter(ip))) {
    return json(429, { error: "Too many requests. Try again in a minute." });
  }
  const body = await readJsonBody(req);
  if ("error" in body) return body.error;
  const parsed = body.value as { headline?: unknown; lines?: unknown; coach?: unknown; language?: unknown };
  const headline = typeof parsed.headline === "string" ? parsed.headline.trim() : "";
  const lines = Array.isArray(parsed.lines)
    ? parsed.lines.filter((line): line is string => typeof line === "string").map((line) => line.trim()).filter(Boolean)
    : [];
  if (!headline || lines.length === 0) return json(400, { error: "headline and lines required" });
  if (containsPromptAttack([headline, lines])) return json(200, { text: fallbackText(lines) });
  const coach: CoachName = parsed.coach === "Kai" ? "Kai" : "Nova";
  const language =
    typeof parsed.language === "string" && /^[a-zA-Z-]{2,10}$/.test(parsed.language)
      ? parsed.language.toLowerCase()
      : "en";
  const system = reviewSystem(coach, language);
  const { answer } = await deps.complete(system, [{ role: "user", content: reviewInput(headline, lines) }]);
  const text = preservesAllNumbers(answer, headline, ...lines) ? answer : fallbackText(lines);
  return json(200, { text });
}

async function voiceIntentHandler(deps: AppDeps, req: Request): Promise<Response> {
  if (unauthorized(deps, req)) return json(401, { error: "unauthorized" });
  const ip = req.headers.get("cf-connecting-ip") ?? "anon";
  if (deps.limiter && !(await deps.limiter(ip))) {
    return json(429, { error: "Too many requests. Try again in a minute." });
  }
  const body = await readJsonBody(req);
  if ("error" in body) return body.error;
  const parsed = body.value as { transcript?: unknown; intents?: unknown; rubrics?: unknown };
  const transcript = typeof parsed.transcript === "string" ? parsed.transcript.trim() : "";
  const intents = Array.isArray(parsed.intents) ? parsed.intents : [];
  const rubrics =
    parsed.rubrics && typeof parsed.rubrics === "object" && !Array.isArray(parsed.rubrics)
      ? (parsed.rubrics as Record<string, string>)
      : {};
  if (!transcript || transcript.length > 300) {
    return json(400, { error: "transcript required (1-300 chars)" });
  }
  if (isPromptAttack(transcript)) {
    return json(200, { intent: "none", confidence: 0, probabilities: {} });
  }
  if (intents.length < 2 || intents.length > 24) return json(400, { error: "intents must have 2-24 entries" });
  if (!intents.every((intent) => typeof intent === "string" && intent in rubrics)) {
    return json(400, { error: "every intent needs a rubric" });
  }
  // Only the declared intents become options; a stray rubric key must not widen the choice.
  const criteria = Object.fromEntries((intents as string[]).map((intent) => [intent, rubrics[intent]]));
  const result = deps.jevApiKey
    ? await jevChoice(deps.jevApiKey, transcript, VOICE_INTENT_INSTRUCTIONS, criteria)
    : null;
  if (!result) return json(200, { intent: "none", confidence: 0, probabilities: {} });
  return json(200, { intent: result.choice, confidence: result.confidence, probabilities: result.probabilities });
}


// ---------- situational coach router ----------

/** Personalized routing is never cached, shared or stored. */
const ROUTE_NO_STORE: Record<string, string> = {
  "cache-control": "no-store, no-cache, must-revalidate, private",
  "referrer-policy": "no-referrer",
};

/** Product bounds, not provider bounds. Over-limit input falls back; it is never truncated. */
const ROUTE_MAX_BODY_BYTES = 8 * 1024;
const ROUTE_MAX_MESSAGE_BYTES = 1500;
const ROUTE_SURFACES = ["active_workout", "today", "coach"];
/** Only the locales whose routing has been evaluated. A new language is a new gate. */
const ROUTE_LOCALES = ["en"];

function routeFallback(requestId: string, contextToken: string, reason: string): Response {
  return json(
    200,
    { schemaVersion: 1, requestId, contextToken, status: "fallback", reason },
    ROUTE_NO_STORE,
  );
}

/**
 * Classify one approved, placeholder-only message into the handlers the app already has.
 *
 * The client supplies a message, a locale and a surface — never questions, a model name, a
 * threshold, a tool name or action JSON. The response carries no training values and no
 * authorization: the phone rechecks its own capabilities and slots, and the user still
 * approves an exact preview.
 */
async function semanticRouteHandler(deps: AppDeps, req: Request): Promise<Response> {
  if (unauthorized(deps, req)) return json(401, { error: "unauthorized" }, ROUTE_NO_STORE);
  const mode = deps.semanticRouteMode ?? "off";
  const body = await readJsonBody(req);
  if ("error" in body) return body.error;
  const parsed = body.value as Record<string, unknown>;

  const requestId = typeof parsed.requestId === "string" ? parsed.requestId : "";
  const contextToken = typeof parsed.contextToken === "string" ? parsed.contextToken : "";
  if (!requestId || requestId.length > 64 || !contextToken || contextToken.length > 64) {
    return json(400, { error: "requestId and contextToken required" }, ROUTE_NO_STORE);
  }
  // Unknown fields are a schema violation: the client never gets to widen this contract.
  const allowedKeys = ["schemaVersion", "requestId", "contextToken", "locale", "surface", "message"];
  if (Object.keys(parsed).some((key) => !allowedKeys.includes(key))) {
    return json(400, { error: "unknown field" }, ROUTE_NO_STORE);
  }
  const message = typeof parsed.message === "string" ? parsed.message.trim() : "";
  const locale = typeof parsed.locale === "string" ? parsed.locale : "";
  const surface = typeof parsed.surface === "string" ? parsed.surface : "";
  if (!message || new TextEncoder().encode(message).length > ROUTE_MAX_MESSAGE_BYTES) {
    return json(400, { error: "message required (1-1500 bytes)" }, ROUTE_NO_STORE);
  }
  if (new TextEncoder().encode(JSON.stringify(parsed)).length > ROUTE_MAX_BODY_BYTES) {
    return json(413, { error: "body too large" }, ROUTE_NO_STORE);
  }
  if (!ROUTE_LOCALES.includes(locale)) return routeFallback(requestId, contextToken, "locale_not_enabled");
  if (!ROUTE_SURFACES.includes(surface)) return json(400, { error: "unknown surface" }, ROUTE_NO_STORE);
  // The app gates this too; the Worker enforcing its own schema does not replace that.
  if (isPromptAttack(message)) return routeFallback(requestId, contextToken, "blocked_input");

  if (mode === "off" || !deps.jevApiKey) {
    return routeFallback(requestId, contextToken, "routing_disabled");
  }
  const ip = req.headers.get("cf-connecting-ip") ?? "anon";
  if (deps.limiter && !(await deps.limiter(ip))) {
    return routeFallback(requestId, contextToken, "rate_limited");
  }

  // One call per eligible turn. A timeout or malformed body is a fallback, not a retry.
  const raw = await jevAsk(deps.jevApiKey, message, ROUTE_QUESTIONS);
  const decoded = raw ? decodeRoute(raw, TESTED_MODELS) : null;
  if (!decoded) return routeFallback(requestId, contextToken, "provider_unavailable");

  return json(
    200,
    {
      schemaVersion: 1,
      requestId,
      contextToken,
      status: mode === "shadow" ? "shadow" : "candidate",
      questionSetVersion: QUESTION_SET_VERSION,
      policyVersion: mode === "shadow" ? "shadow-v1" : "v1",
      providerModel: decoded.model,
      answers: decoded.answers,
    },
    ROUTE_NO_STORE,
  );
}

// ---------- public share handlers (unlisted bearer links) ----------

type ShareHit = { ok: true; row: ProgramShareRow; program: ShareableProgram } | { ok: false; res: Response };

/** Resolves a token to a live share. Unknown/revoked/expired/tampered all fail closed. */
async function loadPublicShare(deps: AppDeps, token: string): Promise<ShareHit> {
    const api = deps.api!;
    const unavailable = () => ({
      ok: false as const,
      res: json(404, { error: "share not found" }, SHARE_NO_STORE),
    });
    const row = await api.queries.getProgramShareByTokenHash(await sha256hex(token));
    if (!row || row.status !== "active") return unavailable();
    if (Date.parse(row.expires_at) <= (api.now?.() ?? new Date()).getTime()) return unavailable();
    // The payload is write-once, so a hash mismatch means the row was tampered with.
    if ((await sha256hex(row.payload)) !== row.payload_hash) return unavailable();
    let program: ShareableProgram;
    try {
      const parsed = parseShareProgram(JSON.parse(row.payload));
      if (!parsed.ok) return unavailable();
      program = parsed.program;
    } catch {
      return unavailable();
    }
    return { ok: true, row, program };
}

/** `GET /programs/share/:token` — public fetch of the allowlisted program. */
async function publicShareHandler(deps: AppDeps, req: Request, url: URL): Promise<Response> {
  if (!deps.api) return json(404, { error: "not found" }, SHARE_NO_STORE);
  const token = shareTokenFromPath(url.pathname, "/programs/share/");
  if (!token || !SHARE_TOKEN_RE.test(token)) return json(404, { error: "share not found" }, SHARE_NO_STORE);
  const ip = req.headers.get("cf-connecting-ip") ?? "anon";
  if (deps.limiter && !(await deps.limiter(`share:get:${ip}`))) {
    return json(429, { error: "Too many requests. Try again in a minute." }, SHARE_NO_STORE);
  }
  const hit = await loadPublicShare(deps, token);
  if (!hit.ok) return hit.res;
  return json(
    200,
    { program: hit.program, code: token, expiresAt: hit.row.expires_at, schemaVersion: hit.row.schema_version },
    SHARE_NO_STORE,
  );
}

/** `POST /programs/share/:token/report` — rate-limited abuse report; only a reason category is stored. */
async function shareReportHandler(deps: AppDeps, req: Request, url: URL): Promise<Response> {
  if (!deps.api) return json(404, { error: "not found" }, SHARE_NO_STORE);
  const token = shareTokenFromPath(url.pathname, "/programs/share/", "/report");
  if (!token || !SHARE_TOKEN_RE.test(token)) return json(404, { error: "share not found" }, SHARE_NO_STORE);
  const ip = req.headers.get("cf-connecting-ip") ?? "anon";
  if (deps.limiter && !(await deps.limiter(`share:report:${ip}`))) {
    return json(429, { error: "Too many reports. Try again in a minute." }, SHARE_NO_STORE);
  }
  const body = await readJsonBody(req);
  if ("error" in body) return body.error;
  const reason = (body.value as { reason?: unknown }).reason;
  if (typeof reason !== "string" || !(SHARE_REPORT_REASONS as readonly string[]).includes(reason)) {
    return json(400, { error: `reason must be one of ${SHARE_REPORT_REASONS.join(", ")}` }, SHARE_NO_STORE);
  }
  const api = deps.api;
  const row = await api.queries.getProgramShareByTokenHash(await sha256hex(token));
  if (!row) return json(404, { error: "share not found" }, SHARE_NO_STORE);
  await api.queries.reportProgramShare(
    row.token_hash, reason, (api.now?.() ?? new Date()).toISOString(), SHARE_REPORT_REVIEW_BATCH,
  );
  return json(202, { ok: true }, SHARE_NO_STORE);
}

/** `GET /p/:token` — minimal inert HTML fallback for link previews and non-app browsers. */
async function sharePreviewHandler(deps: AppDeps, req: Request, url: URL): Promise<Response> {
  const unavailable = (status: number, message: string): Response =>
    new Response(`<!doctype html>\n<html lang="en"><head><meta charset="utf-8"><title>Link unavailable</title></head><body><p>${message}</p></body></html>`, {
      status,
      headers: SHARE_HTML_HEADERS,
    });
  if (!deps.api) return unavailable(404, "This link is no longer available.");
  const token = shareTokenFromPath(url.pathname, "/p/");
  if (!token || !SHARE_TOKEN_RE.test(token)) return unavailable(404, "This link is no longer available.");
  const ip = req.headers.get("cf-connecting-ip") ?? "anon";
  if (deps.limiter && !(await deps.limiter(`share:get:${ip}`))) {
    return unavailable(429, "Too many requests. Try again in a minute.");
  }
  // Same fail-closed lookup, but the page never distinguishes why (no existence oracle).
  const hit = await loadPublicShare(deps, token);
  if (!hit.ok) return unavailable(404, "This link is no longer available.");
  return new Response(sharePreviewHtml(hit.program, token, hit.row.expires_at), { status: 200, headers: SHARE_HTML_HEADERS });
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
  // Publish an unlisted share: rights-confirmed, allowlisted, bounded, token minted server-side.
  if (req.method === "POST" && p === "/programs/share") {
    const user = await bearerUser();
    if (!user) return json(401, { error: "unauthorized" });
    // Publish is the one owner-scoped route that mints a durable public capability, so it is
    // rate-limited by owner *and* IP: a stolen session cannot fan shares out from many machines,
    // and one machine cannot spend other owners' budgets.
    const ip = req.headers.get("cf-connecting-ip") ?? "anon";
    if (deps.limiter && !(await deps.limiter(`share:publish:${user.id}:${ip}`))) {
      return json(429, { error: "Too many shares created. Try again in a minute." }, SHARE_NO_STORE);
    }
    const body = await readBody();
    if (body === null) return json(400, { error: "invalid JSON" });
    if (body.rightsConfirmed !== true) return json(400, { error: "rightsConfirmed must be true" });
    // `errorCode` (not `code`) so a rejected publish can never look like an issued share code.
    const parsed = parseShareProgram(body.program);
    if (!parsed.ok) return json(parsed.status, { error: parsed.error, errorCode: parsed.code });
    const ttlDays = body.expiresInDays === undefined ? SHARE_DEFAULT_TTL_DAYS : body.expiresInDays;
    if (typeof ttlDays !== "number" || !Number.isInteger(ttlDays) || ttlDays < 1 || ttlDays > SHARE_MAX_TTL_DAYS) {
      return json(400, { error: `expiresInDays must be an integer 1-${SHARE_MAX_TTL_DAYS}` });
    }
    const now = api.now?.() ?? new Date();
    // Hard cap on live shares per owner: bounds both moderation load and the blast radius of a
    // compromised session. Only active, unexpired shares count, so revoking frees a slot.
    if ((await q.countActiveProgramShares(user.id, now.toISOString())) >= SHARE_MAX_ACTIVE_PER_OWNER) {
      return json(
        429,
        { error: `Too many active shares (max ${SHARE_MAX_ACTIVE_PER_OWNER}). Revoke one to share another.` },
        SHARE_NO_STORE,
      );
    }
    const payload = JSON.stringify(parsed.program);
    const createdAt = now.toISOString();
    const expiresAt = new Date(now.getTime() + ttlDays * 86400_000).toISOString();
    // ponytail: a token collision is ~2^-256; retry a couple of times so it never loses a publish
    let token = randomToken();
    for (let attempt = 0; ; attempt++) {
      try {
        await q.insertProgramShare({
          id: crypto.randomUUID(),
          token_hash: await sha256hex(token),
          token_prefix: token.slice(0, 8),
          owner_id: user.id,
          payload,
          payload_hash: await sha256hex(payload),
          schema_version: SHARE_SCHEMA_VERSION,
          status: "active",
          created_at: createdAt,
          expires_at: expiresAt,
          revoked_at: null,
          report_count: 0,
          last_reported_at: null,
          last_report_reason: null,
        });
        break;
      } catch (e) {
        if (attempt >= 2) throw e;
        token = randomToken();
      }
    }
    return json(
      201,
      { code: token, url: `https://regulift.app/p/${token}`, expiresAt, schemaVersion: SHARE_SCHEMA_VERSION },
      SHARE_NO_STORE,
    );
  }
  // Owner-only revoke of an unlisted share (idempotent; a revoked row keeps its original payload).
  if (req.method === "DELETE" && p.startsWith("/programs/share/")) {
    const user = await bearerUser();
    if (!user) return json(401, { error: "unauthorized" });
    const token = shareTokenFromPath(p, "/programs/share/");
    if (!token || !SHARE_TOKEN_RE.test(token)) return json(404, { error: "share not found" });
    const row = await q.getProgramShareByTokenHash(await sha256hex(token));
    if (!row) return json(404, { error: "share not found" });
    if (row.owner_id !== user.id) return json(403, { error: "forbidden" });
    await q.revokeProgramShare(row.id, user.id, (api.now?.() ?? new Date()).toISOString());
    return json(200, { ok: true, revoked: true });
  }
  if (p.startsWith("/social/")) {
    const socialUser = await bearerUser();
    if (!socialUser) return json(401, { error: "unauthorized" });
    const r = await handleSocial(req, url, socialUser, q, { now: api.now });
    if (r) return r;
  }
  return null;
}
