import test from "node:test";
import assert from "node:assert/strict";
import { createApp, guardAction, isThisWeekOnly, parseAction } from "../app.js";
import { isApplyRequest } from "../contract.js";
import { ADJUST_PLAN_ACTIONS, buildSystem, PLAN_CHANGES, PLAN_CHANGES_ADJUST } from "../prompt.js";

// --- parseAction ---

test("parseAction: adjustPlan with days and minutes", () => {
  const { text, action } = parseAction(
    'I\'ve prepared 3 days a week with about 45-minute sessions. Review it below.\nACTION {"type":"adjustPlan","daysPerWeek":3,"sessionMinutes":45}',
  );
  assert.deepEqual(action, { type: "adjustPlan", daysPerWeek: 3, sessionMinutes: 45 });
  assert.equal(text, "I've prepared 3 days a week with about 45-minute sessions. Review it below.");
});

test("parseAction: adjustPlan with 2 days parses as an action", () => {
  const { action, unsupportedPlan } = parseAction('Prepared.\nACTION {"type":"adjustPlan","daysPerWeek":2}');
  assert.deepEqual(action, { type: "adjustPlan", daysPerWeek: 2 });
  assert.notEqual(unsupportedPlan, true);
});

test("parseAction: unsupported values return action null with unsupportedPlan", () => {
  for (const line of [
    'ACTION {"type":"adjustPlan","daysPerWeek":1}',
    'ACTION {"type":"adjustPlan","sessionMinutes":35}',
    'ACTION {"type":"adjustPlan","goal":"power"}',
  ]) {
    const { action, unsupportedPlan } = parseAction(`Prepared.\n${line}`);
    assert.equal(action, null, line);
    assert.equal(unsupportedPlan, true, line);
  }
});

test("parseAction: empty adjustPlan object returns action null", () => {
  const { action, unsupportedPlan } = parseAction('Prepared.\nACTION {"type":"adjustPlan"}');
  assert.equal(action, null);
  assert.notEqual(unsupportedPlan, true);
});

// --- guardAction ---

test("guardAction: adjustPlan needs plan-change intent in the question", () => {
  const action = { type: "adjustPlan", daysPerWeek: 3 } as const;
  assert.deepEqual(guardAction(action, "I can only train 3 days a week now"), action);
  assert.equal(guardAction(action, "What should I do tomorrow?"), null);
});

test("guardAction: adjustPlan accepts Vietnamese, Japanese and Korean plan-change questions", () => {
  const action = { type: "adjustPlan", daysPerWeek: 2 } as const;
  const questions = [
    "Tôi Chir rảnh. 2 ngày",
    "Tôi chỉ rảnh 2 ngày một tuần",
    "Tôi chỉ rảnh 2 ngày một tuần".normalize("NFD"),
    "今は週2日しかトレーニングできません。",
    "이제 주 2일만 운동할 수 있어요.",
  ];
  for (const question of questions) {
    assert.deepEqual(guardAction(action, question), action, question);
  }
});

test("guardAction: adjustPlan is rejected for non-plan-change questions in other languages", () => {
  const action = { type: "adjustPlan", daysPerWeek: 2 } as const;
  for (const question of ["Bài squat của tôi thế nào?", "スクワットのフォームは？", "스쿼트 자세 어때요?"]) {
    assert.equal(guardAction(action, question), null, question);
  }
});

// --- isThisWeekOnly ---

test("isThisWeekOnly: true for one-week limits in all languages", () => {
  for (const question of [
    "Tôi chỉ rảnh 2 ngày tuần này",
    "Tôi chỉ rảnh 2 ngày tuần này".normalize("NFD"),
    "I only have 2 days this week.",
    "今週は2日しか空いていません",
    "이번 주는 이틀만 시간이 있어요",
  ]) {
    assert.equal(isThisWeekOnly(question), true, question);
  }
});

