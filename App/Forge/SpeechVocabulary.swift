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
}
