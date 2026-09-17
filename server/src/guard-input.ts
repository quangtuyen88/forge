/** Prompt-injection input guards shared by the coach and review paths. */

const INSTRUCTION_RE = /ignore|disregard|system prompt|instruction|act as|jailbreak|developer mode/i;

/**
 * Normalises a lifter note: trim, collapse whitespace, strip newlines, cap at 140 chars.
 * Returns null (drops the note) when it reads like an instruction rather than a fact.
 */
export function sanitizeNote(s: string): string | null {
  const cleaned = s.trim().replace(/\s+/g, " ").slice(0, 140);
  if (!cleaned || INSTRUCTION_RE.test(cleaned)) return null;
  return cleaned;
}

/** Truncates a string to `max` characters (no-op when already short enough). */
export function clampText(s: string, max: number): string {
  return s.length > max ? s.slice(0, max) : s;
}