test("isThisWeekOnly: false for lasting changes and terse day counts", () => {
  for (const question of [
    "Tôi chỉ rảnh 2 ngày mỗi tuần, bắt đầu từ tuần này",
    "From this week on I can only train 2 days a week",
    "I can only train 2 days a week now.",
    "今週から週2日にしたい",
    "이번 주부터 주 2일만 할게요",
    "Tôi Chir rảnh. 2 ngày",
  ]) {
    assert.equal(isThisWeekOnly(question), false, question);
  }
});

test("guardAction: adjustPlan is null for one-week limits", () => {
  const action = { type: "adjustPlan", daysPerWeek: 2 } as const;
  assert.equal(guardAction(action, "Tôi chỉ rảnh 2 ngày tuần này"), null);
  assert.equal(guardAction(action, "I only have 2 days this week."), null);
  assert.deepEqual(guardAction(action, "Tôi chỉ rảnh 2 ngày mỗi tuần, bắt đầu từ tuần này"), action);
});

// --- buildSystem ---

test("buildSystem: adjustPlan swaps the prompt sections", () => {
  const withAdjust = buildSystem("ctx", [], "Nova", ["note"], "en", undefined, true);
  assert.ok(withAdjust.includes(ADJUST_PLAN_ACTIONS));
  assert.ok(withAdjust.includes(PLAN_CHANGES_ADJUST));
  assert.ok(!withAdjust.includes(PLAN_CHANGES));
  assert.ok(!withAdjust.includes("Settings → Training"));

  const without = buildSystem("ctx", [], "Nova", ["note"], "en", undefined, false);
  assert.ok(without.includes(PLAN_CHANGES));
  assert.ok(!without.includes("adjustPlan"));
  assert.equal(without, buildSystem("ctx", [], "Nova", ["note"], "en", undefined));
});

// --- /coach handler ---

function coachApp(answer: string) {
  return createApp({
    chunks: [],
    complete: async () => ({ answer, provider: "gemini" }),
    secret: "test",
    providers: [],
  });
}

const H = { "content-type": "application/json", "x-forge-secret": "test" };
function post(app: ReturnType<typeof createApp>, body: unknown) {
  return app(new Request("http://x/coach", { method: "POST", headers: H, body: JSON.stringify(body) }));
}

test("/coach: adjustPlan action passes through only with the capability", async () => {
  const answer =
    'I\'ve prepared 3 days a week with about 45-minute sessions. Review it below.\nACTION {"type":"adjustPlan","daysPerWeek":3,"sessionMinutes":45}';
  const withCap = await (await post(coachApp(answer), {
    question: "I can only train 3 days a week now",
    context: "",
    capabilities: ["adjust_plan"],
  })).json();
  assert.deepEqual(withCap.action, { type: "adjustPlan", daysPerWeek: 3, sessionMinutes: 45 });

  const withoutCap = await (await post(coachApp(answer), {
    question: "I can only train 3 days a week now",
    context: "",
  })).json();
  assert.equal(withoutCap.action, null);
});

test("/coach: unsupported adjustPlan values get the fixed template", async () => {
  const res = await post(coachApp('Sure.\nACTION {"type":"adjustPlan","daysPerWeek":1}'), {
    question: "I can only train 1 day a week now",
    context: "",
    capabilities: ["adjust_plan"],
  });
  const data = await res.json();
  assert.equal(
    data.answer,
    "Regulift plans 2 to 6 training days a week with 45, 60 or 90-minute sessions, so I can't set that up. Tell me a supported option, for example 2 days a week with 45-minute sessions, and I'll prepare it.",
  );
  assert.equal(data.action, null);
});

test("/coach: one-week limit gets no card and a keep-the-plan prompt", async () => {
  const answer = 'I\'ve prepared 2 days a week. Review it below.\nACTION {"type":"adjustPlan","daysPerWeek":2}';
  let system = "";
  const app = createApp({
    chunks: [],
    complete: async (s: string) => {
      system = s;
      return { answer, provider: "gemini" };
    },
    secret: "test",
    providers: [],
  });
  const data = await (await post(app, {
    question: "I only have 2 days this week.",
    context: "Week 3, block 2",
    capabilities: ["adjust_plan"],
  })).json();
  assert.ok(system.includes("limit_scope: only this week, so keep the plan and prepare no change"));
  assert.ok(system.includes("Week 3, block 2"));
  assert.equal(data.action, null);
});

