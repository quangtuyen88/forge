import test from "node:test";
import assert from "node:assert/strict";
import { createApp, guardAction, isThisWeekOnly, parseAction, questionLanguage } from "../app.js";
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

test("questionLanguage: letters only one shipped language uses", () => {
  assert.equal(questionLanguage("Ừ, áp dụng đi."), "vi");
  assert.equal(questionLanguage("Ừ, áp dụng đi.".normalize("NFD")), "vi");
  assert.equal(questionLanguage("適用して"), "ja");
  assert.equal(questionLanguage("적용해 줘"), "ko");
  assert.equal(questionLanguage("Yes, apply it."), undefined);
  assert.equal(questionLanguage("toi muon giam tap"), undefined);
  assert.equal(questionLanguage("Can I swap Barbell Curl?"), undefined);
});

const VI_APPLY_ON_CARD =
  "Để áp dụng, bạn chạm nút Áp dụng trên thẻ thay đổi. Kế hoạch chưa thay đổi cho đến lúc đó.";
const JA_APPLY_ON_CARD =
  "適用するには、変更カードの「適用」をタップしてください。タップするまで何も変わりません。";

test("/coach: the trusted apply route replies in the question's language", async () => {
  for (const [question, expected] of [
    ["Ừ, áp dụng đi.", VI_APPLY_ON_CARD],
    ["Ừ, áp dụng đi.".normalize("NFD"), VI_APPLY_ON_CARD],
    ["適用して", JA_APPLY_ON_CARD],
  ] as const) {
    const data = await (await post(coachApp("unused"), {
      question,
      context: "ctx",
      language: "en",
      contract: K05_CONTRACT,
    })).json();
    assert.equal(data.answer, expected, question);
  }
});

test("/coach: the system prompt follows the question's language", async () => {
  const { app, system } = k05App("Mình đã ghi nhận yêu cầu của bạn.");
  await post(app, { question: "Tôi muốn tập 2 ngày mỗi tuần", context: "ctx", language: "en", capabilities: ["adjust_plan"] });
  assert.ok(system().includes("Reply in Vietnamese"));
  assert.ok(!system().includes("Reply in English"));
});

test("/coach: an English question keeps the request language", async () => {
  const { app, system } = k05App("Tomorrow you have Upper.");
  await post(app, { question: "What do I do tomorrow?", context: "ctx", language: "vi" });
  assert.ok(system().includes("Reply in Vietnamese"));
});

const VI_MINUTES_3_45 =
  "Buổi tập trong Regulift dài 45, 60 hoặc 90 phút, nên không đặt được 3 phút. Thẻ bên dưới dùng 45 phút; chỉ áp dụng nếu đúng ý bạn.";
const EN_MINUTES_30_45 =
  "Regulift sessions are 45, 60 or 90 minutes, so 30 minutes isn't possible. The card below uses 45 minutes; apply it only if that's what you want.";
const JA_MINUTES_30_45 =
  "Reguliftのセッションは45分・60分・90分のいずれかなので、30分にはできません。下のカードは45分です。希望どおりの場合だけ適用してください。";
const KO_MINUTES_20_45 =
  "레귤리프트 세션은 45분, 60분, 90분 중 하나라서 20분으로는 설정할 수 없어요. 아래 카드는 45분이에요. 원하는 내용일 때만 적용해 주세요.";
const VI_DAYS_1_2 =
  "Regulift lập kế hoạch 2 đến 6 buổi mỗi tuần, nên không đặt được 1 buổi. Thẻ bên dưới dùng 2 buổi; chỉ áp dụng nếu đúng ý bạn.";
const EN_DAYS_7_6 =
  "Regulift plans 2 to 6 training days a week, so 7 days a week isn't possible. The card below uses 6 days; apply it only if that's what you want.";

test("/coach value note: the owner's case gets the vi minutes note in front (also NFD)", async () => {
  const text = "Tôi đã chuẩn bị kế hoạch mới với thời gian mỗi buổi tập giảm xuống 45 phút. Hãy xem lại bên dưới.";
  for (const question of ["Tôi muốn giảm mỗi bay tập trung còn 3 phút", "Tôi muốn giảm mỗi bay tập trung còn 3 phút".normalize("NFD")]) {
    const data = await (await post(coachApp(`${text}\nACTION {"type":"adjustPlan","sessionMinutes":45}`), {
      question,
      context: "ctx",
      language: "en",
      capabilities: ["adjust_plan"],
    })).json();
    assert.ok(data.answer.startsWith(VI_MINUTES_3_45), question);
    assert.equal(data.answer, `${VI_MINUTES_3_45} ${text}`);
    assert.deepEqual(data.action, { type: "adjustPlan", sessionMinutes: 45 });
  }
});

test("/coach value note: en minutes note", async () => {
  const text = "I've prepared 45-minute sessions. Review it below.";
  const data = await (await post(coachApp(`${text}\nACTION {"type":"adjustPlan","sessionMinutes":45}`), {
    question: "Make my sessions 30 minutes",
    context: "ctx",
    language: "en",
    capabilities: ["adjust_plan"],
  })).json();
  assert.equal(data.answer, `${EN_MINUTES_30_45} ${text}`);
});

