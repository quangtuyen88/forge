import type { Bucket } from "./guard.js";

export type IssueKind =
  | "prompt_leak"
  | "internal_tag"
  | "medical_disclaimer_misuse"
  | "unsupported_action"
  | "invented_number"
  | "wrong_language";

export interface Issue {
  kind: IssueKind;
  detail: string;
}

/** System-prompt disclosure language and URLs are never part of a coach answer. */
const PROMPT_LEAK_RE = /(?:system|developer|hidden)\s+(?:prompt|message|instructions?)|my instructions|https?:\/\/|www\./i;

/** Reserved data/role markers leaking into the reply, plus a stray ACTION outside the parsed line. */
const INTERNAL_TAG_RE = /<<<DATA|>>>|<\s*\/?\s*(?:system|developer|assistant|tool)\b|\[\s*(?:SYSTEM|DEVELOPER|ASSISTANT|TOOL)\s*\]|(^|\s)Scope:\s|(^|\s)Fatigue:\s/i;

/** Referral or diagnosis language that is only ever legitimate when the bucket is `medical`. */
const MEDICAL_DISCLAIMER_RE = /\b(?:doctor|physio|therapist|medical|diagnos|prescri|healthcare)\b/i;

const ALLOWED_ACTIONS = new Set(["swap", "earlyDeload", "restartBlock", "remember", "none"]);

const ACTION_BLOCK_RE = /ACTION\s*(\{[^{}]*\})/g;

/** A number attached to kg/lb/%/reps/sets. */
const NUMBER_UNIT_RE = /(\d+(?:\.\d+)?)\s*(kg|kgs|lb|lbs|%|reps?|sets?)\b/gi;

// Japanese script (hiragana, katakana, kanji) and Korean hangul.
const JA_RE = /[\u3040-\u30ff\u3400-\u9fff]/;
const KO_RE = /[\uac00-\ud7af]/;

function unitKind(unit: string): string {
  const u = unit.toLowerCase();
  if (u.startsWith("kg")) return "kg";
  if (u.startsWith("lb")) return "lb";
  if (u.startsWith("rep")) return "reps";
  if (u.startsWith("set")) return "sets";
  return "%";
}

function numbersWithUnit(text: string): Array<{ value: number; unit: string }> {
  const out: Array<{ value: number; unit: string }> = [];
  const re = new RegExp(NUMBER_UNIT_RE.source, "gi");
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    out.push({ value: parseFloat(m[1]), unit: unitKind(m[2]) });
  }
  return out;
}

/** A number in the answer is invented when no matching-unit number in source is within a one-decimal rounding. */
function inventedNumbers(answer: string, context: string, data: string): string[] {
  const source = numbersWithUnit(`${context}\n${data}`);
  const invented: string[] = [];
  for (const a of numbersWithUnit(answer)) {
    const close = source.some((s) => s.unit === a.unit && Math.abs(s.value - a.value) <= 0.1001);
    if (!close) invented.push(`${a.value}${a.unit === "%" ? "%" : " " + a.unit}`);
  }
  return invented;
}

/** ACTION blocks that are not the trailing (parsed) line, plus unsupported action types. */
function actionIssues(answer: string): Issue[] {
  const issues: Issue[] = [];
  const trimmed = answer.trimEnd();
  const blocks = [...trimmed.matchAll(ACTION_BLOCK_RE)];
  for (const m of blocks) {
    const after = trimmed.slice((m.index ?? 0) + m[0].length);
    const isTrailing = after.trim() === "";
    if (!isTrailing) {
      issues.push({ kind: "internal_tag", detail: "stray ACTION outside the parsed action line" });
      continue;
    }
    let type: unknown;
    try {
      type = (JSON.parse(m[1]) as Record<string, unknown>).type;
    } catch {
      continue;
    }
    if (typeof type === "string" && type !== "none" && !ALLOWED_ACTIONS.has(type)) {
      issues.push({ kind: "unsupported_action", detail: `action type "${type}"` });
    }
  }
  return issues;
}

export function validateAnswer(args: {
  answer: string;
  bucket: Bucket;
  context: string;
  data: string;
  language: string;
}): Issue[] {
  const { answer, bucket, context, data, language } = args;
  const issues: Issue[] = [];

  if (PROMPT_LEAK_RE.test(answer)) {
    issues.push({ kind: "prompt_leak", detail: "answer leaks system-prompt content or a URL" });
  }
  if (INTERNAL_TAG_RE.test(answer)) {
    issues.push({ kind: "internal_tag", detail: "answer contains an internal data tag or heading" });
  }
  if (bucket !== "medical" && MEDICAL_DISCLAIMER_RE.test(answer)) {
    issues.push({ kind: "medical_disclaimer_misuse", detail: "referral or diagnosis language outside a medical refusal" });
  }
  issues.push(...actionIssues(answer));
  for (const num of inventedNumbers(answer, context, data)) {
    issues.push({ kind: "invented_number", detail: `number not in context or data: ${num}` });
  }
  if (language === "ja" && !JA_RE.test(answer)) {
    issues.push({ kind: "wrong_language", detail: "answer is not Japanese" });
  }
  if (language === "ko" && !KO_RE.test(answer)) {
    issues.push({ kind: "wrong_language", detail: "answer is not Korean" });
  }

  return issues;
}

export function mustReplace(issues: Issue[]): boolean {
  return issues.some((i) =>
    i.kind === "prompt_leak" ||
    i.kind === "internal_tag" ||
    i.kind === "medical_disclaimer_misuse" ||
    i.kind === "invented_number",
  );
}
