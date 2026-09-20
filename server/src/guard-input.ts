/** Prompt-injection input guards shared by the coach and review paths. */

const INSTRUCTION_RE = /ignore|disregard|system prompt|instruction|act as|jailbreak|developer mode/i;

const INVISIBLE_RE = /[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F\u200B-\u200F\u202A-\u202E\u2060-\u206F\uFEFF]/g;

const PROMPT_ATTACK_PATTERNS: readonly RegExp[] = [
  /\b(?:ignore|disregard|forget|override|bypass)\b.{0,80}\b(?:previous|prior|above|system|developer|hidden)\b.{0,40}\b(?:instructions?|prompts?|rules?|messages?)\b/i,
  /\b(?:reveal|show|print|repeat|quote|copy|expose|return)\b.{0,80}\b(?:system|developer|hidden|internal)\b.{0,30}\b(?:prompts?|messages?|instructions?|rules?)\b/i,
  /\b(?:what|tell me)\b.{0,40}\b(?:system prompts?|hidden instructions?|developer messages?|your instructions|your rules)\b/i,
  /\b(?:jailbreak|developer mode|dan mode|prompt injection)\b/i,
  /(?:<\s*\/?\s*(?:system|developer|assistant|tool)\b|\[\s*(?:system|developer|assistant|tool)\s*\]|<<<\s*data)/i,
  /\b(?:act|pretend|role\s*play)\b.{0,40}\b(?:unrestricted|unfiltered|without (?:rules|limits)|developer)\b/i,
  /\b(?:decode|execute|follow)\b.{0,50}\b(?:base64|encoded)\b.{0,30}\b(?:instructions?|prompts?|commands?)\b/i,
  /(?:bỏ qua|phớt lờ).{0,50}(?:chỉ dẫn|hướng dẫn|lời nhắc|quy tắc)/iu,
  /(?:tiết lộ|hiển thị).{0,50}(?:lời nhắc hệ thống|chỉ dẫn hệ thống)/iu,
  /(?:以前|前の|システム).{0,40}(?:指示|プロンプト).{0,20}(?:無視|開示|表示)/u,
  /(?:이전|시스템).{0,40}(?:지시|프롬프트).{0,20}(?:무시|공개|출력)/u,
];

function inspectionText(s: string): string {
  return s.normalize("NFKC").replace(INVISIBLE_RE, "").replace(/\s+/g, " ").slice(0, 10_000);
}

/** High-confidence detector that avoids matching lone words such as “ignore” or “system”. */
export function isPromptAttack(s: string): boolean {
  const inspected = inspectionText(s);
  return PROMPT_ATTACK_PATTERNS.some((pattern) => pattern.test(inspected));
}

/** Checks nested JSON input without trusting caller-selected field names or roles. */
export function containsPromptAttack(value: unknown, depth = 0): boolean {
  if (depth > 8 || value === null || value === undefined) return false;
  if (typeof value === "string") return isPromptAttack(value);
  if (Array.isArray(value)) return value.some((item) => containsPromptAttack(item, depth + 1));
  if (typeof value === "object") {
    return Object.values(value as Record<string, unknown>).some((item) => containsPromptAttack(item, depth + 1));
  }
  return false;
}

/**
 * Normalises a lifter note: trim, collapse whitespace, strip newlines, cap at 140 chars.
 * Returns null (drops the note) when it reads like an instruction rather than a fact.
 */
export function sanitizeNote(s: string): string | null {
  const cleaned = s.trim().replace(/\s+/g, " ").slice(0, 140);
  if (!cleaned || INSTRUCTION_RE.test(cleaned) || isPromptAttack(cleaned)) return null;
  return cleaned;
}

/** Truncates a string to `max` characters (no-op when already short enough). */
export function clampText(s: string, max: number): string {
  return s.length > max ? s.slice(0, max) : s;
}
