// Live eval: POSTs eval/questions.json to a running /coach endpoint; exit 1 on any failure.
// Usage: EVAL_URL=http://127.0.0.1:8787/coach APP_SECRET=... node eval/run.ts
import { readFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

interface EvalCase {
  question: string;
  data?: Record<string, unknown>;
  language?: string;
  context?: string;
  capabilities?: string[];
  mustContain: string[];
  mustNotContain: string[];
  expectStatus?: number;
  history?: { role: "user" | "assistant"; content: string }[];
  contract?: Record<string, unknown>;
  coach?: string;
  /** Expected outcome for human grading; ignored by the runner. */
  rubric?: string;
}

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const allCases: EvalCase[] = JSON.parse(
  readFileSync(resolve(root, process.env.EVAL_FILE ?? "eval/questions.json"), "utf8"),
);
const filterRx = process.env.EVAL_FILTER ? new RegExp(process.env.EVAL_FILTER, "i") : null;
const cases = filterRx ? allCases.filter((c) => filterRx.test(c.question)) : allCases;

const url = process.env.EVAL_URL ?? "http://127.0.0.1:8787/coach";
const secret = process.env.APP_SECRET;
if (!secret) {
  console.error("APP_SECRET is required");
  process.exit(1);
}

let failed = 0;
const delayMs = Number(process.env.EVAL_DELAY_MS ?? 0);
for (const c of cases) {
  if (delayMs > 0) await new Promise((r) => setTimeout(r, delayMs));
  let ok = false;
  let detail = "";
  try {
    const res = await fetch(url, {
      method: "POST",
      headers: { "content-type": "application/json", "x-forge-secret": secret },
      body: JSON.stringify({
        question: c.question,
        data: c.data ?? {},
        ...(c.language ? { language: c.language } : {}),
        ...(c.context ? { context: c.context } : {}),
        ...(c.capabilities ? { capabilities: c.capabilities } : {}),
        ...(c.history ? { history: c.history } : {}),
        ...(c.contract ? { contract: c.contract } : {}),
        ...(c.coach ? { coach: c.coach } : {}),
      }),
      signal: AbortSignal.timeout(30_000),
    });
    const j = (await res.json()) as Record<string, unknown>;
    let haystack = typeof j.answer === "string" ? j.answer : "";
    if (typeof j.text === "string") haystack += `\n${j.text}`;
    if (typeof j.error === "string") haystack += `\n${j.error}`;
    if (j.action && typeof j.action === "object") {
      haystack += `\nACTION ${JSON.stringify(j.action)}`;
    }
    const expectStatus = c.expectStatus ?? 200;
    const missing = c.mustContain.filter((rx) => !new RegExp(rx).test(haystack));
    const forbidden = c.mustNotContain.filter((rx) => new RegExp(rx).test(haystack));
    ok = res.status === expectStatus && missing.length === 0 && forbidden.length === 0;
    if (!ok) {
      detail =
        `status ${res.status}` +
        (missing.length ? `; missing ${JSON.stringify(missing)}` : "") +
        (forbidden.length ? `; forbidden ${JSON.stringify(forbidden)}` : "");
    }
  } catch (e) {
    detail = `error: ${e instanceof Error ? e.message : String(e)}`;
  }
  if (!ok) failed++;
  console.log(`${ok ? "PASS" : "FAIL"} ${c.question}${detail ? ` — ${detail}` : ""}`);
}
console.log(`\n${cases.length - failed}/${cases.length} passed`);
process.exit(failed ? 1 : 0);
