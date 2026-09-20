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

  /// Phrasings where the lifter has already said *which* weight they mean: their own.
  /// Asking "body weight or the load for an exercise?" after someone wrote "my body weight
  /// is down 0.8 kg" re-asks a question they already answered, so these suppress the
  /// clarification instead of triggering it.
  private static let bodyWeightPhrases = [
    "body weight", "bodyweight", "body mass", "body fat", "scale weight", "on the scale",
    "weigh myself", "weighed myself", "weigh in", "weighed in", "my scale",
  ]

  /// Phrasings that name a lift, a load or a set: the other side of the same ambiguity.
  private static let loadPhrases = [
    "load", "loads", "bar", "barbell", "dumbbell", "dumbbells", "machine", "plate", "plates",
    "squat", "bench", "deadlift", "press", "row", "curl", "pulldown", "pull-up", "pullup",
    "lift", "lifts", "lifting", "set", "sets", "rep", "reps", "working weight", "top set",
  ]

  public static func classify(_ question: String, known: Set<String>) -> CoachIntent {
    let q = question.lowercased()
    let words = Set(q.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init))

    // 1. Medical safety first.
    if !words.isDisjoint(with: medicalWords) || medicalPhrases.contains(where: { q.contains($0) }) {
      return .unsafeOrMedical
    }

    // 2. Weight ambiguity (bodyweight vs lift load) — only when the wording is genuinely
    // bare. A question that already says "body weight", or that names a lift, a load or a
    // set, has answered the clarification in advance.
    let mentionsWeight = words.contains("weigh") || words.contains("weighs")
      || words.contains("weighing") || words.contains("weight") || q.contains("how heavy")
    let saysBodyWeight = bodyWeightPhrases.contains(where: { q.contains($0) })
    let saysLoad = loadPhrases.contains(where: { words.contains($0) })
      || q.contains("working weight") || q.contains("top set")
    if mentionsWeight && !saysBodyWeight && !saysLoad {
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

// MARK: - Clarification follow-ups
//
// A clarification only helps if the *answer* to it goes back to the original question. The
// reply on its own — "Yes", "Body weight" — is not a question, and sending it to a model
// alone is how a coach ends up answering something nobody asked.

/// One clarification the coach asked, kept until the lifter's reply resolves it.
public struct CoachClarification: Sendable, Equatable {
  /// The lifter's original question, verbatim. This is what actually gets answered.
  public let question: String
  public let options: [String]
  /// How many times this clarification has already been re-asked.
  public let attempts: Int

  public init(question: String, options: [String], attempts: Int = 0) {
    self.question = question
    self.options = options
    self.attempts = attempts
  }

  public var retried: CoachClarification {
    CoachClarification(question: question, options: options, attempts: attempts + 1)
  }
}

/// What a reply to a clarification means.
public enum CoachClarificationResolution: Sendable, Equatable {
  /// The reply picked one of the options: answer the original question with that reading.
  case resolved(question: String, choice: String)
  /// A bare "yes"/"ok" that picks nothing: ask once more, listing the options.
  case repeatOptions(CoachClarification)
  /// Still nothing picked: answer the original question rather than stall the lifter.
  case fallbackToOriginal(String)
  /// The reply is a question of its own: forget the clarification and answer that instead.
  case newQuestion(String)
}

public enum CoachClarificationResolver {
  /// Replies that agree without choosing anything. Multilingual because the app is.
  private static let bareAffirmations: Set<String> = [
    "y", "ye", "yes", "yeah", "yep", "yup", "ok", "okay", "k", "sure", "right", "correct",
    "no", "nope", "nah", "both", "either", "idk",
    "có", "vâng", "ừ", "uh", "đúng", "phải", "không",
    "はい", "うん", "ええ", "いいえ", "네", "예", "아니요", "是", "对", "好", "不",
  ]

  public static func resolve(reply: String, pending: CoachClarification) -> CoachClarificationResolution {
    let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
    let normalized = normalize(trimmed)
    guard !normalized.isEmpty else { return .repeatOptions(pending.retried) }

    if let choice = match(normalized, options: pending.options) {
      return .resolved(question: pending.question, choice: choice)
    }
    if bareAffirmations.contains(normalized) {
      return pending.attempts == 0
        ? .repeatOptions(pending.retried)
        : .fallbackToOriginal(pending.question)
    }
    // Anything else is the lifter moving on: a real sentence of their own.
    return .newQuestion(trimmed)
  }

  /// A reply matches an option when either contains the other once punctuation, case and
  /// articles are gone — "body weight", "the body weight one", "Body Weight." all match.
  private static func match(_ normalized: String, options: [String]) -> String? {
    for option in options {
      let candidate = normalize(option)
      guard !candidate.isEmpty else { continue }
      if normalized == candidate { return option }
    }
    for option in options {
      let candidate = normalize(option)
      guard candidate.count >= 3 else { continue }
      if normalized.contains(candidate) || candidate.contains(normalized) { return option }
    }
    return nil
  }

  private static func normalize(_ text: String) -> String {
    let stripped = text.lowercased().unicodeScalars.map { scalar -> Character in
      CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : " "
    }
    let words = String(stripped)
      .split(separator: " ")
      .map(String.init)
      .filter { !["the", "a", "an", "my", "one", "please", "it", "is", "was"].contains($0) }
    return words.joined(separator: " ")
  }
}
