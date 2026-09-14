import { complete, type Provider } from "./providers.js";
import { loadKnowledgeFromStrings, type Chunk } from "./rag.js";
import { createApp, type CompleteFn } from "./app.js";
import { KNOWLEDGE } from "./knowledge.generated.js";
import { reindex, type Env } from "./index-vectors.js";

const chunks: Chunk[] = loadKnowledgeFromStrings(KNOWLEDGE);
const byId = new Map(chunks.map((c) => [c.id, c]));

// ponytail: Vectorize path is untested here (no account); BM25 is the default
function vectorRetrieve(env: Env): (q: string) => Promise<Chunk[]> {
  return async (q) => {
    const { data } = (await env.AI!.run("@cf/baai/bge-base-en-v1.5", {
      text: [q],
    })) as { data: number[][] };
    const { matches } = await env.VECTORS!.query(data[0], { topK: 4, returnMetadata: "all" });
    return matches.flatMap((m) => {
      const c = byId.get(m.id);
      return c ? [c] : [];
    });
  };
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    if (req.method === "POST" && new URL(req.url).pathname === "/admin/reindex") {
      return reindex(req, env);
    }
    const provider: Provider = env.PROVIDER === "gemini" ? "gemini" : "claude";
    const completeWithKeys: CompleteFn = (p, system, messages, keys) =>
      complete(p, system, messages, {
        ANTHROPIC_API_KEY: keys.anthropic,
        GEMINI_API_KEY: keys.gemini,
      });
    return createApp({
      chunks,
      complete: completeWithKeys,
      secret: env.APP_SECRET ?? "",
      provider,
      keys: { anthropic: env.ANTHROPIC_API_KEY, gemini: env.GEMINI_API_KEY },
      retrieve: env.AI && env.VECTORS ? vectorRetrieve(env) : undefined,
    })(req);
  },
};
