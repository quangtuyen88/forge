export interface JevChoice {
  choice: string;
  confidence: number;
  probabilities: Record<string, number>;
}

const JEV_URL = "https://api.typesafe.ai/v1/systemone";
const RETRY_MS = 100; // backoff before the single allowed retry on 429/529

/**
 * One choice question to Jev (TypeSafe AI "System One"). Resolves null — never
 * throws — on a missing key, non-2xx (after at most one retry on 429/529),
 * malformed body, or timeout. Logs the failure reason only: the state is the
 * lifter's speech and is never logged.
 */
export async function jevChoice(
  apiKey: string,
  state: string | object,
  instructions: string,
  criteria: Record<string, string>,
  timeoutMs = 1200,
): Promise<JevChoice | null> {
  if (!apiKey) return null;
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const call = (): Promise<Response> =>
    fetch(JEV_URL, {
      method: "POST",
      headers: { authorization: `Bearer ${apiKey}`, "content-type": "application/json" },
      body: JSON.stringify({
        state,
        model: "jev-latest",
        questions: { q: { type: "choice", instructions, criteria } },
      }),
      signal: controller.signal,
    });
  try {
    let res = await call();
    if (res.status === 429 || res.status === 529) {
      await new Promise((resolve) => setTimeout(resolve, RETRY_MS));
      res = await call();
    }
    if (!res.ok) {
      console.error("jev: http", res.status);
      return null;
    }
    const parsed = (await res.json().catch(() => null)) as {
      answers?: { q?: { choice?: unknown; confidence?: unknown; probabilities?: unknown } };
    } | null;
    const answer = parsed?.answers?.q;
    if (
      !answer ||
      typeof answer.choice !== "string" || !answer.choice ||
      typeof answer.confidence !== "number" ||
      !answer.probabilities || typeof answer.probabilities !== "object"
    ) {
      console.error("jev: malformed answer");
      return null;
    }
    return {
      choice: answer.choice,
      confidence: answer.confidence,
      probabilities: answer.probabilities as Record<string, number>,
    };
  } catch {
    console.error("jev: request failed (timeout or network)");
    return null;
  } finally {
    clearTimeout(timer);
  }
}
