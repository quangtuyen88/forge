import { COACH_KB, type KbEntry } from "./coach-kb.generated.js";

export interface KnowledgeDeps {
  mode: "off" | "shadow" | "enabled"; // off = never retrieve; shadow = retrieve + log only
  search?: (request: unknown) => Promise<unknown>; // the COACH_KB binding's search()
  deny?: ReadonlySet<string>; // "doc_id" or "doc_id@locale" withdrawn right now
  timeoutMs?: number; // default 1500
  minScore?: number; // default 0.35
}

/** Locales with reviewed kb1 articles; ja/ko stay on the no-retrieval route. */
export const REVIEWED_LOCALES = new Set(["en", "vi"]);

/** Canonical nonpersonal topics the app can name without any network call. Checked in order. */
export const EXACT_TOPICS: { doc_id: string; re: RegExp }[] = [
  { doc_id: "program.week", re: /\b(?:roadmap|program week|which week|week \d+)\b|lộ trình|tuần chương trình|tuần \d+|ロードマップ|第\d+週|로드맵|\d+주차/iu },
  { doc_id: "plan.change_scope", re: /\b(?:start|begin)\b[^.?!]{0,30}\b(?:next|on|from)\b[^.?!]{0,15}\b(?:monday|tuesday|wednesday|thursday|friday|saturday|sunday|week)\b|\btakes? effect\b|bắt đầu từ thứ|có hiệu lực|thứ (?:hai|ba|tư|năm|sáu|bảy) (?:tới|tuần sau)/iu },
  { doc_id: "effort.target_vs_reported", re: /\bRPE\b|\beffort\b|gắng sức/iu },
];

export interface KbResult {
  route: "none" | "exact" | "semantic";
  status: "disabled" | "skipped" | "hit" | "none" | "timeout" | "error";
  docs: KbEntry[];
  ms: number;
  searchCalls: number;
}

function isObj(v: unknown): v is Record<string, unknown> {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

function denied(deny: ReadonlySet<string> | undefined, docId: string, locale: string): boolean {
  return !!deny && (deny.has(docId) || deny.has(`${docId}@${locale}`));
}

function publishedEntry(docId: string, locale: string): KbEntry | undefined {
  return COACH_KB.entries.find((e) => e.doc_id === docId && e.locale === locale && e.status === "published");
}

const TIMEOUT = Symbol("kb-timeout");

/** One retrieval decision per turn: exact topic first (no network), else one bounded AI Search call. */
export async function retrieveReferences(
  deps: KnowledgeDeps | undefined,
  question: string,
  locale: string,
): Promise<KbResult> {
  const started = Date.now();
  const none = (route: KbResult["route"], status: KbResult["status"]): KbResult => ({
    route, status, docs: [], ms: Date.now() - started, searchCalls: 0,
  });
  if (!deps || deps.mode === "off") return none("none", "disabled");
  if (!REVIEWED_LOCALES.has(locale)) return none("none", "skipped");

  const q = question.normalize("NFC");
  for (const topic of EXACT_TOPICS) {
    if (!topic.re.test(q)) continue;
    const entry = publishedEntry(topic.doc_id, locale);
    if (entry && !denied(deps.deny, entry.doc_id, entry.locale)) {
      return { route: "exact", status: "hit", docs: [entry], ms: Date.now() - started, searchCalls: 0 };
    }
    return { ...none("exact", "none"), status: "none" };
  }

  if (!deps.search) return none("none", "skipped");

  // One search per turn; the query is the question only — never context, data, history or notes.
  const request = {
    query: question.trim().slice(0, 500),
    ai_search_options: {
      retrieval: {
        retrieval_type: "hybrid",
        max_num_results: 4,
        context_expansion: 0,
        filters: { locale, policy_version: COACH_KB.policy_version, status: "published" },
      },
      query_rewrite: { enabled: false },
      reranking: { enabled: false },
    },
  };
  const timeoutMs = deps.timeoutMs ?? 1500;
  const minScore = deps.minScore ?? 0.35;
  let timer: ReturnType<typeof setTimeout> | undefined;
  const searchCalls = 1;
  const done = (status: KbResult["status"], docs: KbEntry[]): KbResult => ({
    route: "semantic", status, docs, ms: Date.now() - started, searchCalls,
  });
  try {
    const raced = await Promise.race([
      (async () => deps.search!(request))(),
      new Promise<typeof TIMEOUT>((resolve) => {
        timer = setTimeout(() => resolve(TIMEOUT), timeoutMs);
      }),
    ]);
    if (raced === TIMEOUT) return done("timeout", []);
    if (!isObj(raced) || !Array.isArray(raced.chunks)) return done("error", []);
    // Every returned chunk is untrusted: score gate, metadata checks, manifest match, deny list.
    const docs: KbEntry[] = [];
    const seen = new Set<string>();
    for (const chunk of raced.chunks) {
      if (!isObj(chunk) || typeof chunk.score !== "number" || chunk.score < minScore) continue;
      const item = isObj(chunk.item) ? chunk.item : undefined;
      const meta = item && isObj(item.metadata) ? item.metadata : undefined;
      if (!meta) continue;
      const { doc_id, locale: chunkLocale, policy_version, status } = meta;
      if (
        typeof doc_id !== "string" || typeof chunkLocale !== "string" ||
        typeof policy_version !== "string" || typeof status !== "string" ||
        status !== "published" || policy_version !== COACH_KB.policy_version || chunkLocale !== locale
      ) {
        continue;
      }
      if (seen.has(doc_id)) continue; // deduplicate by doc_id in score order
      const entry = publishedEntry(doc_id, chunkLocale);
      if (!entry || denied(deps.deny, entry.doc_id, entry.locale)) continue;
      seen.add(doc_id);
      docs.push(entry);
      if (docs.length === 2) break;
    }
    return done(docs.length > 0 ? "hit" : "none", docs);
  } catch {
    return done("error", []); // never retry; a late result after timeout is ignored
  } finally {
    if (timer !== undefined) clearTimeout(timer);
  }
}
