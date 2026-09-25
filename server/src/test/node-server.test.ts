import { after, before, test } from "node:test";
import assert from "node:assert/strict";

// An empty secret makes every gated route 401 (unauthorized() blocks when !secret),
// so set it before the import captures it; gated routes then need x-forge-secret.
process.env.APP_SECRET = "e2e";

const { server } = await import("../index.js");

let base = "";
before(async () => {
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  base = `http://127.0.0.1:${(server.address() as { port: number }).port}`;
});
after(() => new Promise<void>((resolve) => server.close(() => resolve())));

test("PUT /social/profile keeps its body; GET echoes the lowercased handle", async () => {
  const secret = { "content-type": "application/json", "x-forge-secret": "e2e" };
  const start = await fetch(`${base}/auth/email/start`, {
    method: "POST",
    headers: secret,
    body: JSON.stringify({ email: "e2e@example.com" }),
  });
  assert.equal(start.status, 200);
  const { devCode } = (await start.json()) as { devCode: string };
  const verify = await fetch(`${base}/auth/email/verify`, {
    method: "POST",
    headers: secret,
    body: JSON.stringify({ email: "e2e@example.com", code: devCode }),
  });
  assert.equal(verify.status, 200);
  const { token } = (await verify.json()) as { token: string };

  const put = await fetch(`${base}/social/profile`, {
    method: "PUT",
    headers: { ...secret, authorization: `Bearer ${token}` },
    body: JSON.stringify({ handle: "E2E_Lifter", displayName: "E2E", bio: "" }),
  });
  assert.equal(put.status, 200);

  const get = await fetch(`${base}/social/profile`, {
    headers: { authorization: `Bearer ${token}`, "x-forge-secret": "e2e" },
  });
  assert.equal(get.status, 200);
  const { profile } = (await get.json()) as { profile: { handle: string } };
  assert.equal(profile.handle, "e2e_lifter");
});

test("OPTIONS /waitlist returns 204 with CORS headers", async () => {
  const res = await fetch(`${base}/waitlist`, { method: "OPTIONS" });
  assert.equal(res.status, 204);
  assert.equal(res.headers.get("access-control-allow-origin"), "*");
});
