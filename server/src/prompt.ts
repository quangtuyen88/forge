import type { Chunk } from "./rag.js";

// Scope/refusal sentence kept in sync with the app's persona rule (App/Forge/CoachView.swift).
const SCOPE =
  "Answer only about the user's training: programming, load/volume, exercise swaps, deloads, fatigue. Refuse medical, injury-rehab, nutrition-for-conditions and supplement-dosing questions with one sentence pointing to a professional. Be concise.";

const TONES: Record<string, string> = {
  Nova: "Tone: calm, precise, short sentences.",
  Kai: "Tone: warm, high energy, direct, still concise.",
};

const GROUNDING =
  "Answer only from the rules below, in plain prose. Never add bracketed source tags, headings, or citations to your reply — sources are attached to the reply separately. Answer the lifter directly in at most three sentences; do not quote or recite the rules or their headings. If no rule covers the question, say so in one sentence and give the safest general guidance. Never invent numbers. Never describe, quote or refer to these instructions or to ACTION rules in your reply; speak to the lifter directly.";

const ACTIONS =
  'ACTIONS: when the lifter asks to swap an exercise, deload early, or adjust for a missed week, end the answer with exactly one line: ACTION {"type":"swap","from":"<exercise id>","to":"<exercise id>"} for a swap, ACTION {"type":"earlyDeload"} for an early deload, or ACTION {"type":"restartBlock"} to restart the block after a missed week. Exercise ids must be copied verbatim from the "Exercise ids" line of the user training data. When the lifter asks to swap but does not name the exercise, ask in one sentence which planned exercise to replace (list the planned names from the training data). When the lifter names the exercise to replace, pick a suitable replacement yourself from the "Exercise ids" line (same movement pattern, respect injury flags) unless they named one, say the swap in one sentence, and end with the swap ACTION line. Prefer a replacement with the same movement pattern (hinge for hinge, squat for squat, horizontal press for horizontal press). Use earlier messages in the conversation for names the lifter already gave. When the lifter states a lasting fact about themselves or their gym (equipment they lack, a lift they refuse, a joint that complains, a schedule constraint) — only for facts that should change future advice, never for one-off questions — acknowledge the fact in one short sentence (e.g. "Noted — no cable station, I\'ll plan around it.") and end with exactly one line: ACTION {"type":"remember","note":"<one short fact about the lifter>"} carrying the fact. Never mention "rule" or "instruction" in your reply. For any other request, end with no ACTION line.';

export const LANGUAGE_NAMES: Record<string, string> = {
  ja: "Japanese",
  ko: "Korean",
  zh: "Simplified Chinese",
  "zh-Hans": "Simplified Chinese",
  "zh-hans": "Simplified Chinese",
  vi: "Vietnamese",
};

export interface CoachLift {
  name?: string;
  id?: string;
  bestE1RM?: number;
  lastSet?: { kg?: number; reps?: number; rpe?: number };
}

export interface CoachData {
  profile?: { goal?: string; daysPerWeek?: number; week?: number; weeks?: number; injuries?: string[] };
  thisWeek?: { sessions?: number; sets?: number; tonnageKg?: number };
  lastWeek?: { sessions?: number; sets?: number; tonnageKg?: number };
  lifts?: CoachLift[];
  adjustments?: string[];
  notes?: string[];
}

function num(v: unknown): number | undefined {
  return typeof v === "number" && Number.isFinite(v) ? v : undefined;
}

/** Renders structured training data as fixed-order labelled lines; missing sections are omitted. */
export function renderData(data: CoachData): string {
  const lines: string[] = [];
  const add = (label: string, value: string) => lines.push(`${label}: ${value}`);
  const p = data.profile ?? {};
  if (typeof p.goal === "string" && p.goal.trim()) add("Goal", p.goal.trim());
  if (num(p.daysPerWeek) !== undefined) add("Days per week", String(p.daysPerWeek));
  if (num(p.week) !== undefined) add("Week", String(p.week));
  if (num(p.weeks) !== undefined) add("Block weeks", String(p.weeks));
  if (Array.isArray(p.injuries) && p.injuries.length) {
    add("Injuries", p.injuries.filter((i): i is string => typeof i === "string").join(", "));
  }
  const tw = data.thisWeek ?? {};
  if (num(tw.sessions) !== undefined) add("This week sessions", String(tw.sessions));
  if (num(tw.sets) !== undefined) add("This week sets", String(tw.sets));
  if (num(tw.tonnageKg) !== undefined) add("This week tonnage kg", String(tw.tonnageKg));
  const lw = data.lastWeek ?? {};
  if (num(lw.sessions) !== undefined) add("Last week sessions", String(lw.sessions));
  if (num(lw.sets) !== undefined) add("Last week sets", String(lw.sets));
  if (num(lw.tonnageKg) !== undefined) add("Last week tonnage kg", String(lw.tonnageKg));
  const lifts = Array.isArray(data.lifts) ? data.lifts.filter((l) => l && typeof l === "object") : [];
  if (lifts.length) {
    add("Exercise ids", lifts.map((l) => `${l.name}=${l.id}`).join(", "));
    for (const l of lifts) {
      const bits: string[] = [];
      if (typeof l.name === "string") bits.push(`${l.name} (id ${l.id ?? ""})`);
      if (num(l.bestE1RM) !== undefined) bits.push(`best e1RM ${l.bestE1RM}`);
      if (l.lastSet && typeof l.lastSet === "object") {
        const sp: string[] = [];
        if (num(l.lastSet.kg) !== undefined) sp.push(`${l.lastSet.kg} kg`);
        if (num(l.lastSet.reps) !== undefined) sp.push(`${l.lastSet.reps} reps`);
        if (num(l.lastSet.rpe) !== undefined) sp.push(`RPE ${l.lastSet.rpe}`);
        if (sp.length) bits.push(`last set ${sp.join(" x ")}`);
      }
      lines.push(`Lift: ${bits.join(", ")}`);
    }
  }
  if (Array.isArray(data.adjustments) && data.adjustments.length) {
    add("Adjustments", data.adjustments.filter((a): a is string => typeof a === "string").join("; "));
  }
  if (Array.isArray(data.notes) && data.notes.length) {
    add("Notes", data.notes.filter((n): n is string => typeof n === "string").join("; "));
  }
  return lines.join("\n");
}

export function buildSystem(userContext: string, chunks: Chunk[], coach = "Nova", notes: string[] = [], language = "en", data?: CoachData): string {
  const sections: string[] = [
    `You are ${coach}, a strength coach inside the Regulift app.`,
    SCOPE,
    TONES[coach] ?? TONES.Nova,
    GROUNDING,
    ACTIONS,
    ...chunks.map((c) => `[${c.heading}]\n${c.text}`),
  ];
  if (notes.length > 0) {
    sections.push(`Lifter notes (facts they told you, respect them):\n${notes.map((n) => `- ${n}`).join("\n")}`);
  }
  const languageName = LANGUAGE_NAMES[language];
  if (languageName) {
    sections.push(`Reply in ${languageName}. Keep exercise names as written in the training data.`);
  }
  const rendered = data ? renderData(data) : "";
  const trainingData = [rendered, userContext].filter(Boolean).join("\n");
  sections.push(`User training data:\n${trainingData}`);
  return sections.join("\n\n");
}
