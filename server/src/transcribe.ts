import type { AiBinding } from "./providers.js";

export const WHISPER_TURBO = "@cf/openai/whisper-large-v3-turbo";

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

/** Transcribes raw audio with Workers AI Whisper turbo. Audio bytes are only ever base64-encoded here — never logged. */
export async function transcribeAudio(
  env: TranscribeEnv,
  bytes: Uint8Array,
  language?: string,
  prompt?: string,
): Promise<TranscribeResult> {
  if (!env.AI) throw new Error("whisper: AI binding missing");
  // Without VAD, Whisper turns silence and gym noise into subtitle outros ("Hãy subscribe cho kênh…").
  const input: Record<string, string | boolean> = { audio: toBase64(bytes), vad_filter: true };
  if (language) input.language = language;
  if (prompt) input.initial_prompt = prompt;
  // No fallback: the base Whisper model has no VAD and invents text on silence.
  const out = (await env.AI.run(WHISPER_TURBO, input)) as { text?: string; language?: string };
  if (typeof out?.text !== "string") throw new Error(`whisper ${WHISPER_TURBO}: no text returned`);
  return out.language ? { text: out.text, language: out.language } : { text: out.text };
}
