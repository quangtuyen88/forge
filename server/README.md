# forge-server

Coach proxy: holds the model key, RAG over `knowledge/`, medical guard. Node 24, zero runtime deps.

## Run

    pnpm install && pnpm build
    APP_SECRET=... ANTHROPIC_API_KEY=... pnpm start   # or GEMINI_API_KEY=... PROVIDER=gemini

Env: `PORT` (8787), `PROVIDER` (claude|gemini, default claude), `ANTHROPIC_API_KEY`,
`GEMINI_API_KEY`, `APP_SECRET` (required).

## Endpoint

- `POST /coach` — headers `x-forge-secret`, `content-type: application/json`;
  body `{ question, context, history? }` → `{ answer, refused, citations }` (502 on upstream error)
- `GET /health` — `{ ok, provider, chunks }`

Tests: `pnpm test`