// --- K05: deferred plan start ---

const K05_CONTRACT = {
  contract_version: "coach-contract-v1",
  capabilities: { deferred_plan_start_supported: false, approved_change_scope: "next_unstarted_session" },
  program: { week_basis: "completed_sessions", computed_week: 2, weeks_in_block: 6, deload_week: 6, completed_sessions_since_block_start: 6, sessions_per_program_week: 4, block_start: "2026-09-14" },
  proposal: { type: "adjustPlan", status: "ready", summary: "days per week 2, session 45 min" },
  commit_receipt: null,
};
const EN_NOTE =
  "A later start date is not supported yet. An applied change starts with your next workout that has not been started, so apply it when you are ready.";

function k05App(answer: string) {
  let system = "";
  const app = createApp({
    chunks: [],
    complete: async (s: string) => {
      system = s;
      return { answer, provider: "gemini" };
    },
    secret: "test",
    providers: [],
  });
  return { app, system: () => system };
}

test("/coach K05: en deferred start gets the hint and the leading note", async () => {
  const { app, system } = k05App("Your plan stays at 4 days a week. Tomorrow you have Upper.");
  const data = await (await post(app, {
    question: "Start that next Monday. What do I do tomorrow?",
    context: "ctx",
    language: "en",
    capabilities: ["adjust_plan"],
    contract: K05_CONTRACT,
  })).json();
  assert.ok(system().includes("deferred_start:"));
  assert.equal(data.answer, `${EN_NOTE} Your plan stays at 4 days a week. Tomorrow you have Upper.`);
  assert.equal(data.action, null);
});

test("/coach K05: vi promise sentence is dropped, tomorrow's session kept", async () => {
  const { app } = k05App("Kế hoạch của bạn vẫn là 4 ngày mỗi tuần. Ngày mai, thứ Năm, bạn có buổi Upper. Nếu bạn muốn bắt đầu với kế hoạch 2 ngày mỗi tuần, 45 phút mỗi buổi từ thứ Hai, bạn cần áp dụng thay đổi kế hoạch.");
  const data = await (await post(app, {
    question: "Bắt đầu từ thứ Hai tới nhé. Ngày mai tôi tập gì?",
    context: "ctx",
    language: "vi",
    capabilities: ["adjust_plan"],
    contract: K05_CONTRACT,
  })).json();
  assert.ok(data.answer.startsWith("Hiện chưa hỗ trợ chọn ngày bắt đầu muộn hơn."));
  assert.ok(data.answer.includes("Ngày mai, thứ Năm, bạn có buổi Upper."));
  assert.ok(!data.answer.includes("từ thứ Hai"));
});

test("/coach K05: a compliant model answer gets no second note", async () => {
  const compliant = "A start on a later date is not supported yet; a change applies from your next unstarted workout. Tomorrow you have Upper.";
  const { app } = k05App(compliant);
  const data = await (await post(app, {
    question: "Start that next Monday. What do I do tomorrow?",
    context: "ctx",
    language: "en",
    capabilities: ["adjust_plan"],
    contract: K05_CONTRACT,
  })).json();
  assert.equal(data.answer, compliant);
});

test("/coach K05: ja and ko replies get their own note", async () => {
  const ja = k05App("明日は上半身の日です。");
  const dataJa = await (await post(ja.app, {
    question: "来週の月曜からプランを始めたい",
    context: "ctx",
    language: "ja",
    capabilities: ["adjust_plan"],
    contract: K05_CONTRACT,
  })).json();
  assert.ok(dataJa.answer.startsWith("開始日を後の日付に指定することはまだできません。"));
  const ko = k05App("내일은 상체 운동이에요.");
  const dataKo = await (await post(ko.app, {
    question: "다음 주 월요일부터 새 플랜을 시작해 줘",
    context: "ctx",
    language: "ko",
    capabilities: ["adjust_plan"],
    contract: K05_CONTRACT,
  })).json();
  assert.ok(dataKo.answer.startsWith("나중 날짜부터 시작하는 기능은 아직 지원되지 않아요."));
});

