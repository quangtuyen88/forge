import test from "node:test";
import assert from "node:assert/strict";
import { apiApp, call, login } from "./helpers.js";

const COACH = { body: { question: "how many sets for chest", context: "" } };

test("free user: 6th coach question in a day returns 429", async () => {
  const { app } = apiApp();
  const { token } = await login(app, "freebie");
  for (let i = 0; i < 5; i++) {
    const res = await call(app, "POST", "/coach", { token, ...COACH });
    assert.equal(res.status, 200, `question ${i + 1} should pass`);
  }
  const sixth = await call(app, "POST", "/coach", { token, ...COACH });
  assert.equal(sixth.status, 429);
  assert.deepEqual(await sixth.json(), { error: "Daily coach limit reached. Upgrade for more." });
});

test("pro user stays under the 60/day cap", async () => {
  const { app, queries } = apiApp();
  const { token, user } = await login(app, "probie");
  await queries.setTier(user.id, "pro");
  for (let i = 0; i < 6; i++) {
    const res = await call(app, "POST", "/coach", { token, ...COACH });
    assert.equal(res.status, 200, `question ${i + 1} should pass for pro`);
  }
});

test("coach without a Bearer still works when the api is configured", async () => {
  const { app } = apiApp();
  await login(app, "anon-next-to");
  for (let i = 0; i < 6; i++) {
    const res = await call(app, "POST", "/coach", COACH);
    assert.equal(res.status, 200);
  }
});
