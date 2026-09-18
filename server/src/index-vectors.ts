// POST /admin/reindex — embeds all chunks and upserts them into VECTORS (batches of 50).
import { loadKnowledgeFromStrings } from "./rag.js";
import { KNOWLEDGE } from "./knowledge.generated.js";
import type { AiBinding } from "./providers.js";
import type { EventsBinding } from "./app.js";
import type { D1Database } from "./db.js";

export interface VectorsBinding {
  query(
    vector: number[],
    opts: { topK: number; returnMetadata: "all" },
  ): Promise<{ matches: { id: string; score: number; metadata?: Record<string, unknown> }[] }>;
  upsert(vectors: { id: string; values: number[]; metadata: Record<string, unknown> }[]): Promise<unknown>;
}

export interface Env {
  APP_SECRET?: string;
  PROVIDER?: string;
  ANTHROPIC_API_KEY?: string;
  GEMINI_API_KEY?: string;
  JEV_API_KEY?: string;
  AI?: AiBinding;
  VECTORS?: VectorsBinding;
  EVENTS?: EventsBinding;
  COACH_LIMIT?: { limit(opts: { key: string }): Promise<{ success: boolean }> };
  DB?: D1Database;
  GOOGLE_CLIENT_ID?: string;
  RESEND_API_KEY?: string;
  RC_WEBHOOK_SECRET?: string;
  RC_SECRET_KEY?: string;
  ADMIN_SECRET?: string;
  ENV?: string;
}

const EMBEDDINGS = "@cf/baai/bge-base-en-v1.5";

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export async function reindex(req: Request, env: Env): Promise<Response> {
  if (!env.AI || !env.VECTORS) {
    return json(501, { error: "AI and VECTORS bindings not configured" });
  }
  if (!env.APP_SECRET || req.headers.get("x-forge-secret") !== env.APP_SECRET) {
    return json(401, { error: "unauthorized" });
  }
  const chunks = loadKnowledgeFromStrings(KNOWLEDGE);
  let upserted = 0;
  for (let i = 0; i < chunks.length; i += 50) {
    const batch = chunks.slice(i, i + 50);
    const { data } = (await env.AI.run(EMBEDDINGS, {
      text: batch.map((c) => `${c.heading}\n${c.text}`),
    })) as { data: number[][] };
    await env.VECTORS.upsert(
      batch.map((c, j) => ({
        id: c.id,
        values: data[j],
        metadata: { file: c.file, heading: c.heading, text: c.text },
      })),
    );
    upserted += batch.length;
  }
  return json(200, { ok: true, upserted });
}
