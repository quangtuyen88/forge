import { createApp, type ApiContext } from "../app.js";
import { memoryQueries } from "../queries.js";
import type { Queries } from "../queries.js";

export const H = { "content-type": "application/json", "x-forge-secret": "test" };

export function apiApp(extra: Partial<ApiContext> = {}): { app: ReturnType<typeof createApp>; queries: Queries } {
  const queries = memoryQueries();
  const app = createApp({
    chunks: [],
    complete: async () => ({ answer: "stub", provider: "gemini" }),
    secret: "test",
    providers: [],
    api: {
      queries,
      env: { ENV: "dev" },
      verifyApple: async (t) => ({ sub: `apple-${t}`, email: "lifter@example.com" }),
      ...extra,
    },
  });
  return { app, queries };
}

export async function call(
  app: ReturnType<typeof createApp>,
  method: string,
  path: string,
  opts: { token?: string; body?: unknown; headers?: Record<string, string> } = {},
): Promise<Response> {
  return app(
    new Request(`http://x${path}`, {
      method,
      headers: {
        ...H,
        ...(opts.token ? { authorization: `Bearer ${opts.token}` } : {}),
        ...(opts.headers ?? {}),
      },
      body: opts.body === undefined ? undefined : JSON.stringify(opts.body),
    }),
  );
}

export interface TestUser {
  token: string;
  user: { id: string; tier: string; referralCode: string; email?: string };
}

export async function login(app: ReturnType<typeof createApp>, key = "u1"): Promise<TestUser> {
  const res = await call(app, "POST", "/auth/apple", { body: { identityToken: key } });
  if (res.status !== 200) throw new Error(`login failed: ${res.status} ${await res.text()}`);
  return (await res.json()) as TestUser;
}