test("/coach K05: a plain next-session question gets no hint and no note", async () => {
  const { app, system } = k05App("Tomorrow you have Upper.");
  const data = await (await post(app, {
    question: "What do I do tomorrow?",
    context: "ctx",
    language: "en",
    capabilities: ["adjust_plan"],
    contract: K05_CONTRACT,
  })).json();
  assert.ok(!system().includes("deferred_start:"));
  assert.equal(data.answer, "Tomorrow you have Upper.");
});

test("/coach K05 (amendment 1a): a question with plan words keeps the card and drops the promise sentence", async () => {
  const { app } = k05App('I\'ve set it to start next Monday. Review it below.\nACTION {"type":"adjustPlan","daysPerWeek":2}');
  const data = await (await post(app, {
    question: "Switch me to 2 days a week starting next Monday.",
    context: "ctx",
    language: "en",
    capabilities: ["adjust_plan"],
    contract: K05_CONTRACT,
  })).json();
  assert.equal(data.answer, `${EN_NOTE} Review it below.`);
  assert.deepEqual(data.action, { type: "adjustPlan", daysPerWeek: 2 });
});

test("/coach K05 (amendment 1b): no plan words -> guardAction drops the card, the note replaces the card-claim reply", async () => {
  const { app } = k05App('I\'ve set it to start next Monday. Review it below.\nACTION {"type":"adjustPlan","daysPerWeek":2,"sessionMinutes":45}');
  const data = await (await post(app, {
    question: "Start that next Monday.",
    context: "ctx",
    language: "en",
    capabilities: ["adjust_plan"],
    contract: K05_CONTRACT,
  })).json();
  assert.equal(data.answer, EN_NOTE);
  assert.equal(data.action, null);
});

// --- K05b: tomorrow answers from the app's (tomorrow) entry ---

const K05B_CONTEXT =
  "today: Saturday, 2026-09-26 10:21 (Asia/Taipei)\nnext_session: Upper on 2026-09-26\nrest_of_week: Saturday 2026-09-26 (today): Upper; Sunday 2026-09-27 (tomorrow): Lower";
const K05B_CONTRACT = {
  contract_version: "coach-contract-v1",
  capabilities: { deferred_plan_start_supported: false, approved_change_scope: "next_unstarted_session" },
  program: { week_basis: "completed_sessions", computed_week: 1, weeks_in_block: 6, deload_week: 6, completed_sessions_since_block_start: 2, sessions_per_program_week: 4, block_start: "2026-09-21" },
  proposal: { type: "adjustPlan", status: "ready", summary: "days per week 2, session 45 min" },
  commit_receipt: null,
};

test("/coach K05b: tomorrow questions get the app's tomorrow entry as a hint (en/vi incl. NFD/ja/ko)", async () => {
  for (const question of [
    "What do I do tomorrow?",
    "Ngày mai tôi tập gì?",
    "Ngày mai tôi tập gì?".normalize("NFD"),
    "明日のメニューは？",
    "내일 운동은 뭐야?",
  ]) {
    const { app, system } = k05App("Tomorrow you have Lower.");
    const res = await post(app, { question, context: K05B_CONTEXT, language: "en", capabilities: ["adjust_plan"] });
    assert.equal(res.status, 200, question);
    assert.ok(system().includes("tomorrow_plan: Sunday 2026-09-27 (tomorrow): Lower;"), question);
  }
});

