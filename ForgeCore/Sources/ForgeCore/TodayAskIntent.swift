import Foundation

/// The Today question a spoken or typed message asks, classified across the four shipped
/// languages (en, ja, ko, vi). Tiles pass the kind explicitly; free speech needs this.
public enum TodayAskIntent: String, Sendable, Equatable {
  case todayPlan, lastWorkout

  /// The Today question a message asks, if any. Keyword tables per shipped language;
  /// accents and case are ignored.
  public static func classify(_ question: String) -> TodayAskIntent? {
    let q = normalize(question)
    // lastWorkout before todayPlan, so "compare today with my last workout" is lastWorkout.
    if lastWorkoutKeywords.contains(where: { q.contains(normalize($0)) }) { return .lastWorkout }
    if todayPlanKeywords.contains(where: { q.contains(normalize($0)) }) { return .todayPlan }
    return nil
  }

  /// NFC, lowercased, "đ"→"d" (Vietnamese đ does not fold), then diacritic/case/width folding.
  private static func normalize(_ text: String) -> String {
    text
      .precomposedStringWithCanonicalMapping
      .lowercased()
      .replacingOccurrences(of: "đ", with: "d")
      .replacingOccurrences(of: "\u{2019}", with: "'")  // dictation writes a curly apostrophe
      .folding(options: [.diacriticInsensitive, .caseInsensitive, .widthInsensitive], locale: nil)
  }

  private static let lastWorkoutKeywords: [String] = [
    "last workout", "last session", "previous workout", "previous session", "last training", "my last lift",
    "buổi tập trước", "buổi trước", "lần tập trước", "buổi tập vừa rồi", "bài tập hôm trước", "hôm trước tập",
    "前回のトレーニング", "前回のワークアウト", "前回の練習", "この前のトレーニング", "前回",
    "지난 운동", "지난번 운동", "마지막 운동", "저번 운동", "지난 세션",
  ]

  private static let todayPlanKeywords: [String] = [
    "plan today", "today's plan", "todays plan", "plan for today", "today's workout", "workout today",
    "what am i doing today", "what's on today", "what do i train today",
    "kế hoạch hôm nay", "hôm nay tập gì", "bài tập hôm nay", "lịch tập hôm nay", "hôm nay tập", "buổi tập hôm nay",
    "今日のプラン", "今日のメニュー", "今日のトレーニング", "今日は何を", "今日のワークアウト", "今日の予定",
    "오늘 계획", "오늘 운동", "오늘 뭐", "오늘의 운동", "오늘 루틴",
  ]
}
