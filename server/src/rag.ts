import { readdirSync, readFileSync } from "node:fs";
import { join } from "node:path";

export interface Chunk {
  id: string;
  file: string;
  heading: string;
  text: string;
}

export function loadKnowledge(dir: string): Chunk[] {
  const chunks: Chunk[] = [];
  for (const f of readdirSync(dir).filter((f) => f.endsWith(".md")).sort()) {
    const md = readFileSync(join(dir, f), "utf8");
    // [0] is the file preamble (title only); each "## " section is a chunk
    for (const section of md.split(/^## /m).slice(1)) {
      const [heading, ...rest] = section.split("\n");
      chunks.push({
        id: `${f}:${heading.trim()}`,
        file: f,
        heading: heading.trim(),
        text: rest.join("\n").trim(),
      });
    }
  }
  return chunks;
}

function tokenise(s: string): string[] {
  return s
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
    .split(/\s+/)
    .filter((t) => t.length > 2);
}

const K1 = 1.5;
const B = 0.75;

// ponytail: lexical BM25 over ~60 chunks; swap for embeddings when the rulebook outgrows it
export function bm25(query: string, chunks: Chunk[], k = 4): Chunk[] {
  const terms = [...new Set(tokenise(query))];
  if (!terms.length) return [];
  const docs = chunks.map((c) => tokenise(`${c.heading} ${c.text}`));
  const N = docs.length;
  const avgLen = docs.reduce((a, d) => a + d.length, 0) / N || 1;
  return chunks
    .map((chunk, i) => {
      const doc = docs[i];
      let score = 0;
      for (const term of terms) {
        const tf = doc.filter((t) => t === term).length;
        if (!tf) continue;
        const df = docs.filter((d) => d.includes(term)).length;
        const idf = Math.log((N - df + 0.5) / (df + 0.5) + 1);
        score += (idf * tf * (K1 + 1)) / (tf + K1 * (1 - B + (B * doc.length) / avgLen));
      }
      return { chunk, score };
    })
    .filter((s) => s.score > 0)
    .sort((a, b) => b.score - a.score)
    .slice(0, k)
    .map((s) => s.chunk);
}
