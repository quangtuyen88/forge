import { isPromptAttack } from "./guard-input.js";

/** Authoritative app state sent by the client; parsed strictly, rendered into the system prompt. */
export interface CoachContract {
  contract_version: "coach-contract-v1";
  capabilities: { deferred_plan_start_supported: boolean; approved_change_scope: "next_unstarted_session" };
  program?: {
    week_basis: "completed_sessions";
    computed_week: number;
    weeks_in_block: number;
    deload_week: number;
    completed_sessions_since_block_start: number;
    sessions_per_program_week: number;
    block_start: string;
  };
  proposal?: {
    type: "adjustPlan" | "swap" | "earlyDeload" | "restartBlock" | "remember";
    status: "ready" | "stale" | "applied" | "declined" | "expired";
    summary: string;
  } | null;
  commit_receipt?: { type: string; applied_at: string } | null;
}

const PROPOSAL_TYPES = ["adjustPlan", "swap", "earlyDeload", "restartBlock", "remember"] as const;
const PROPOSAL_STATUSES = ["ready", "stale", "applied", "declined", "expired"] as const;
const ISO_DATE_RE = /^\d{4}-\d{2}-\d{2}$/;
const ISO_DATETIME_RE = /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$/;
const CONTROL_RE = /[\u0000-\u001f\u007f]/;

function isObj(v: unknown): v is Record<string, unknown> {
  return !!v && typeof v === "object" && !Array.isArray(v);
}

function intBetween(v: unknown, lo: number, hi: number): v is number {
  return typeof v === "number" && Number.isInteger(v) && v >= lo && v <= hi;
}

/** "YYYY-MM-DD" that is also a real calendar date. */
function validDate(s: string): boolean {
  if (!ISO_DATE_RE.test(s)) return false;
  const [y, m, d] = s.split("-").map(Number);
  const dt = new Date(Date.UTC(y, m - 1, d));
  return dt.getUTCFullYear() === y && dt.getUTCMonth() === m - 1 && dt.getUTCDate() === d;
}

/** Strict parse: anything malformed (wrong version, types, ranges, enums, dates, prompt attacks,
 *  control characters) rejects the whole contract with undefined. Unknown extra keys are ignored. */
export function parseContract(raw: unknown): CoachContract | undefined {
  if (!isObj(raw) || raw.contract_version !== "coach-contract-v1") return undefined;
  const cap = raw.capabilities;
  if (!isObj(cap) || typeof cap.deferred_plan_start_supported !== "boolean" || cap.approved_change_scope !== "next_unstarted_session") {
    return undefined;
  }
  const contract: CoachContract = {
    contract_version: "coach-contract-v1",
    capabilities: {
      deferred_plan_start_supported: cap.deferred_plan_start_supported,
      approved_change_scope: "next_unstarted_session",
    },
  };
  if (raw.program !== undefined) {
    const p = raw.program;
    if (!isObj(p) || p.week_basis !== "completed_sessions") return undefined;
    if (
      !intBetween(p.computed_week, 1, 12) ||
      !intBetween(p.weeks_in_block, 1, 12) ||
      !intBetween(p.deload_week, 1, 12) ||
      !intBetween(p.completed_sessions_since_block_start, 0, 1000) ||
      !intBetween(p.sessions_per_program_week, 1, 7) ||
      typeof p.block_start !== "string" ||
      !validDate(p.block_start)
    ) {
      return undefined;
    }
    contract.program = {
      week_basis: "completed_sessions",
      computed_week: p.computed_week,
      weeks_in_block: p.weeks_in_block,
      deload_week: p.deload_week,
      completed_sessions_since_block_start: p.completed_sessions_since_block_start,
      sessions_per_program_week: p.sessions_per_program_week,
      block_start: p.block_start,
    };
  }
  if (raw.proposal === null) {
    contract.proposal = null;
  } else if (raw.proposal !== undefined) {
    const pr = raw.proposal;
    if (
      !isObj(pr) ||
      typeof pr.type !== "string" || !(PROPOSAL_TYPES as readonly string[]).includes(pr.type) ||
      typeof pr.status !== "string" || !(PROPOSAL_STATUSES as readonly string[]).includes(pr.status)
    ) {
      return undefined;
    }
    const summary = typeof pr.summary === "string" ? pr.summary.trim() : "";
    if (!summary || summary.length > 120 || isPromptAttack(summary) || CONTROL_RE.test(summary)) return undefined;
    contract.proposal = { type: pr.type as NonNullable<CoachContract["proposal"]>["type"], status: pr.status as NonNullable<CoachContract["proposal"]>["status"], summary };
  }
  if (raw.commit_receipt === null) {
    contract.commit_receipt = null;
  } else if (raw.commit_receipt !== undefined) {
    const cr = raw.commit_receipt;
    if (
      !isObj(cr) ||
      typeof cr.type !== "string" || !cr.type || cr.type.length > 40 ||
      isPromptAttack(cr.type) || CONTROL_RE.test(cr.type) ||
      typeof cr.applied_at !== "string" || !ISO_DATETIME_RE.test(cr.applied_at) || Number.isNaN(Date.parse(cr.applied_at))
    ) {
      return undefined;
    }
    contract.commit_receipt = { type: cr.type, applied_at: cr.applied_at };
  }
  return contract;
}

