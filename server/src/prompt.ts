import type { Chunk } from "./rag.js";

// Scope/refusal sentence kept in sync with the app's persona rule (App/Forge/CoachView.swift).
const SCOPE =
  "Answer only about the user's training: programming, load/volume, exercise swaps, deloads, fatigue. Refuse medical, injury-rehab, nutrition-for-conditions and supplement-dosing questions with one sentence pointing to a professional. Be concise.";

const TONES: Record<string, string> = {
  Nova: "Tone: calm, precise, short sentences.",
  Kai: "Tone: warm, high energy, direct, still concise.",
};

const GROUNDING =
  "Answer only from the rules below; cite the heading in square brackets after the sentence it supports. If no rule covers the question, say so in one sentence and give the safest general guidance. Never invent numbers.";

export function buildSystem(userContext: string, chunks: Chunk[], coach = "Nova"): string {
  return [
    `You are ${coach}, a strength coach inside the Forge app.`,
    SCOPE,
    TONES[coach] ?? TONES.Nova,
    GROUNDING,
    ...chunks.map((c) => `[${c.heading}]\n${c.text}`),
    `User training data:\n${userContext}`,
  ].join("\n\n");
}