test("/coach K05b: a next-workout question gets no tomorrow hint", async () => {
  const { app, system } = k05App("Your next session is Upper.");
  const res = await post(app, { question: "What's my next workout?", context: K05B_CONTEXT, language: "en", capabilities: ["adjust_plan"] });
  assert.equal(res.status, 200);
  assert.ok(!system().includes("tomorrow_plan:"));
});

test("/coach K05b: no rest_of_week line means no hint, no crash", async () => {
  const { app, system } = k05App("Tomorrow you have Lower.");
  const res = await post(app, { question: "What do I do tomorrow?", context: "today: Saturday, 2026-09-26", language: "en", capabilities: ["adjust_plan"] });
  assert.equal(res.status, 200);
  assert.ok(!system().includes("tomorrow_plan:"));
});

test("/coach K05b: a tomorrow entry in next week is passed as is", async () => {
  const { app, system } = k05App("Tomorrow you have Lower.");
  const res = await post(app, {
    question: "What do I do tomorrow?",
    context: "rest_of_week: Sunday 2026-09-27 (today): Lower; Monday 2026-09-28 (tomorrow): next week, not in this week's plan",
    language: "en",
    capabilities: ["adjust_plan"],
  });
  assert.equal(res.status, 200);
  assert.ok(system().includes("tomorrow_plan: Monday 2026-09-28 (tomorrow): next week, not in this week's plan;"));
});

test("/coach K05b: a deferred-start question that also asks about tomorrow keeps both hints", async () => {
  const { app, system } = k05App("Your plan stays at 4 days a week. Tomorrow you have Lower.");
  const res = await post(app, {
    question: "Start that next Monday. What do I do tomorrow?",
    context: K05B_CONTEXT,
    language: "en",
    capabilities: ["adjust_plan"],
    contract: K05B_CONTRACT,
  });
  assert.equal(res.status, 200);
  assert.ok(system().includes("deferred_start:"));
  assert.ok(system().includes("tomorrow_plan: Sunday 2026-09-27 (tomorrow): Lower;"));
});

const CARD = { type: "adjustPlan", daysPerWeek: 2, sessionMinutes: 45 } as const;

test("guardAction: date-only day words drop the card (vi/ja/ko/en)", () => {
  for (const question of [
    "Bắt đầu từ thứ Hai tới nhé. Ngày mai tôi tập gì?",
    "Ngày kia tôi tập gì?",
    "Ngày hôm nay tôi tập gì?",
    "Hôm nay tôi tập gì?",
    "明日は何をする？",
    "今日のトレーニングは？",
    "昨日のトレーニングはどうだった？",
    "明後日は何をする？",
    "내일 운동은 뭐야?",
    "오늘 운동 뭐야?",
    "Start that next Monday. What do I do tomorrow?",
  ]) {
    for (const q of [question, question.normalize("NFD")]) {
      assert.equal(guardAction(CARD, q), null, q);
    }
  }
});

test("guardAction: plan-change questions keep the card (vi/ja/ko/en)", () => {
  for (const question of [
    "Giờ tôi chỉ tập được 2 ngày, mỗi buổi 45 phút.",
    "Tôi Chir rảnh. 2 ngày",
    "Tôi muốn tập hàng ngày",
    "週3日しかトレーニングできない",
    "毎日トレーニングしたい",
    "주 3회만 운동할 수 있어",
    "주 3회로 바꿔 주세요",
    "I can only train 2 days a week now",
  ]) {
    for (const q of [question, question.normalize("NFD")]) {
      assert.deepEqual(guardAction(CARD, q), CARD, q);
    }
  }
});

test("isApplyRequest: polite endings and date words are still apply requests", () => {
  for (const question of ["적용해 주세요", "Áp dụng từ ngày mai nhé", "今日から適用して"]) {
    for (const q of [question, question.normalize("NFD")]) {
      assert.equal(isApplyRequest(q), true, q);
    }
  }
  assert.equal(isApplyRequest("주 3회로 바꿔 주세요"), false);
  assert.equal(isApplyRequest("Áp dụng 3 buổi mỗi tuần"), false);
});
