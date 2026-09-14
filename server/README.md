# forge-server

Coach proxy: model key, RAG over `knowledge/`, medical guard. Same code on Node and Cloudflare Workers.

## Node

    pnpm install && pnpm build
    APP_SECRET=... ANTHROPIC_API_KEY=... pnpm start   # or PROVIDER=gemini GEMINI_API_KEY=...

## Worker deploy

    pnpm install && pnpm build && npx wrangler login
    npx wrangler secret put APP_SECRET && npx wrangler secret put ANTHROPIC_API_KEY   # and/or GEMINI_API_KEY
    pnpm deploy

Optional Vectorize retrieval (default is local BM25):

    npx wrangler vectorize create forge-coach --dimensions=768 --metric=cosine
    # uncomment [ai] + [[vectorize]] in wrangler.toml, pnpm deploy, then:
    curl -X POST https://forge-coach.<account>.workers.dev/admin/reindex -H "x-forge-secret: $APP_SECRET"

## Endpoints

- `POST /coach` — header `x-forge-secret`; body `{question, context, history?}` → `{answer, refused, citations}`
- `GET /health` — `{ok, provider, chunks}`

App Settings: URL `http://localhost:8787/coach` or `https://forge-coach.<account>.workers.dev/coach`, plus the APP_SECRET.

Tests: `pnpm build && pnpm test`
