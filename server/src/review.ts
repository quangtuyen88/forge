import { LANGUAGE_NAMES } from "./prompt.js";

export type CoachName = "Kai" | "Nova";

/** Matches the number tokens the review contract must preserve (e.g. 100, 92.5, 1,250, 50%). */
const NUMBER_RE = /\d[\d.,]*%?/g;

export function numberTokens(...inputs: string[]): string[] {
  return inputs.flatMap((s) => s.match(NUMBER_RE) ?? []);
}

export function preservesAllNumbers(output: string, ...inputs: string[]): boolean {
  return numberTokens(...inputs).every((t) => output.includes(t));
}

const TONE: Record<CoachName, string> = {
  Kai: "warm, high energy, direct",
  Nova: "calm, precise",
};

export function reviewSystem(coach: CoachName, language = "en"): string {
  const parts = [
    `You are ${coach}, a strength coach inside the Regulift app.`,
    `Rewrite the headline and lines the user sends as exactly two sentences in ${coach}'s tone (${TONE[coach]}).`,
    "Keep every number exactly as written. Do not add new numbers. Do not make medical claims.",
    "Return only the two sentences, with no extra text.",
  ];
  const name = LANGUAGE_NAMES[language];
  if (name) parts.push(`Reply in ${name}.`);
  return parts.join("\n");
}

export function reviewInput(headline: string, lines: string[]): string {
  return `Headline: ${headline}\nLines:\n${lines.map((l) => `- ${l}`).join("\n")}`;
}

export function fallbackText(lines: string[]): string {
  return lines.join(" ");
}
