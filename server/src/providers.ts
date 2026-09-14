export type Provider = "claude" | "gemini";

export interface Message {
  role: "user" | "assistant";
  content: string;
}

export interface ProviderEnv {
  ANTHROPIC_API_KEY?: string;
  GEMINI_API_KEY?: string;
}

export async function complete(
  p: Provider,
  system: string,
  messages: Message[],
  env: ProviderEnv,
): Promise<string> {
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
      body: JSON.stringify({ model: "claude-sonnet-5", max_tokens: 600, system, messages }),
    });
    if (!res.ok) throw new Error(`${res.status}: ${await res.text()}`);
    const data: { content: { text?: string }[] } = await res.json();
    return data.content.map((b) => b.text ?? "").join("");
  }
  const res = await fetch(
    `https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${env.GEMINI_API_KEY ?? ""}`,
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
