// Live eval: POSTs eval/questions.json to a running server; exit 1 on any failure.
// Usage: COACH_URL=http://localhost:8787 APP_SECRET=... pnpm eval
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const questions: { q: string; expect?: string[]; refuse?: boolean }[] = JSON.parse(
  readFileSync(join(root, "eval", "questions.json"), "utf8"),
);
const url = process.env.COACH_URL ?? "http://localhost:8787";
const secret = process.env.APP_SECRET;
if (!secret) {
  console.error("APP_SECRET is required");
  process.exit(1);
}

let failed = 0;
for (const { q, expect, refuse } of questions) {
  let pass = false;
  let provider = "refuse";
  try {
    const res = await fetch(`${url}/coach`, {
      method: "POST",
      headers: { "content-type": "application/json", "x-forge-secret": secret },
      body: JSON.stringify({ question: q, context: "" }),
      signal: AbortSignal.timeout(30_000),
    });
    const data = await res.json();
    provider = data.provider ?? "-";
    pass =
      res.status === 200 &&
      (refuse
        ? data.refused === true
        : data.refused === false &&
          (expect ?? []).every((h) => data.citations?.includes(h) && data.answer?.includes(`[${h}]`)));
  } catch (e) {
    provider = `error: ${e instanceof Error ? e.message : e}`;
  }
  if (!pass) failed++;
  console.log(`${pass ? "PASS" : "FAIL"} [${provider}] ${q}`);
}
console.log(`\n${questions.length - failed}/${questions.length} passed`);
process.exit(failed ? 1 : 0);
