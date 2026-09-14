import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";
import { bm25, loadKnowledge, type Chunk } from "./rag.js";
import { classify } from "./guard.js";
import { buildSystem } from "./prompt.js";
import { complete, type Message, type Provider } from "./providers.js";

const PORT = Number(process.env.PORT) || 8787;
const PROVIDER: Provider = process.env.PROVIDER === "gemini" ? "gemini" : "claude";
const APP_SECRET = process.env.APP_SECRET;
// ponytail: shared secret; swap for App Attest / Sign in with Apple token before public launch

const chunks: Chunk[] = loadKnowledge(
  join(dirname(fileURLToPath(import.meta.url)), "..", "knowledge"),
);

type ProviderFn = (p: Provider, system: string, messages: Message[]) => Promise<string>;
let providerFn: ProviderFn = (p, system, messages) => complete(p, system, messages, process.env);

/** Test-only injection point for the upstream model call. */
export function setProvider(fn: ProviderFn): void {
  providerFn = fn;
}

function send(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

async function readBody(req: IncomingMessage): Promise<string | null> {
  const parts: Buffer[] = [];
  let size = 0;
  for await (const c of req) {
    size += (c as Buffer).length;
    if (size > 64 * 1024) return null;
    parts.push(c as Buffer);
  }
  return Buffer.concat(parts).toString("utf8");
}

export const server = createServer(async (req, res) => {
  try {
    if (req.method === "GET" && req.url === "/health") {
      return send(res, 200, { ok: true, provider: PROVIDER, chunks: chunks.length });
    }
    if (req.method !== "POST" || req.url !== "/coach") {
      return send(res, 404, { error: "not found" });
    }
    if (!APP_SECRET || req.headers["x-forge-secret"] !== APP_SECRET) {
      return send(res, 401, { error: "unauthorized" });
    }
    if (!String(req.headers["content-type"] ?? "").includes("application/json")) {
      return send(res, 415, { error: "content-type must be application/json" });
    }
    const raw = await readBody(req);
    if (raw === null) return send(res, 413, { error: "body too large" });
    let parsed: { question?: unknown; context?: unknown; history?: unknown };
    try {
      parsed = JSON.parse(raw);
    } catch {
      return send(res, 400, { error: "invalid JSON" });
    }
    const question = typeof parsed.question === "string" ? parsed.question : "";
    if (!question.trim()) return send(res, 400, { error: "question required" });
    const context = typeof parsed.context === "string" ? parsed.context : "";
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
      return send(res, 200, {
        answer: "That's a medical question — please ask a doctor or physiotherapist.",
        refused: true,
        citations: [],
      });
    }
    const top = bm25(question, chunks);
    const system = buildSystem(context, top);
    const answer = await providerFn(PROVIDER, system, [...history, { role: "user", content: question }]);
    return send(res, 200, { answer, refused: false, citations: top.map((c) => c.heading) });
  } catch (e) {
    return send(res, 502, { error: e instanceof Error ? e.message : String(e) });
  }
});

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  if (!APP_SECRET) {
    console.error("APP_SECRET is required");
    process.exit(1);
  }
  server.listen(PORT, () =>
    console.log(`forge-server on :${PORT} (provider ${PROVIDER}, ${chunks.length} chunks)`),
  );
}
