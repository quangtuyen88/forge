import test from "node:test";
import assert from "node:assert/strict";
import { apiApp, call, login } from "./helpers.js";
import { verifyAppleToken } from "../auth.js";

test("apple login creates a user and returns a working Bearer", async () => {
  const { app } = apiApp();
  const { token, user } = await login(app, "apple-1");
  assert.match(user.id, /^[0-9a-f-]{36}$/);
  assert.equal(user.tier, "free");
  assert.match(user.referralCode, /^[a-z2-7]{8}$/);
  const me = await call(app, "GET", "/me", { token });
  assert.equal(me.status, 200);
  assert.equal((await me.json()).user.id, user.id);
});

test("second apple login returns the same user", async () => {
  const { app } = apiApp();
  const first = await login(app, "apple-1");
  const second = await login(app, "apple-1");
  assert.equal(second.user.id, first.user.id);
  assert.equal(second.user.referralCode, first.user.referralCode);
});

test("GET /me without (or with a bad) token returns 401", async () => {
  const { app } = apiApp();
  await login(app, "apple-1");
  assert.equal((await call(app, "GET", "/me")).status, 401);
  assert.equal((await call(app, "GET", "/me", { token: "garbage" })).status, 401);
});

test("apple login with a rejected identity token returns 401", async () => {
  const { app } = apiApp({ verifyApple: async () => { throw new Error("bad signature"); } });
  const res = await call(app, "POST", "/auth/apple", { body: { identityToken: "bad" } });
  assert.equal(res.status, 401);
});

test("google login upserts by google_sub", async () => {
  const { app } = apiApp({
    env: { ENV: "dev", GOOGLE_CLIENT_ID: "g-client-id" },
    verifyGoogle: async () => ({ sub: "g-1", email: "g@example.com" }),
  });
  const res = await call(app, "POST", "/auth/google", { body: { idToken: "t" } });
  assert.equal(res.status, 200);
  const data = (await res.json()) as { token: string; user: { email?: string } };
  assert.equal(data.user.email, "g@example.com");
  const again = await call(app, "POST", "/auth/google", { body: { idToken: "t2" } });
  assert.equal(((await again.json()) as { user: { id: string } }).user.id, (await (await call(app, "GET", "/me", { token: data.token })).json()).user.id);
});

test("email start returns devCode in dev; verify returns a working token", async () => {
  const { app } = apiApp();
  const start = await call(app, "POST", "/auth/email/start", { body: { email: "Lifter@Example.com" } });
  assert.equal(start.status, 200);
  const { devCode } = (await start.json()) as { devCode: string };
  assert.match(devCode ?? "", /^\d{6}$/);
  const verify = await call(app, "POST", "/auth/email/verify", { body: { email: "lifter@example.com", code: devCode } });
  assert.equal(verify.status, 200);
  const { token } = await verify.json() as { token: string };
  assert.equal((await call(app, "GET", "/me", { token })).status, 200);
});

test("email start rejects invalid addresses", async () => {
  const { app } = apiApp();
  assert.equal((await call(app, "POST", "/auth/email/start", { body: { email: "nope" } })).status, 400);
});

test("wrong code five times locks the code", async () => {
  const { app } = apiApp();
  await call(app, "POST", "/auth/email/start", { body: { email: "a@b.co" } });
  const { devCode } = (await (await call(app, "POST", "/auth/email/start", { body: { email: "a@b.co" } })).json()) as { devCode: string };
  for (let i = 0; i < 5; i++) {
    const wrong = devCode === "000000" ? "111111" : "000000";
    assert.equal((await call(app, "POST", "/auth/email/verify", { body: { email: "a@b.co", code: wrong } })).status, 401);
  }
  const locked = await call(app, "POST", "/auth/email/verify", { body: { email: "a@b.co", code: devCode } });
  assert.equal(locked.status, 429);
});

