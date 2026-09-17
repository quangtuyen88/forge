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

export type Bucket = "training" | "missing_fact" | "ambiguous" | "medical";

export interface Classification {
  bucket: Bucket;
  /** The personal fact the app does not hold (missing_fact only). */
  field?: string;
  /** Two plain-word readings (ambiguous only). */
  options?: string[];
}

/** Personal facts the app does not hold; `field` names the fact for the refusal copy. */
const FACT_FIELDS: Array<{ field: string; re: RegExp }> = [
  { field: "birthday", re: /\bbirthday\b|\bwhen (?:is|was) my birthday\b|\bborn\b/i },
  { field: "age", re: /\bhow old\b|\bmy age\b|\bage\b/i },
  { field: "height", re: /\bheight\b|\bhow tall\b/i },
  { field: "name", re: /\b(?:my|your|real)\s+name\b|\bwho am i\b/i },
  { field: "email", re: /\bemail\b/i },
  { field: "address", re: /\baddress\b|\bwhere (?:do|am) i live\b/i },
];

/** "how much do I weigh" reads as bodyweight or as the prescribed load. */
const WEIGH_RE = /\b(?:how much|what) do i weigh\b/i;

export function classify(question: string, knownFields: string[] = []): Classification {
  const known = new Set(knownFields);
  // Order matters: medical wins over ambiguous, ambiguous wins over missing_fact.
  if (MEDICAL_RE.test(question)) return { bucket: "medical" };
  if (WEIGH_RE.test(question) && !known.has("bodyweight")) {
    return { bucket: "ambiguous", options: ["your bodyweight", "the load you lift"] };
  }
  for (const { field, re } of FACT_FIELDS) {
    if (re.test(question) && !known.has(field)) {
      return { bucket: "missing_fact", field };
    }
  }
  return { bucket: "training" };
}
