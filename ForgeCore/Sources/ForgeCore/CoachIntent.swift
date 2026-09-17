import Foundation

public enum CoachIntent: Sendable, Equatable {
  case trainingQuestion
  case profileFactMissing(field: String)
  case ambiguous(options: [String])
  case unsafeOrMedical
  case outOfScope
}

public enum CoachIntentClassifier {
  private static let medicalWords: Set<String> = [
    "pain", "painful", "hurt", "hurts", "hurting", "injury", "injured", "injure", "torn",
    "sprain", "sprained", "strain", "strained", "diagnosis", "diagnosed", "diagnose",
    "medication", "medicine", "meds", "prescription", "rehab", "rehabilitation", "physio",
  ]
  private static let medicalPhrases = ["physical therapy", "see a doctor", "consult a doctor"]

  private static let factWords: [(word: String, field: String)] = [
    ("birthday", "birthday"), ("born", "birthday"), ("age", "age"),
    ("height", "height"), ("tall", "height"), ("name", "name"), ("email", "email"),
  ]
  private static let factPhrases: [(phrase: String, field: String)] = [
    ("date of birth", "birthday"), ("years old", "age"), ("how old", "age"),
  ]

  private static let outOfScopeWords: Set<String> = [
    "weather", "forecast", "recipe", "cook", "joke", "movie", "film", "politics", "election", "news", "music", "song",
  ]

  public static func classify(_ question: String, known: Set<String>) -> CoachIntent {
    let q = question.lowercased()
    let words = Set(q.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))

    // 1. Medical safety first.
    if !words.isDisjoint(with: medicalWords) || medicalPhrases.contains(where: { q.contains($0) }) {
      return .unsafeOrMedical
    }

    // 2. Weight ambiguity (bodyweight vs lift load).
    let weightAmbiguous = words.contains("weigh") || words.contains("weighs") || words.contains("weighing")
      || q.contains("bodyweight") || q.contains("body weight") || q.contains("how heavy")
    if weightAmbiguous {
      return .ambiguous(options: ["Body weight", "The load for an exercise"])
    }

    // 3. Missing personal facts.
    for (word, field) in factWords where words.contains(word) {
      if !known.contains(field) { return .profileFactMissing(field: field) }
    }
    for (phrase, field) in factPhrases where q.contains(phrase) {
      if !known.contains(field) { return .profileFactMissing(field: field) }
    }

    // 4. Out of scope vs training.
    if !words.isDisjoint(with: outOfScopeWords) { return .outOfScope }
    return .trainingQuestion
  }
}
