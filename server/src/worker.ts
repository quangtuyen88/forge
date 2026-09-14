import { completeWithFallback, providerChain, type Provider } from "./providers.js";
import { bm25, loadKnowledgeFromStrings, rrf, type Chunk } from "./rag.js";
import { createApp, type CompleteFn } from "./app.js";
import { KNOWLEDGE } from "./knowledge.generated.js";
import { reindex, type Env } from "./index-vectors.js";

const chunks: Chunk[] = loadKnowledgeFromStrings(KNOWLEDGE);
const byId = new Map(chunks.map((c) => [c.id, c]));

const EMBEDDINGS = "@cf/baai/bge-base-en-v1.5";
const ALL_PROVIDERS: Provider[] = ["workers-ai", "gemini", "claude"];

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
    const primary = ALL_PROVIDERS.includes(env.PROVIDER as Provider)
      ? (env.PROVIDER as Provider)
      : "workers-ai";
    const chain = providerChain(primary, {
      AI: env.AI,
      GEMINI_API_KEY: env.GEMINI_API_KEY,
      ANTHROPIC_API_KEY: env.ANTHROPIC_API_KEY,
    });
    const complete: CompleteFn = (system, messages) =>
      completeWithFallback(chain, system, messages, env);
    return createApp({
      chunks,
      complete,
      secret: env.APP_SECRET ?? "",
      providers: chain,
      retrieve: env.AI && env.VECTORS ? hybridRetrieve(env) : undefined,
      limiter: env.COACH_LIMIT ? (key) => env.COACH_LIMIT!.limit({ key }).then((r) => r.success) : undefined,
    })(req);
  },
};
