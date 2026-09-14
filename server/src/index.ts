import { createServer, type IncomingMessage, type ServerResponse } from "node:http";
import { fileURLToPath, pathToFileURL } from "node:url";
import { dirname, join } from "node:path";
import { loadKnowledge, type Chunk } from "./rag.js";
import { complete } from "./providers.js";
import { createApp, type CompleteFn } from "./app.js";

const PORT = Number(process.env.PORT) || 8787;
const PROVIDER = process.env.PROVIDER === "gemini" ? "gemini" : "claude";
const APP_SECRET = process.env.APP_SECRET;
// ponytail: shared secret; swap for App Attest / Sign in with Apple token before public launch

const chunks: Chunk[] = loadKnowledge(
  join(dirname(fileURLToPath(import.meta.url)), "..", "knowledge"),
);

let providerFn: CompleteFn = (p, system, messages, keys) =>
  complete(p, system, messages, {
    ANTHROPIC_API_KEY: keys.anthropic,
    GEMINI_API_KEY: keys.gemini,
  });

/** Test-only injection point for the upstream model call. */
export function setProvider(fn: CompleteFn): void {
  providerFn = fn;
}

const handleRequest = createApp({
  chunks,
  complete: (p, system, messages, keys) => providerFn(p, system, messages, keys),
  secret: APP_SECRET ?? "",
  provider: PROVIDER,
  keys: { anthropic: process.env.ANTHROPIC_API_KEY, gemini: process.env.GEMINI_API_KEY },
});

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

function send(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, { "content-type": "application/json" });
  res.end(JSON.stringify(body));
}

export const server = createServer(async (req, res) => {
  try {
    const raw = req.method === "POST" ? await readBody(req) : undefined;
    if (raw === null) return send(res, 413, { error: "body too large" });
    const webRes = await handleRequest(
      new Request(`http://${req.headers.host ?? "localhost"}${req.url}`, {
        method: req.method,
        headers: req.headers as Record<string, string>,
        body: raw,
      }),
    );
    res.writeHead(webRes.status, {
      "content-type": webRes.headers.get("content-type") ?? "application/json",
    });
    res.end(await webRes.text());
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
