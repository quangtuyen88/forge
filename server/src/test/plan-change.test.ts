import test from "node:test";
import assert from "node:assert/strict";
import { buildSystem } from "../prompt.js";

test("buildSystem: PLAN CHANGES guidance is present with its key context lines", () => {
  const system = buildSystem("", [], "Nova");
  assert.ok(system.includes("PLAN CHANGES"));
  assert.ok(system.includes("Settings → Training"));
  assert.ok(system.includes("sessions_this_block"));
  assert.ok(system.includes("recent_plan_changes"));
});

test("buildSystem: retired remember wording and plan-setting fact are gone", () => {
  const system = buildSystem("", [], "Nova");
  assert.ok(!system.includes("I'll plan around it"));
  assert.ok(!system.includes("Noted —"));
  assert.ok(!system.includes("a schedule constraint"));
});

test("buildSystem: PLAN CHANGES sits after the ACTIONS text", () => {
  const system = buildSystem("", [], "Nova");
  assert.ok(system.indexOf("PLAN CHANGES") > system.indexOf("ACTIONS:"));
});
