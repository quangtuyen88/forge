import { completeWithFallback, providerChain } from "./providers.js";
import { transcribeAudio } from "./transcribe.js";
import { bm25, loadKnowledgeFromStrings, rrf, type Chunk } from "./rag.js";
import { createApp, type ApiContext, type CompleteFn } from "./app.js";
import { KNOWLEDGE } from "./knowledge.generated.js";
import { reindex, type Env } from "./index-vectors.js";
import { d1Queries, memoryQueries, type Queries } from "./queries.js";
import type { EventsBinding } from "./app.js";

const chunks: Chunk[] = loadKnowledgeFromStrings(KNOWLEDGE);
const byId = new Map(chunks.map((c) => [c.id, c]));

const EMBEDDINGS = "@cf/baai/bge-base-en-v1.5";

// ponytail: module-level so the no-DB dev fallback keeps state across requests in one isolate
let memQueries: Queries | null = null;

function apiContext(env: Env): ApiContext {
  const queries = env.DB ? d1Queries(env.DB) : (memQueries ??= memoryQueries());
  return {
    queries,
    env: {
      GOOGLE_CLIENT_ID: env.GOOGLE_CLIENT_ID,
      RESEND_API_KEY: env.RESEND_API_KEY,
      RC_WEBHOOK_SECRET: env.RC_WEBHOOK_SECRET,
      RC_SECRET_KEY: env.RC_SECRET_KEY,
      ADMIN_SECRET: env.ADMIN_SECRET,
      ENV: env.ENV,
    },
  };
}

// BM25 ∪ vector top 6 → reciprocal rank fusion → top 4. Retrieval must never fail the request.
function hybridRetrieve(env: Env): (q: string) => Promise<Chunk[]> {
  return async (q) => {
    try {
      const { data } = (await env.AI!.run(EMBEDDINGS, { text: [q] })) as { data: number[][] };
      const { matches } = await env.VECTORS!.query(data[0], { topK: 6, returnMetadata: "all" });
      const vectorTop = matches.flatMap((m) => {
        const c = byId.get(m.id);
        return c ? [c] : [];
      });
      return rrf([bm25(q, chunks, 6), vectorTop], 4);
    } catch (e) {
      console.error("hybrid retrieval failed, falling back to BM25:", e);
      return bm25(q, chunks, 4);
    }
  };
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    if (req.method === "POST" && new URL(req.url).pathname === "/admin/reindex") {
      return reindex(req, env);
    }
    const providerEnv = {
      AI: env.AI,
      GEMINI_API_KEY: env.GEMINI_API_KEY,
      ANTHROPIC_API_KEY: env.ANTHROPIC_API_KEY,
    };
    const complete: CompleteFn = (system, messages, tier = "chat") =>
      completeWithFallback(providerChain(providerEnv, tier), system, messages, env);
    const minScore = Number(env.COACH_KB_MIN_SCORE);
    return createApp({
      chunks,
      complete,
      secret: env.APP_SECRET ?? "",
      providers: providerChain(providerEnv, "chat"),
      retrieve: env.AI && env.VECTORS ? hybridRetrieve(env) : undefined,
      limiter: env.COACH_LIMIT ? (key) => env.COACH_LIMIT!.limit({ key }).then((r) => r.success) : undefined,
      events: env.EVENTS,
      transcribe: (audio, language, prompt) => transcribeAudio(env, audio, language, prompt),
      jevApiKey: env.JEV_API_KEY,
      semanticRouteMode: (env.SEMANTIC_ROUTE_MODE as "off" | "shadow" | "enabled") ?? "off",
      knowledge: {
        mode: env.COACH_REFERENCE_RETRIEVAL === "shadow" || env.COACH_REFERENCE_RETRIEVAL === "enabled"
          ? env.COACH_REFERENCE_RETRIEVAL
          : "off",
        search: env.COACH_KB ? (request) => env.COACH_KB!.search(request) : undefined,
        deny: new Set((env.COACH_KB_DENY ?? "").split(",").map((d) => d.trim()).filter(Boolean)),
        minScore: Number.isFinite(minScore) && minScore >= 0 && minScore <= 1 ? minScore : undefined,
      },
      api: apiContext(env),
    })(req);
  },
};
