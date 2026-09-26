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

/** Referral or diagnosis language that is only ever legitimate when the bucket is `medical`. English terms inside \b (ASCII-only in JS); other languages as plain substrings. */
const MEDICAL_DISCLAIMER_RE =
  /\b(?:doctor|physio|therapist|medical|diagnos|prescri|healthcare)\b|bác sĩ|chuyên gia y tế|y tế|vật lý trị liệu|chẩn đoán|kê đơn|医師|医者|医療|理学療法|診断|処方|의사|의료|물리치료|진단|처방/i;

/** Symptom wording in the question that makes a cautious referral legitimate. English terms inside \b (ASCII-only in JS); other languages as plain substrings. */
export const SYMPTOM_RE =
  /\b(?:pain|painful|hurt|hurts|hurting|sore|soreness|ache|aches|aching|injur\w*|strain\w*|sprain\w*|tweak\w*|swollen|swelling|numb\w*|tingl\w*)\b|đau|nhức|chấn thương|sưng|tê|bong gân|căng cơ|痛|怪我|けが|ケガ|捻挫|しびれ|腫れ|아프|아파|통증|부상|다쳤|삐었|저리|부었/i;

const ALLOWED_ACTIONS = new Set(["swap", "earlyDeload", "restartBlock", "remember", "adjustPlan", "none"]);

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

/** Strip thousands grouping ("18,250" → "18250") then decimal commas ("92,5" → "92.5"). */
function normalizeNumbers(text: string): string {
  return text
    .replace(/\b\d{1,3}(?:,\d{3})+\b/g, (m) => m.replace(/,/g, ""))
    .replace(/(\d+),(\d{1,2})(?!\d)/g, "$1.$2");
}

/** A number in the source, bare when no unit follows — a bare figure backs any unit in the answer. */
const SOURCE_NUMBER_RE = /(\d+(?:\.\d+)?)\s*(kg|kgs|lb|lbs|%|reps?|sets?)?\b/gi;

function sourceNumbers(text: string): Array<{ value: number; unit: string | null }> {
  const out: Array<{ value: number; unit: string | null }> = [];
  const re = new RegExp(SOURCE_NUMBER_RE.source, "gi");
  let m: RegExpExecArray | null;
  while ((m = re.exec(text)) !== null) {
    out.push({ value: parseFloat(m[1]), unit: m[2] ? unitKind(m[2]) : null });
  }
  return out;
}

/** A number in the answer is invented when no matching-unit or bare source number is within a one-decimal rounding, and it is not a source number plus or minus a number the lifter asked about. */
function inventedNumbers(answer: string, context: string, data: string, question = ""): string[] {
  const source = sourceNumbers(normalizeNumbers(`${context}\n${data}\n${question}`));
  const asked = sourceNumbers(normalizeNumbers(question)).map((s) => s.value);
  const invented: string[] = [];
  for (const a of numbersWithUnit(normalizeNumbers(answer))) {
    const explained = (s: { value: number; unit: string | null }, target: number) =>
      (s.unit === a.unit || s.unit === null) && Math.abs(target - a.value) <= 0.1001;
    const close =
      source.some((s) => explained(s, s.value)) ||
      source.some((s) => asked.some((q) => explained(s, s.value + q) || explained(s, s.value - q)));
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
  question?: string;
}): Issue[] {
  const { answer, bucket, context, data, language, question } = args;
  const issues: Issue[] = [];

  if (PROMPT_LEAK_RE.test(answer)) {
    issues.push({ kind: "prompt_leak", detail: "answer leaks system-prompt content or a URL" });
  }
  if (INTERNAL_TAG_RE.test(answer)) {
    issues.push({ kind: "internal_tag", detail: "answer contains an internal data tag or heading" });
  }
  if (bucket !== "medical" && !(question && SYMPTOM_RE.test(question.normalize("NFC"))) && MEDICAL_DISCLAIMER_RE.test(answer.normalize("NFC"))) {
    issues.push({ kind: "medical_disclaimer_misuse", detail: "referral or diagnosis language outside a medical refusal" });
  }
  issues.push(...actionIssues(answer));
  for (const num of inventedNumbers(answer, context, data, question ?? "")) {
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
