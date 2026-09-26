// Uploads coach-knowledge published corpus to R2 bucket `regulift-coach-knowledge`
// (Cloudflare AI Search metadata). Default --dry-run prints keys and uploads nothing;
// --upload is for the supervisor. Run via `pnpm kb:publish` (Node 24 strips types; no deps).
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { validateManifest, kbDir, type Manifest, type ManifestEntry } from "./kb-build.ts";

interface KbBucket {
  put(key: string, value: ArrayBuffer | ReadableStream | string, opts?: { httpMetadata?: Record<string, string>; customMetadata?: Record<string, string> }): Promise<void>;
  head(key: string): Promise<{ customMetadata?: Record<string, string> } | null>;
}

function die(msg: string): never {
  console.error(`kb-publish: ${msg}`);
  process.exit(1);
}

const manifest: Manifest = JSON.parse(readFileSync(join(kbDir, "manifest.json"), "utf8"));
validateManifest(manifest);

const published: ManifestEntry[] = manifest.entries.filter((e) => e.status === "published");
const prefix = `published/${manifest.corpus_version}/`;
for (const e of published) {
  if (!e.source_key.startsWith(prefix)) die(`refusing to upload outside ${prefix}: ${e.source_key}`);
}

const customMetaFor = (e: ManifestEntry): Record<string, string> => ({
  doc_id: e.doc_id,
  kind: e.kind,
  locale: e.locale,
  policy_version: manifest.policy_version,
  status: e.status,
});

const mode = process.argv.includes("--upload") ? "upload" : process.argv.includes("--dry-run") ? "dry-run" : process.argv.length <= 2 ? "dry-run" : die(`unknown flag (use --dry-run or --upload): ${process.argv.slice(2).join(" ")}`);

if (mode === "dry-run") {
  console.log(`dry-run: ${published.length} published entries, corpus ${manifest.corpus_version} (nothing uploaded)`);
  for (const e of published) {
    console.log(`${e.source_key}  ${JSON.stringify(customMetaFor(e))}`);
  }
} else {
  const require = createRequire(join(kbDir, "..", "package.json")); // server/package.json → devDependencies.wrangler
  const { getPlatformProxy } = require("wrangler") as {
    getPlatformProxy(opts: { configPath: string }): Promise<{ env: { KB_BUCKET?: KbBucket }; dispose: () => Promise<void> }>;
  };
  const { env, dispose } = await getPlatformProxy({ configPath: join(kbDir, "wrangler.kb.toml") });
  const bucket = env.KB_BUCKET ?? die("KB_BUCKET binding missing (coach-knowledge/wrangler.kb.toml)");
  let ok = 0;
  try {
    for (const e of published) {
      const body = readFileSync(join(kbDir, e.source_key));
      await bucket.put(e.source_key, body, {
        httpMetadata: { contentType: "text/markdown; charset=utf-8" },
        customMetadata: customMetaFor(e),
      });
      const head = await bucket.head(e.source_key);
      const expected = customMetaFor(e);
      const actual = head?.customMetadata ?? {};
      const roundTrip = JSON.stringify(expected) === JSON.stringify(actual);
      if (!roundTrip) die(`customMetadata round-trip failed for ${e.source_key}: expected ${JSON.stringify(expected)}, got ${JSON.stringify(actual)}`);
      ok++;
    }
  } finally {
    await dispose();
  }
  console.log(`upload: ${ok}/${published.length} objects written to regulift-coach-knowledge, customMetadata verified`);
}
