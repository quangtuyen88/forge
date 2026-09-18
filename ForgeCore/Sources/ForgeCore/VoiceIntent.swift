import Foundation

/// The one question a remote classifier answers: which intent was this.
/// It never returns numbers — numbers stay local, extracted from the transcript.
public enum VoiceIntent: String, Sendable, CaseIterable {
  case logSet = "log_set"
  case completeSet = "complete_set"
  case startRest = "start_rest"
  case skipRest = "skip_rest"
  case changeWeight = "change_weight"
  case changeReps = "change_reps"
  case changeRPE = "change_rpe"
  case nextExercise = "next_exercise"
  case askCoach = "ask_coach"
  case swapExercise = "swap_exercise"
  case confirm, cancel, undo
  case none

  /// One plain sentence per case, written for the classifier to read.
  /// Criteria map only — never shown to a lifter, must stay in English.
  public var rubric: String {
    switch self {
    case .logSet: return "Log a completed set of an exercise with a weight, a rep count, and an optional RPE."
    case .completeSet: return "Finish and record the set that was just performed."
    case .startRest: return "Start or set a rest timer."
    case .skipRest: return "End or skip the running rest timer."
    case .changeWeight: return "Increase or decrease the weight on the bar for the next set."
    case .changeReps: return "Change the planned rep count for the exercise, as a target or an adjustment."
    case .changeRPE: return "Change the target rating of perceived exertion, between 5 and 10."
    case .nextExercise: return "Move on to the next exercise in the workout."
    case .askCoach: return "Ask the coach a question about training, form, or the program."
    case .swapExercise: return "Replace the current exercise with a different named exercise."
    case .confirm: return "Agree to or approve a pending action."
    case .cancel: return "Reject or stop a pending action."
    case .undo: return "Revert the last logged action."
    case .none: return "Gym noise, chatter, or nothing the app can act on."
    }
  }
}

// ponytail: normalize/number-word folding duplicated from VoiceCommand.swift because that
// file is off-limits and its helpers are private; merge there if file ownership changes.
public extension VoiceCommandParser {
  /// Build a command from a classified intent. The local `parse` always wins; the
  /// classifier only rescues phrasings the anchored patterns do not cover.
  static func command(
    for intent: VoiceIntent,
    transcript: String,
    candidates: [QuickLogCandidate],
    defaultLb: Bool,
    language: VoiceLanguage
  ) -> VoiceCommand {
    let original = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    let local = parse(transcript, candidates: candidates, defaultLb: defaultLb, language: language)
    if case .unrecognised = local {} else { return local }

    let table = VoicePhraseTable.forLanguage(language)
    let tokens = normalize(transcript, language: language)
      .split(separator: " ").map(String.init)

    switch intent {
    case .completeSet: return .completeSet
    case .skipRest: return .skipRest
    case .nextExercise: return .nextExercise
    case .confirm: return .confirm
    case .cancel: return .cancel
    case .undo: return .undo

    case .startRest:
      return .startRest(seconds: IntentScan.firstDuration(tokens, table: table))

    case .changeWeight:
      guard let (value, idx) = IntentScan.firstNumber(tokens),
            let sign = IntentScan.sign(tokens, language: language) else {
        return .unrecognised(original)
      }
      let next = idx + 1 < tokens.count ? tokens[idx + 1] : ""
      let kg = kgValue(value, unit: IntentScan.unitWord(next, table: table), defaultLb: defaultLb,
                       poundWords: folded(table.poundWords))
      return .changeWeight(deltaKg: Double(sign) * kg)

    case .changeReps:
      guard let (n, _) = IntentScan.firstInteger(tokens) else { return .unrecognised(original) }
      if let sign = IntentScan.sign(tokens, language: language) {
        return .changeReps(to: nil, delta: sign * n)
      }
      return .changeReps(to: n, delta: nil)

    case .changeRPE:
      guard let (v, _) = IntentScan.firstNumber(tokens), (5...10).contains(v) else {
        return .unrecognised(original)
      }
      return .changeRPE(v)

    case .logSet:
      guard let set = IntentScan.set(tokens, table: table, defaultLb: defaultLb) else {
        return .unrecognised(original)
      }
      return .logSet(set)

    case .swapExercise:
      guard let ex = IntentScan.exercise(tokens) else { return .unrecognised(original) }
      return .swapExercise(exerciseID: ex.id)

    case .askCoach:
      return .askCoach(original)

    case .none:
      return .unrecognised(original)
    }
  }
}

/// Free-form scanning over a normalised transcript. The anchored regexes in
/// `VoiceCommand.swift` stay strict; these helpers see a number wherever it appears.
/// The shared pipeline (fold, normalize, number-word conversion, kg conversion) lives in
/// `VoiceCommandParser`; only what has no anchored equivalent is here.
private enum IntentScan {
  /// The shared `number` answers `?? 0` for regex captures that are always numeric;
  /// scanning needs to tell a non-numeric token from a spoken zero, so it stays optional here.
  private static func tokenNumber(_ tok: String) -> Double? {
    Double(tok.replacingOccurrences(of: ",", with: "."))
  }

  /// The token itself if it is a unit word, else "" (no unit spoken).
  static func unitWord(_ tok: String, table: VoicePhraseTable) -> String {
    let words = Set(VoiceCommandParser.folded(table.kiloWords) + VoiceCommandParser.folded(table.poundWords))
    return words.contains(tok) ? tok : ""
  }

  // MARK: - Scanning