test("/coach value note: ja note only, a 1回 match adds no days note without daysPerWeek", async () => {
  const text = "45分のセッションを準備しました。下で確認してください。";
  const data = await (await post(coachApp(`${text}\nACTION {"type":"adjustPlan","sessionMinutes":45}`), {
    question: "1回30分にしたい",
    context: "ctx",
    language: "ja",
    capabilities: ["adjust_plan"],
  })).json();
  assert.equal(data.answer, `${JA_MINUTES_30_45} ${text}`);
});

test("/coach value note: ko minutes note", async () => {
  const text = "45분으로 준비했어요. 아래에서 확인해 주세요.";
  const data = await (await post(coachApp(`${text}\nACTION {"type":"adjustPlan","sessionMinutes":45}`), {
    question: "세션을 20분으로 줄여줘",
    context: "ctx",
    language: "ko",
    capabilities: ["adjust_plan"],
  })).json();
  assert.equal(data.answer, `${KO_MINUTES_20_45} ${text}`);
});

test("/coach value note: vi days note below the 2-day minimum", async () => {
  const text = "Mình đã chuẩn bị 2 buổi mỗi tuần. Bạn xem lại bên dưới nhé.";
  const data = await (await post(coachApp(`${text}\nACTION {"type":"adjustPlan","daysPerWeek":2}`), {
    question: "Tôi chỉ tập được 1 ngày mỗi tuần",
    context: "ctx",
    language: "vi",
    capabilities: ["adjust_plan"],
  })).json();
  assert.equal(data.answer, `${VI_DAYS_1_2} ${text}`);
});

test("/coach value note: en days note above the 6-day maximum", async () => {
  const text = "I've prepared 6 days a week. Review it below.";
  const data = await (await post(coachApp(`${text}\nACTION {"type":"adjustPlan","daysPerWeek":6}`), {
    question: "I can train 7 days a week",
    context: "ctx",
    language: "en",
    capabilities: ["adjust_plan"],
  })).json();
  assert.equal(data.answer, `${EN_DAYS_7_6} ${text}`);
});

test("/coach value note: no mismatch means the answer is unchanged", async () => {
  const matching = await (await post(coachApp('Bạn vẫn tập 2 ngày mỗi tuần, mỗi buổi 45 phút.\nACTION {"type":"adjustPlan","daysPerWeek":2,"sessionMinutes":45}'), {
    question: "Giờ tôi chỉ tập được 2 ngày, mỗi buổi 45 phút.",
    context: "ctx",
    language: "vi",
    capabilities: ["adjust_plan"],
  })).json();
  assert.equal(matching.answer, "Bạn vẫn tập 2 ngày mỗi tuần, mỗi buổi 45 phút.");
  assert.deepEqual(matching.action, { type: "adjustPlan", daysPerWeek: 2, sessionMinutes: 45 });

  const units = await (await post(coachApp('Kế hoạch giữ nguyên 2 ngày, mỗi buổi 45 phút.\nACTION {"type":"adjustPlan","daysPerWeek":2,"sessionMinutes":45}'), {
    question: "Giờ tôi chỉ tập được 2 ngày mỗi tuần và muốn giảm tạ 10kg, còn 3 hiệp mỗi buổi",
    context: "ctx",
    language: "vi",
    capabilities: ["adjust_plan"],
  })).json();
  assert.equal(units.answer, "Kế hoạch giữ nguyên 2 ngày, mỗi buổi 45 phút.");
  assert.deepEqual(units.action, { type: "adjustPlan", daysPerWeek: 2, sessionMinutes: 45 });

  // No plan-change intent: guardAction drops the card, so no note and no card claim in the text.
  for (const [question, text] of [
    ["I want shorter sessions", "Sessions keep their current length."],
    ["Tôi muốn giảm tạ 10kg", "Để giảm tạ, bạn chỉnh mức tạ trên mỗi hiệp trong bài tập."],
    ["Tôi muốn giảm còn 3 hiệp", "Bạn vẫn giữ số hiệp như hiện tại nhé."],
  ] as const) {
    const data = await (await post(coachApp(`${text}\nACTION {"type":"adjustPlan","sessionMinutes":45}`), {
      question,
      context: "ctx",
      language: "vi",
      capabilities: ["adjust_plan"],
    })).json();
    assert.equal(data.answer, text, question);
    assert.equal(data.action, null, question);
  }

  const noCard = await (await post(coachApp("Tomorrow you have Upper."), {
    question: "What do I do tomorrow?",
    context: "ctx",
    language: "en",
    capabilities: ["adjust_plan"],
  })).json();
  assert.equal(noCard.answer, "Tomorrow you have Upper.");
  assert.equal(noCard.action, null);
});

test("/coach value note: an unsupported ACTION still gets the fixed template", async () => {
  const data = await (await post(coachApp('Sure.\nACTION {"type":"adjustPlan","sessionMinutes":30}'), {
    question: "Make my sessions 30 minutes",
    context: "ctx",
    language: "en",
    capabilities: ["adjust_plan"],
  })).json();
  assert.equal(
    data.answer,
    "Regulift plans 2 to 6 training days a week with 45, 60 or 90-minute sessions, so I can't set that up. Tell me a supported option, for example 2 days a week with 45-minute sessions, and I'll prepare it.",
  );
  assert.equal(data.action, null);
});
