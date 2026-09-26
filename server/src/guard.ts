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

// A weight that went up or down without saying whose: body weight or the lifted load.
const WEIGHT_CHANGE_RE =
  /\bweight\b[^.?!]{0,30}\b(?:drop|dropped|fell|fall|went down|go down|down|change|changed|went up|go up|up|increase|increased|decrease|decreased)\b|trọng lượng[^.?!]{0,20}(?:giảm|tăng|xuống|lên|thay đổi|sụt)|重さ[^。？?!]{0,10}(?:減|落|下が|増|上が|変わ)|무게[^.?!]{0,10}(?:줄|떨어|빠졌|늘|올랐|변했|바뀌)/i;
const WEIGHT_SUBJECT_RE =
  /\bbody ?weight\b|\bbodyweight\b|\bscale\b|\bweigh-?in\b|\b(?:loads?|bars?|plates?|lifts?|bench(?:es)?|squats?|deadlifts?|press(?:es)?|rows?|curls?|pull-?ups?|pulldowns?)\b|cân nặng|cơ thể|mức tạ|(?<!\p{L})tạ(?!\p{L})|体重|重量|ベンチ|スクワット|デッドリフト|체중|몸무게|중량|벤치|스쿼트|데드리프트/iu;

export function classify(question: string, knownFields: string[] = []): Classification {
  const known = new Set(knownFields);
  // Order matters: medical wins over ambiguous, ambiguous wins over missing_fact.
  if (MEDICAL_RE.test(question)) return { bucket: "medical" };
  if (WEIGH_RE.test(question) && !known.has("bodyweight")) {
    return { bucket: "ambiguous", options: ["your bodyweight", "the load you lift"] };
  }
  const q = question.normalize("NFC");
  if (WEIGHT_CHANGE_RE.test(q) && !WEIGHT_SUBJECT_RE.test(q)) {
    return { bucket: "ambiguous", options: ["your bodyweight", "the load you lift"] };
  }
  for (const { field, re } of FACT_FIELDS) {
    if (re.test(question) && !known.has(field)) {
      return { bucket: "missing_fact", field };
    }
  }
  return { bucket: "training" };
}