const PROPOSAL_STATUS_WORDING: Record<"ready" | "stale" | "applied" | "declined" | "expired", string> = {
  ready: "status ready: the lifter applies it with the card's Apply button",
  stale: "status stale: it can no longer be applied; offer to prepare a fresh one",
  expired: "status expired: it can no longer be applied; offer to prepare a fresh one",
  applied: "status applied",
  declined: "status declined",
};

/** Plain English lines for the system prompt; the app state is authoritative. */
export function renderContract(c: CoachContract): string {
  const lines = ["APP CONTRACT (authoritative app state; it overrides references, conversation history and your own assumptions):"];
  if (!c.capabilities.deferred_plan_start_supported) {
    lines.push("- A plan change applies from the next unstarted session. A later start date is not supported.");
  }
  if (c.program) {
    const p = c.program;
    lines.push(
      `- Program week: ${p.computed_week} of ${p.weeks_in_block}, counted from completed sessions: ` +
        `${p.completed_sessions_since_block_start} completed since the block started on ${p.block_start}, ` +
        `${p.sessions_per_program_week} sessions per program week. Week ${p.deload_week} is the deload week.`,
    );
  }
  if (c.proposal) {
    lines.push(`- Pending proposal: ${c.proposal.type} (${c.proposal.summary}), ${PROPOSAL_STATUS_WORDING[c.proposal.status]}.`);
  } else {
    lines.push("- No pending proposal.");
  }
  lines.push(
    c.commit_receipt
      ? `- Applied: ${c.commit_receipt.type} at ${c.commit_receipt.applied_at}.`
      : "- No change has been applied in this conversation.",
  );
  return lines.join("\n");
}

// Plan-change vocabulary (moved from app.ts; re-exported there so behaviour is unchanged).
export const PLAN_CHANGE_INTENT_RE = /\b(day|days|week|weekly|minute|minutes|min|hour|goal|strength|muscle|hypertrophy|split|full[- ]?body|upper|lower|push|pull|legs|schedule|program|programme|plan)\b|ngày(?!\s*(?:mai|kia|hôm)\b)|tuần|buổi|phút|giờ|mục tiêu|sức mạnh|tăng cơ|lịch|chương trình|kế hoạch|toàn thân|rảnh|(?<![明今昨本後])日|週|回|分|時間|目標|筋力|筋肥大|分割|全身|スケジュール|プログラム|プラン|計画|요일|주(?!세요|시|십시오)|회|분|시간|목표|근력|근비대|분할|전신|스케줄|일정|프로그램|계획|플랜|이틀/i;

export const APPLY_INTENT_RE = /\b(apply|confirm)\b|áp dụng|xác nhận|適用|確定|적용|확정/i;

/** A short bare "apply it" answer to the pending proposal — never a plan request. */
export function isApplyRequest(question: string): boolean {
  const q = question.normalize("NFC");
  return q.length <= 60 && APPLY_INTENT_RE.test(q) && !PLAN_CHANGE_INTENT_RE.test(q);
}

