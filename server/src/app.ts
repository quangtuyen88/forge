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
}

function json(status: number, body: unknown): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json" },
  });
}

export function createApp(deps: AppDeps): (req: Request) => Promise<Response> {
  const retrieve = deps.retrieve ?? ((q: string) => Promise.resolve(bm25(q, deps.chunks)));
  return async (req) => {
    const url = new URL(req.url);
    try {
      if (req.method === "GET" && url.pathname === "/health") {
        return json(200, { ok: true, providers: deps.providers, chunks: deps.chunks.length });
      }
      if (req.method !== "POST" || url.pathname !== "/coach") {
        return json(404, { error: "not found" });
      }
      if (!deps.secret || req.headers.get("x-forge-secret") !== deps.secret) {
        return json(401, { error: "unauthorized" });
      }
      const ip = req.headers.get("cf-connecting-ip") ?? "anon";
      if (deps.limiter && !(await deps.limiter(ip))) {
        return json(429, { error: "Too many questions. Try again in a minute." });
      }
      if (!String(req.headers.get("content-type") ?? "").includes("application/json")) {
        return json(415, { error: "content-type must be application/json" });
      }
      const raw = await req.text();
      if (raw.length > 64 * 1024) return json(413, { error: "body too large" });
      let parsed: { question?: unknown; context?: unknown; history?: unknown; coach?: unknown };
      try {
        parsed = JSON.parse(raw);
      } catch {
        return json(400, { error: "invalid JSON" });
      }
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
        });
      }
      const top = await retrieve(question);
      const system = buildSystem(context, top, coach);
      const { answer, provider } = await deps.complete(system, [
        ...history,
        { role: "user", content: question },
      ]);
      return json(200, {
        answer,
        refused: false,
        citations: top.map((c) => c.heading),
        provider,
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
