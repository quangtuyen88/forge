// Reads coach-knowledge/manifest.json → src/coach-kb.generated.ts (Workers have no filesystem).
// Run via `pnpm gen` / `pnpm kb:hash` (Node 24 strips types natively; no deps).
// Exported validateManifest() is reused by kb-publish.ts.
import { createHash } from "node:crypto";
import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const serverRoot = join(dirname(fileURLToPath(import.meta.url)), "..");
export const kbDir = join(serverRoot, "coach-knowledge");

const LOCALES = new Set(["en", "vi", "ja", "ko"]);
const STATUSES = new Set(["published", "draft", "retired"]);
const DOC_ID_RE = /^[a-z0-9._-]{1,64}$/;
// Scalar metadata fields checked against the 64-byte cap (R2 customMetadata limit).
// Locators/reference lists (content_hash, source_key, source_references) are exempt.
const SCALAR_FIELDS = ["doc_id", "kind", "locale", "title", "status", "reviewed_date", "reviewer_role", "owner_review", "reuse_rights"] as const;

export interface ManifestEntry {
  doc_id: string;
  kind: string;
  locale: string;
  title: string;
  doc_version: number;
  source_key: string;
  content_hash: string;
  status: string;
  reviewed_date: string;
  reviewer_role: string;
  owner_review: string;
  source_references: string[];
  reuse_rights: string;
  related_exercise_ids: string[];
}

export interface Manifest {
  corpus_version: string;
  policy_version: string;
  contract_version: string;
  entries: ManifestEntry[];
}

const isNonEmptyString = (v: unknown): v is string => typeof v === "string" && v.length > 0;
const isStringArray = (v: unknown): v is string[] => Array.isArray(v) && v.every((x) => typeof x === "string");
const bytes = (s: string): number => Buffer.byteLength(s, "utf8");
const sha256 = (data: Buffer): string => "sha256:" + createHash("sha256").update(data).digest("hex");

function fail(problem: string): never {
  console.error(`kb-build: ${problem}`);
  process.exit(1);
}

/** Full manifest validation; throws on the first violation. */
export function validateManifest(manifest: Manifest): void {
  for (const key of ["corpus_version", "policy_version", "contract_version"] as const) {
    if (!isNonEmptyString(manifest[key])) fail(`${key} must be a non-empty string`);
  }
  if (!Array.isArray(manifest.entries)) fail("entries must be an array");
  const seen = new Set<string>();
  for (const [i, e] of manifest.entries.entries()) {
    const where = `entries[${i}] (${e?.doc_id ?? "?"}/${e?.locale ?? "?"})`;
    if (typeof e !== "object" || e === null) fail(`${where}: not an object`);
    const entry = e as Record<string, unknown>;
    for (const f of [
      "doc_id", "kind", "locale", "title", "source_key", "content_hash", "status",
      "reviewed_date", "reviewer_role", "owner_review", "reuse_rights",
    ]) {
      if (!isNonEmptyString(entry[f])) fail(`${where}: ${f} must be a non-empty string`);
    }
    if (typeof entry.doc_version !== "number" || !Number.isInteger(entry.doc_version)) {
      fail(`${where}: doc_version must be an integer`);
    }
    if (!isStringArray(entry.source_references)) fail(`${where}: source_references must be a string[]`);
    if (!isStringArray(entry.related_exercise_ids)) fail(`${where}: related_exercise_ids must be a string[]`);
    if (!LOCALES.has(entry.locale as string)) fail(`${where}: locale "${entry.locale}" not in {en,vi,ja,ko}`);
    if (!STATUSES.has(entry.status as string)) fail(`${where}: status "${entry.status}" not in {published,draft,retired}`);
    if (!DOC_ID_RE.test(entry.doc_id as string)) fail(`${where}: doc_id "${entry.doc_id}" fails ${DOC_ID_RE}`);
    const expectedKey = `published/${manifest.corpus_version}/${entry.locale}/${entry.doc_id}.md`;
    if (entry.source_key !== expectedKey) fail(`${where}: source_key "${entry.source_key}" != "${expectedKey}"`);
    const pair = `${entry.doc_id}/${entry.locale}`;
    if (seen.has(pair)) fail(`${where}: duplicate (doc_id, locale) pair`);
    seen.add(pair);
    for (const f of SCALAR_FIELDS) {
      if (bytes(entry[f] as string) > 64) fail(`${where}: ${f} exceeds 64 UTF-8 bytes`);
    }
    const file = join(kbDir, entry.source_key as string);
    if (!existsSync(file)) fail(`${where}: file not found: ${entry.source_key}`);
    const body = readFileSync(file);
    const hash = sha256(body);
    if (entry.content_hash !== hash) fail(`${where}: content_hash ${entry.content_hash} != file hash ${hash}`);
    const firstLine = body.toString("utf8").split("\n", 1)[0];
    if (firstLine !== `# ${entry.title}`) fail(`${where}: first line "${firstLine}" != "# ${entry.title}"`);
  }
}

function build(): void {
  const manifest: Manifest = JSON.parse(readFileSync(join(kbDir, "manifest.json"), "utf8"));
  validateManifest(manifest);
  const entries = manifest.entries
    .filter((e) => e.status === "published")
    .map((e) => {
      const text = readFileSync(join(kbDir, e.source_key), "utf8").split("\n").slice(1).join("\n").trim();
      return {
        doc_id: e.doc_id, kind: e.kind, locale: e.locale, title: e.title, doc_version: e.doc_version,
        source_key: e.source_key, content_hash: e.content_hash, status: e.status, text,
      };
    });
  const out = `// Generated by scripts/kb-build.ts from coach-knowledge/manifest.json. Do not edit.
export interface KbEntry {
  doc_id: string; kind: string; locale: string; title: string; doc_version: number;
  source_key: string; content_hash: string; status: string; text: string;
}
export const COACH_KB: {
  corpus_version: string; policy_version: string; contract_version: string; entries: KbEntry[];
} = ${JSON.stringify(
    { corpus_version: manifest.corpus_version, policy_version: manifest.policy_version, contract_version: manifest.contract_version, entries },
    null,
    2,
  )};
`;
  writeFileSync(join(serverRoot, "src", "coach-kb.generated.ts"), out);
  console.log(`coach-kb.generated.ts: ${entries.length} published entries (corpus ${manifest.corpus_version})`);
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const manifestPath = join(kbDir, "manifest.json");
  const manifest: Manifest = JSON.parse(readFileSync(manifestPath, "utf8"));
  if (process.argv.includes("--write-hashes")) {
    for (const e of manifest.entries) {
      const expectedKey = `published/${manifest.corpus_version}/${e.locale}/${e.doc_id}.md`;
      if (e.source_key !== expectedKey) fail(`entries (${e.doc_id}/${e.locale}): source_key "${e.source_key}" != "${expectedKey}"`);
      e.content_hash = sha256(readFileSync(join(kbDir, e.source_key)));
    }
    writeFileSync(manifestPath, JSON.stringify(manifest, null, 2) + "\n");
    console.log(`manifest.json: hashes rewritten for ${manifest.entries.length} entries`);
  }
  build();
}
