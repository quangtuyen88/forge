import type { AiBinding } from "./providers.js";

export const WHISPER_TURBO = "@cf/openai/whisper-large-v3-turbo";
export const WHISPER = "@cf/openai/whisper";

export interface TranscribeResult {
  text: string;
  language?: string;
}

export interface TranscribeEnv {
  AI?: AiBinding;
}

/** Chunked base64 so a 6 MB clip never overflows `String.fromCharCode`'s argument list. */
function toBase64(bytes: Uint8Array): string {
  let binary = "";
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(binary);
}

/**
 * Transcribes raw audio with Workers AI Whisper. Tries the turbo model first and
 * falls back to the base model when turbo is unavailable. Audio bytes are only
 * ever base64-encoded here — never logged.
 */
export async function transcribeAudio(
  env: TranscribeEnv,
  bytes: Uint8Array,
  language?: string,
  prompt?: string,
): Promise<TranscribeResult> {
  if (!env.AI) throw new Error("whisper: AI binding missing");
  const input: Record<string, string> = { audio: toBase64(bytes) };
  if (language) input.language = language;
  if (prompt) input.initial_prompt = prompt;
  for (const model of [WHISPER_TURBO, WHISPER]) {
    try {
      const out = (await env.AI.run(model, input)) as { text?: string; language?: string };
      if (typeof out?.text === "string") {
        return out.language ? { text: out.text, language: out.language } : { text: out.text };
      }
      throw new Error(`whisper ${model}: no text returned`);
    } catch (e) {
      if (model === WHISPER) throw e;
      console.error(`whisper ${model} failed, falling back to ${WHISPER}`);
    }
  }
  throw new Error("whisper: no model available");
}
