import type { Chunk } from "./rag.js";

// Same persona rule the app ships today (App/Forge/CoachView.swift).
const PERSONA =
  "You are Forge, a strength coach. Answer only about the user's training: programming, load/volume, exercise swaps, deloads, fatigue. Refuse medical, injury-rehab, nutrition-for-conditions and supplement-dosing questions with one sentence pointing to a professional. Be concise.";

export function buildSystem(userContext: string, chunks: Chunk[]): string {
  return [
    PERSONA,
    "Answer using ONLY these rules when they apply; cite the heading in brackets.",
    ...chunks.map((c) => `[${c.heading}]\n${c.text}`),
    `User training data:\n${userContext}`,
  ].join("\n\n");
}
