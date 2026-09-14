export type Provider = "workers-ai" | "gemini" | "claude";

export const WORKERS_AI_MODEL = "@cf/meta/llama-3.3-70b-instruct-fp8-fast";
export const GEMINI_MODEL = "gemini-2.5-flash";
export const CLAUDE_MODEL = "claude-haiku-4-5-20251001";

export interface Message {
  role: "user" | "assistant";
  content: string;
}

export interface AiBinding {
  run(model: string, input: unknown): Promise<unknown>;
}

export interface ProviderEnv {
  ANTHROPIC_API_KEY?: string;
  GEMINI_API_KEY?: string;
  AI?: AiBinding;
}

export async function complete(
  p: Provider,
  system: string,
  messages: Message[],
  env: ProviderEnv,
): Promise<string> {
  if (p === "workers-ai") {
    if (!env.AI) throw new Error("workers-ai: AI binding missing");
    const out = (await env.AI.run(WORKERS_AI_MODEL, {
      messages: [{ role: "system", content: system }, ...messages],
      max_tokens: 600,
      temperature: 0.3,
    })) as { response?: string };
    return out.response ?? "";
  }
  const signal = AbortSignal.timeout(20_000);
  if (p === "claude") {
    const res = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      signal,
      headers: {
        "content-type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY ?? "",
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({ model: CLAUDE_MODEL, max_tokens: 600, system, messages }),
    });
    if (!res.ok) throw new Error(`${res.status}: ${await res.text()}`);
    const data: { content: { text?: string }[] } = await res.json();
    return data.content.map((b) => b.text ?? "").join("");
  }
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${env.GEMINI_API_KEY ?? ""}`,
    {
      method: "POST",
      signal,
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        systemInstruction: { parts: [{ text: system }] },
        contents: messages.map((m) => ({
          role: m.role === "assistant" ? "model" : "user",
          parts: [{ text: m.content }],
        })),
      }),
    },
  );
  if (!res.ok) throw new Error(`${res.status}: ${await res.text()}`);
  const data: { candidates?: { content?: { parts?: { text?: string }[] } }[] } = await res.json();
  return data.candidates?.[0]?.content?.parts?.map((p) => p.text ?? "").join("") ?? "";
}

const ALL: Provider[] = ["workers-ai", "gemini", "claude"];

function usable(p: Provider, env: ProviderEnv): boolean {
  if (p === "workers-ai") return !!env.AI;
  if (p === "gemini") return !!env.GEMINI_API_KEY;
  return !!env.ANTHROPIC_API_KEY;
}

/** Primary first, then every usable fallback, deduplicated. May be empty (the app reports it). */
export function providerChain(primary: Provider, env: ProviderEnv): Provider[] {
  return [...new Set([primary, ...ALL])].filter((p) => usable(p, env));
}

export async function completeWithFallback(
  chain: Provider[],
  system: string,
  messages: Message[],
  env: ProviderEnv,
): Promise<{ answer: string; provider: Provider }> {
  let last: string | undefined;
  for (const p of chain) {
    try {
      return { answer: await complete(p, system, messages, env), provider: p };
    } catch (e) {
      last = e instanceof Error ? e.message : String(e);
      console.error(`provider ${p} failed:`, last);
    }
  }
  throw new Error(
    "no provider available: " +
      (last ?? "configure the AI binding, GEMINI_API_KEY or ANTHROPIC_API_KEY"),
  );
}
