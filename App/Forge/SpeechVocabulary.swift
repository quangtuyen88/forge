import Foundation
import ForgeCore

/// Contextual vocabulary for dictation: exercise names first, then lifting terms.
enum SpeechVocabulary {
  static func lifting(extra: [String]) -> [String] {
    var out: [String] = []
    var seen = Set<String>()
    func add(_ s: String) { let k = s.lowercased(); if !k.isEmpty, !seen.contains(k) { seen.insert(k); out.append(s) } }
    extra.forEach(add)
    ["deadlift", "Romanian deadlift", "back squat", "front squat", "bench press", "overhead press", "lat pulldown", "landmine press",
     "barbell curl", "calf raise", "RPE", "reps", "sets", "kilos", "kg", "pounds", "lb", "deload", "swap", "warm-up", "one rep max"].forEach(add)
    ExerciseDB.everything.map(\.name).forEach(add)
    return out
  }

  static func coach(extra: [String]) -> [String] {
    var terms = lifting(extra: extra)
    let localized: [String]
    switch L10n.languageCode {
    case "vi":
      localized = ["vì sao", "giảm tải", "tăng tải", "đổi bài", "buổi tập", "kế hoạch tập", "mức tạ", "số hiệp", "số lần", "phục hồi", "đau cơ", "nghỉ giữa hiệp"]
    case "ja":
      localized = ["なぜ", "重量", "回数", "セット", "トレーニング", "回復", "種目変更", "ディロード"]
    case "ko":
      localized = ["왜", "중량", "반복", "세트", "운동 계획", "회복", "운동 교체", "디로드"]
    case "zh-Hans":
      localized = ["为什么", "重量", "次数", "组数", "训练计划", "恢复", "更换动作", "减量"]
    default:
      localized = ["why", "weight", "reps", "sets", "workout plan", "recovery", "swap exercise", "deload"]
    }
    let existing = Set(terms.map { $0.lowercased() })
    terms.append(contentsOf: localized.filter { !existing.contains($0.lowercased()) })
    return terms
  }
}
