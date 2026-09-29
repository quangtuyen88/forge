import XCTest
@testable import ForgeCore

final class TodayAskIntentTests: XCTestCase {
  private func assertIntent(
    _ expected: TodayAskIntent?, _ questions: [String],
    file: StaticString = #filePath, line: UInt = #line
  ) {
    for q in questions {
      XCTAssertEqual(TodayAskIntent.classify(q), expected, "input: \(q)", file: file, line: line)
    }
  }

  // MARK: - English

  func testEnglishTodayPlan() {
    assertIntent(.todayPlan, [
      "what's my plan today",
      "show me today's plan",
      "what am i doing today",
      "today's workout please",
      "what's my workout today",
    ])
  }

  func testDictationCurlyApostrophe() {
    assertIntent(.todayPlan, ["Show me today\u{2019}s plan", "Today\u{2019}s workout?"])
  }

  func testEnglishLastWorkout() {
    assertIntent(.lastWorkout, [
      "what was my last workout?",
      "show my last session",
      "my previous workout",
      "previous session summary",
      "my last lift",
    ])
  }

  func testEnglishMixedCase() {
    assertIntent(.todayPlan, ["What Is My PLAN Today?"])
    assertIntent(.lastWorkout, ["Show My LAST WORKOUT"])
  }

  // MARK: - Vietnamese

  func testVietnameseTodayPlan() {
    assertIntent(.todayPlan, [
      "kế hoạch hôm nay",
      "hôm nay tập gì",
      "bài tập hôm nay",
      "lịch tập hôm nay",
      "buổi tập hôm nay",
    ])
  }

  func testVietnameseLastWorkout() {
    assertIntent(.lastWorkout, [
      "buổi tập trước",
      "buổi trước",
      "lần tập trước",
      "buổi tập vừa rồi",
      "bài tập hôm trước",
      "hôm trước tập gì",
    ])
  }

  func testVietnameseNoAccents() {
    assertIntent(.todayPlan, ["ke hoach hom nay", "hom nay tap gi"])
    assertIntent(.lastWorkout, ["buoi tap truoc"])
  }

  func testVietnameseNFDInput() {
    assertIntent(.todayPlan, ["kế hoạch hôm nay".decomposedStringWithCanonicalMapping])
    assertIntent(.lastWorkout, ["buổi tập trước".decomposedStringWithCanonicalMapping])
  }

  // MARK: - Japanese

  func testJapaneseTodayPlan() {
    assertIntent(.todayPlan, [
      "今日のプラン",
      "今日のメニュー",
      "今日のトレーニング",
      "今日は何をする",
      "今日のワークアウト",
      "今日の予定",
    ])
  }

  func testJapaneseLastWorkout() {
    assertIntent(.lastWorkout, [
      "前回のトレーニング",
      "前回のワークアウト",
      "前回の練習",
      "この前のトレーニング",
      "前回はどうだった",
    ])
  }

  // MARK: - Korean

  func testKoreanTodayPlan() {
    assertIntent(.todayPlan, [
      "오늘 계획",
      "오늘 운동",
      "오늘 뭐 해",
      "오늘의 운동",
      "오늘 루틴",
    ])
  }

  func testKoreanLastWorkout() {
    assertIntent(.lastWorkout, [
      "지난 운동",
      "지난번 운동",
      "마지막 운동",
      "저번 운동",
      "지난 세션",
    ])
  }

  // MARK: - Ordering and negatives

  func testTodayVsLastWorkoutPrefersLastWorkout() {
    assertIntent(.lastWorkout, ["Compare today with my last workout"])
  }

  func testNegativesReturnNil() {
    assertIntent(nil, [
      "How do I squat deeper?",
      "Tôi muốn thay đổi tạ",
      "スクワットのフォーム",
      "벤치 무게",
    ])
  }

  func testEmptyAndUnrelatedReturnNil() {
    assertIntent(nil, ["", "hello", "weather forecast please"])
  }
}