// Post-model consistency checks: claims the model makes that only the app can verify.
export const CARD_CLAIM_RE =
  /\breview (?:it |this |that |them |the change |the changes )?below\b|\bconfirm below\b|\bsee (?:it |the card )?below\b|\bcard below\b|\bprepared\b[^.]{0,60}\bbelow\b|(?:xem|xem lại|xem xét|kiểm tra|xác nhận)[^.]{0,20}(?:bên dưới|ở dưới|phía dưới)|thẻ (?:bên dưới|ở dưới)|chuẩn bị[^.]{0,60}(?:bên dưới|ở dưới)|下(?:で|の|に)(?:確認|カード|表示)|以下(?:で|の)(?:確認|カード)|아래(?:에서|의)? ?(?:확인|검토|카드)/i;

export const APPLIED_CLAIM_RE =
  /\b(?:is|are) now (?:set|updated|changed|applied|active)\b|\bhas been (?:applied|updated|changed|saved|set)\b|\bI(?:'ve| have) (?:applied|updated|changed|saved)\b|\bapplied (?:it|the change|your (?:new )?plan)\b|\bnow set to\b|đã (?:được )?áp dụng(?!\s+(?:sẽ|bắt đầu|vẫn|chỉ)(?:\s|[,.!?]|$))|đã cập nhật|đã được cập nhật|đã thay đổi kế hoạch|đã lưu thay đổi|適用しました|適用されました|更新しました|更新されました|変更しました|変更されました|적용했|적용되었|적용됐|업데이트했|업데이트되었|변경했|변경되었|변경됐/i;

export const DEFERRED_START_RE = new RegExp(
  [
    String.raw`\b(?:start(?:s|ed|ing)?|begin(?:s|ning)?|appl(?:y|ies|ied|ying)|activat(?:e|es|ed|ing)|switch(?:es|ed|ing)?)\b(?:\s+(?:it|that|this|them|(?:the|my)\s+(?:new\s+)?(?:plan|program|programme|change|changes|schedule)))?\s+(?:on|from|next|in|at|starting)\b[^.?!\n]{0,20}?\b(?:(?:mon|tues|wednes|thurs|fri|satur|sun)day|next\s+(?:week|month)|the\s+\d{1,2}(?:st|nd|rd|th)?|\d{1,2}(?:st|nd|rd|th)|january|february|march|april|june|july|august|september|october|november|december)\b`,
    String.raw`(?:bắt đầu|áp dụng|chuyển|đổi)[^.?!\n]{0,60}?(?:từ|vào|kể từ)\s+(?:(?:đầu|cuối|giữa)\s+)?(?:thứ\s+(?:hai|ba|tư|năm|sáu|bảy)|chủ\s+nhật|tuần\s+(?:sau|tới)|tháng\s+(?:sau|tới)|ngày\s+\d{1,2})`,
    String.raw`(?:再来週|来週|来月|[月火水木金土日]曜日?|[0-9０-９]{1,2}日)[^。？！?!\n]{0,12}?(?:から|に)[^。？！?!\n]{0,12}?(?:始め|開始|適用|スタート|切り替え)`,
    String.raw`(?:다음\s*주|다음\s*달|[월화수목금토일]요일|[0-9]{1,2}일)[^.?!\n]{0,12}?(?:부터|에)[^.?!\n]{0,12}?(?:시작|적용)`,
  ].join("|"),
  "iu",
);
const PLAN_NOUN_RE = /\b(?:plans?|program|programme|schedule|changes?|routine)\b|kế hoạch|chương trình|lịch tập|thay đổi|プラン|計画|プログラム|メニュー|変更|플랜|계획|프로그램|루틴|변경/iu;
export const NOT_SUPPORTED_RE = /\bnot (?:yet )?supported\b|\bisn['’]t (?:yet )?supported\b|\bnot (?:yet )?possible\b|\bcan['’]t\b|\bcannot\b|chưa (?:được )?hỗ trợ|không (?:được )?hỗ trợ|không thể|できません|対応していません|未対応|サポートされていません|지원(?:하지|되지) 않|지원 안|할 수 없|불가/iu;

/** A request to begin a plan change on a later day or date, while the app cannot schedule one. */
export function isDeferredStartRequest(question: string, contract?: CoachContract): boolean {
  if (contract?.capabilities.deferred_plan_start_supported) return false;
  const q = question.normalize("NFC");
  return DEFERRED_START_RE.test(q) && (Boolean(contract?.proposal) || PLAN_NOUN_RE.test(q));
}