test("email verify with no code requested returns 400", async () => {
  const { app } = apiApp();
  assert.equal((await call(app, "POST", "/auth/email/verify", { body: { email: "x@y.co", code: "123456" } })).status, 400);
});

test("logout invalidates the session", async () => {
  const { app } = apiApp();
  const { token } = await login(app, "apple-1");
  assert.equal((await call(app, "POST", "/auth/logout", { token })).status, 200);
  assert.equal((await call(app, "GET", "/me", { token })).status, 401);
});

test("DELETE /me removes the user, its records, its session and its social rows", async () => {
  const { app, queries } = apiApp();
  const { token, user } = await login(app, "apple-1");
  await call(app, "POST", "/sync", {
    token,
    body: { cursor: 0, changes: [{ type: "session", id: "s1", updatedAt: "2025-01-01T00:00:00Z", data: { note: "x" } }] },
  });
  const put = await call(app, "PUT", "/social/profile", { token, body: { handle: "deleteme", displayName: "D", bio: "" } });
  assert.equal(put.status, 200);
  const res = await call(app, "DELETE", "/me", { token });
  assert.equal(res.status, 200);
  assert.deepEqual(await res.json(), { ok: true });
  assert.equal(await queries.getUserById(user.id), null);
  assert.deepEqual(await queries.recordsSince(user.id, 0), []);
  assert.equal(await queries.getProfileByHandle("deleteme"), null); // handle freed
  assert.deepEqual(await queries.userPosts(user.id), []);
  assert.equal((await call(app, "GET", "/me", { token })).status, 401);
});

test("api routes 404 when no api context is configured", async () => {
  const { createApp } = await import("../app.js");
  const app = createApp({ chunks: [], complete: async () => ({ answer: "", provider: "gemini" }), secret: "test", providers: [] });
  assert.equal((await call(app, "POST", "/auth/apple", { body: { identityToken: "t" } })).status, 404);
});

// Real RS256 path: generate an RSA key, sign a JWT, stub the JWKS fetch.
test("verifyAppleToken verifies a real RS256 JWT against the JWKS", async () => {
  const { publicKey, privateKey } = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" },
    true,
    ["sign", "verify"],
  );
  const jwk = { ...(await crypto.subtle.exportKey("jwk", publicKey)), kid: "k1" } as Record<string, unknown>;
  const b64u = (buf: ArrayBuffer | Uint8Array) => {
    const b = buf instanceof Uint8Array ? buf : new Uint8Array(buf);
    return btoa(String.fromCharCode(...b)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
  };
  const enc = (obj: unknown) => b64u(new TextEncoder().encode(JSON.stringify(obj)));
  const header = enc({ alg: "RS256", kid: "k1" });
  const payload = enc({
    sub: "apple-real-sub",
    email: "real@apple.example",
    iss: "https://appleid.apple.com",
    aud: "app.regulift",
    exp: Math.floor(Date.now() / 1000) + 3600,
  });
  const sig = await crypto.subtle.sign("RSASSA-PKCS1-v1_5", privateKey, new TextEncoder().encode(`${header}.${payload}`));
  const jwt = `${header}.${payload}.${b64u(sig)}`;

  const realFetch = globalThis.fetch;
  globalThis.fetch = (async () => new Response(JSON.stringify({ keys: [jwk] }), { status: 200 })) as typeof fetch;
  try {
    const identity = await verifyAppleToken(jwt, "app.regulift");
    assert.equal(identity.sub, "apple-real-sub");
    assert.equal(identity.email, "real@apple.example");
    // tampered payload must fail the signature check
    const tampered = `${header}.${enc({ ...JSON.parse(atob(payload.replace(/-/g, "+").replace(/_/g, "/"))), sub: "evil" })}.${b64u(sig)}`;
    await assert.rejects(verifyAppleToken(tampered, "app.regulift"));
  } finally {
    globalThis.fetch = realFetch;
  }
});