  /// First numeric token: its value and index.
  static func firstNumber(_ tokens: [String]) -> (Double, Int)? {
    for (i, tok) in tokens.enumerated() {
      if let v = tokenNumber(tok) { return (v, i) }
    }
    return nil
  }

  /// First numeric token that is a whole number.
  static func firstInteger(_ tokens: [String]) -> (Int, Int)? {
    for (i, tok) in tokens.enumerated() {
      if let d = tokenNumber(tok), d == d.rounded() { return (Int(d), i) }
    }
    return nil
  }

  /// First `N <minute|second word>` pair, in seconds. Minutes multiply by 60.
  static func firstDuration(_ tokens: [String], table: VoicePhraseTable) -> Int? {
    let minutes = Set(VoiceCommandParser.folded(table.restMinuteWords))
    let seconds = Set(VoiceCommandParser.folded(table.restSecondWords))
    for (i, tok) in tokens.enumerated() {
      guard let v = tokenNumber(tok), i + 1 < tokens.count else { continue }
      if minutes.contains(tokens[i + 1]) { return Int((v * 60).rounded()) }
      if seconds.contains(tokens[i + 1]) { return Int(v.rounded()) }
    }
    return nil
  }

  /// +1 if an add word appears, -1 if a remove word does, nil otherwise.
  /// Free-form speech uses words the anchored tables lack ("another", "more"), so the
  /// classifier path widens the lists instead of loosening the local parser.
  static func sign(_ tokens: [String], language: VoiceLanguage) -> Int? {
    let table = VoicePhraseTable.forLanguage(language)
    let extras: (add: [String], remove: [String]) = language == .en
      ? (["another", "more", "extra"], ["less", "fewer"])
      : ([], [])
    let joined = " " + tokens.joined(separator: " ") + " "
    for phrase in VoiceCommandParser.folded(table.addWords) + VoiceCommandParser.folded(extras.add) {
      if joined.contains(wordBounded(phrase)) { return 1 }
    }
    for phrase in VoiceCommandParser.folded(table.removeWords) + VoiceCommandParser.folded(extras.remove) {
      if joined.contains(wordBounded(phrase)) { return -1 }
    }
    return nil
  }

  private static func wordBounded(_ phrase: String) -> String {
    // Match as whole tokens by padding with spaces; the joined string is space-separated.
    return " " + phrase + " "
  }

  /// A free-form set needs a load and a rep count; the exercise name is matched from the
  /// leftover words, else left empty for the caller to resolve to the active exercise.
  static func set(_ tokens: [String], table: VoicePhraseTable, defaultLb: Bool) -> QuickLogParse? {
    let kilos = Set(VoiceCommandParser.folded(table.kiloWords) + VoiceCommandParser.folded(table.poundWords))
    let pounds = VoiceCommandParser.folded(table.poundWords)
    let reps = Set(VoiceCommandParser.folded(table.repWords))

    var weight: (Double, Int)? = nil
    var repCount: (Int, Int)? = nil
    for (i, tok) in tokens.enumerated() {
      guard let v = tokenNumber(tok) else { continue }
      if repCount == nil, i + 1 < tokens.count, reps.contains(tokens[i + 1]), v >= 1 {
        repCount = (Int(v), i)
      }
      if weight == nil, i + 1 < tokens.count, kilos.contains(tokens[i + 1]) {
        weight = (VoiceCommandParser.kgValue(v, unit: tokens[i + 1], defaultLb: defaultLb, poundWords: pounds), i)
      }
    }
    // Without a unit word, the first non-rep number still counts as the load.
    if weight == nil, let (v, i) = firstNumber(tokens), repCount == nil || repCount!.1 != i {
      weight = (VoiceCommandParser.kgValue(v, unit: "", defaultLb: defaultLb, poundWords: pounds), i)
    }
    guard let w = weight, let r = repCount else { return nil }

    var rpe: Double? = nil
    if let at = tokens.firstIndex(where: { $0 == "rpe" || $0 == "@" }),
       at + 1 < tokens.count, let v = tokenNumber(tokens[at + 1]) {
      rpe = v
    }

    let skip = [w.1, r.1, r.1 + 1] + (weight!.1 + 1 < tokens.count ? [weight!.1 + 1] : [])
    let filler = Set(VoiceCommandParser.folded(table.connectors) + ["rpe", "@"])
    let leftovers = tokens.enumerated()
      .filter { !skip.contains($0.offset) && tokenNumber($0.element) == nil && !kilos.contains($0.element) && !reps.contains($0.element) && !filler.contains($0.element) }
      .map(\.element)
    // Same rule as the Vietnamese grammar: an empty name resolves to the active
    // exercise, but a spoken name that fails to match must not log onto it silently.
    let exerciseID: String
    if leftovers.isEmpty {
      exerciseID = ""
    } else if let ex = ngram(leftovers) {
      exerciseID = ex.id
    } else {
      return nil
    }
    return QuickLogParse(
      exerciseID: exerciseID,
      weightKg: w.0, reps: r.0, rpe: rpe)
  }

  /// Longest-first n-gram match against the exercise database.
  static func exercise(_ tokens: [String]) -> Exercise? {
    ngram(tokens.filter { tokenNumber($0) == nil })
  }

  private static func ngram(_ words: [String]) -> Exercise? {
    for len in stride(from: min(4, words.count), through: 1, by: -1) {
      for start in 0...(words.count - len) {
        let phrase = words[start..<(start + len)].joined(separator: " ")
        if let ex = WorkoutImport.match(phrase) { return ex }
      }
    }
    return nil
  }
}
