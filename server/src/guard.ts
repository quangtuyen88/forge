export const MEDICAL_TERMS = [
  "pain",
  "injury",
  "injured",
  "hurt",
  "tear",
  "torn",
  "sprain",
  "strain",
  "tendon",
  "tendinitis",
  "rehab",
  "physio",
  "surgery",
  "doctor",
  "medication",
  "supplement dose",
  "steroid",
  "pregnan",
  "diagnos",
  "numb",
  "tingling",
  "dizzy",
  "chest pain",
] as const;

// Deliberate stems: match pregnancy/pregnant, diagnose/diagnosis without trailing boundary.
// Everything else is a full word with common inflections; "numb" must not match "number".
const STEMS = new Set(["pregnan", "diagnos"]);

const MEDICAL_RE = new RegExp(
  MEDICAL_TERMS.map((t) =>
    STEMS.has(t) ? `\\b${t}` : `\\b${t}(?:s|es|ed|ing)?\\b`,
  ).join("|"),
  "i",
);

export function classify(question: string): "training" | "medical" {
  return MEDICAL_RE.test(question) ? "medical" : "training";
}
