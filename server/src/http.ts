export const EMAIL_RE = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export function json(status: number, body: unknown, headers: Record<string, string> = {}): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });
}

type JsonBody = { error: Response } | { value: unknown };

export async function readJsonBody(req: Request): Promise<JsonBody> {
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
