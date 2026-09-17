import Foundation

/// How the app may act on a command without further confirmation.
public enum VoiceConsequence: Sendable, Equatable {
  case immediate     // harmless and self-evident: run, no confirmation, no undo needed
  case undoable      // changes the log or the editor: run, show an Undo affordance
  case confirm       // destructive or ambiguous: never run without an explicit yes
}

/// A non-committal read of a transcript still being spoken.
public struct VoiceCandidate: Sendable, Equatable {
  public let command: VoiceCommand
  /// False while the utterance still looks unfinished, e.g. "eight reps at".
  public let isComplete: Bool

  public init(command: VoiceCommand, isComplete: Bool) {
    self.command = command
    self.isComplete = isComplete
  }
}

public enum VoiceCommand: Sendable, Equatable {
  /// "bench 80 for 8 at rpe 8", "deadlift 132.5 for 8 at 8"
  case logSet(QuickLogParse)
  /// "complete set", "done", "log it", "that's it"
  case completeSet
  /// "start 2 minute rest", "rest 90 seconds", "start rest"
  case startRest(seconds: Int?)
  /// "skip rest", "skip the timer"
  case skipRest
  /// "add 5 kilos", "minus 2.5 kg", "add 10 pounds"
  case changeWeight(deltaKg: Double)
  /// "make it 9 reps", "add 2 reps", "one less rep"
  case changeReps(to: Int?, delta: Int?)
  /// "rpe 8", "make it rpe 9.5"
  case changeRPE(Double)
  /// "next exercise", "move on"
  case nextExercise
  /// "ask coach why did bench change", everything after "ask coach" is the question
  case askCoach(String)
  /// "swap bench", "change squat" — the app must show options, never swap silently
  case swapExercise(exerciseID: String)
  /// "confirm", "yes", "do it", "go ahead"
  case confirm
  /// "cancel", "no", "stop", "never mind"
  case cancel
  /// "undo", "undo that", "scratch that"
  case undo
  case unrecognised(String)

  public var consequence: VoiceConsequence {
    consequence(fastLogging: false)
  }

  @available(*, deprecated, message: "Use consequence instead")
  public var needsConfirmation: Bool {
    consequence == .confirm
  }

  private static func fmt(_ d: Double) -> String {
    d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
  }

  /// One line for the confirmation card: "Deadlift · 132.5 kg × 8 @ 8", "Rest 2:00", "Add 5 kg".
  public func summary(weight: (Double) -> String) -> String {
    switch self {
    case .logSet(let p):
      let name = ExerciseDB.find(p.exerciseID)?.name ?? p.exerciseID
      var s = "\(name) · \(weight(p.weightKg)) × \(p.reps)"
      if let rpe = p.rpe { s += " @ \(VoiceCommand.fmt(rpe))" }
      return s
    case .completeSet: return String(localized: "Set complete", bundle: ForgeCoreResources.bundle)
    case .startRest(let seconds):
      if let seconds {
        return "Rest \(seconds / 60):\(String(format: "%02d", seconds % 60))"
      }
      return String(localized: "Start rest", bundle: ForgeCoreResources.bundle)
    case .skipRest: return String(localized: "Skip rest", bundle: ForgeCoreResources.bundle)
    case .changeWeight(let deltaKg):
      return deltaKg >= 0 ? "Add \(weight(deltaKg))" : "Remove \(weight(-deltaKg))"
    case .changeReps(let to, let delta):
      if let to { return "\(to) reps" }
      if let delta { return "\(delta > 0 ? "+" : "")\(delta) reps" }
      return ""
    case .changeRPE(let rpe): return "RPE \(VoiceCommand.fmt(rpe))"
    case .nextExercise: return String(localized: "Next exercise", bundle: ForgeCoreResources.bundle)
    case .askCoach(let q): return q.isEmpty ? "Ask coach" : "Ask coach: \(q)"
    case .swapExercise(let id):
      let name = ExerciseDB.find(id)?.name ?? id
      return "Swap \(name)"
    case .confirm: return String(localized: "Confirm", bundle: ForgeCoreResources.bundle)
    case .cancel: return String(localized: "Cancel", bundle: ForgeCoreResources.bundle)
    case .undo: return String(localized: "Undo", bundle: ForgeCoreResources.bundle)
    case .unrecognised(let raw): return raw
    }
  }
}

public enum VoiceLanguage: String, Sendable, CaseIterable {
  case en, vi
}

public enum VoiceCommandParser {
  private static let tensValues: Set<Int> = [20, 30, 40, 50, 60, 70, 80, 90]

  // MARK: - Normalisation

  /// Lowercase, strip diacritics (so a transcript without tone marks still matches),
  /// then replace spoken numbers with digits. This is what every regex compares against.
  private static func normalize(_ raw: String, language: VoiceLanguage) -> String {
    var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    // Vietnamese đ has no combining mark, so folding leaves it; map it explicitly.
    s = s.replacingOccurrences(of: "đ", with: "d").replacingOccurrences(of: "Đ", with: "d")
    s = s.folding(options: [.diacriticInsensitive], locale: nil)
    s = s.replacingOccurrences(of: "at rpe", with: "rpe")
    s = s.replacingOccurrences(of: "-", with: " ")
    var cleaned = ""
    for ch in s {
      if ch.isLetter || ch.isNumber || ch == "." || ch == "," || ch == "×" || ch == "*" || ch == "@" {
        cleaned.append(ch)
      } else if ch == "'" || ch == "’" {
        continue  // drop apostrophes: "that's" → "thats"
      } else {
        cleaned.append(" ")
      }
    }
    // Dictation punctuates sentences: "complete set." must still match. Keep a dot or
    // comma only between digits so decimals like 132.5 survive.
    let chars = Array(cleaned)
    var kept = ""
    for (i, ch) in chars.enumerated() {
      if ch == "." || ch == "," {
        let prev = i > 0 ? chars[i - 1] : " "
        let next = i + 1 < chars.count ? chars[i + 1] : " "
        guard prev.isNumber && next.isNumber else { continue }
      }
      kept.append(ch)
    }
    let tokens = kept.split(separator: " ").map(String.init)
    return applyHalf(convertWordNumbers(tokens, language: language))
  }

  private static func fold(_ s: String) -> String {
    s.lowercased()
      .replacingOccurrences(of: "đ", with: "d")
      .folding(options: [.diacriticInsensitive], locale: nil)
  }

  private static func folded(_ words: [String]) -> [String] {
    words.map(fold)
  }

  /// Escaped regex alternation like `minute|minutes|min|mins`.
  private static func alternation(_ words: [String]) -> String {
    words.map { NSRegularExpression.escapedPattern(for: $0) }.joined(separator: "|")
  }

  // MARK: - Spoken numbers

  private static func convertWordNumbers(_ tokens: [String], language: VoiceLanguage) -> String {
    switch language {
    case .en: return convertEnglishNumbers(tokens)
    case .vi: return convertVietnameseNumbers(tokens)
    }
  }

  private static func convertEnglishNumbers(_ tokens: [String]) -> String {
    let numbers = VoicePhraseTable.english.numbers
    var out: [String] = []
    var i = 0
    while i < tokens.count {
      let w = tokens[i]
      if let tens = numbers[w], tensValues.contains(tens), i + 1 < tokens.count,
         let ones = numbers[tokens[i + 1]], (1...9).contains(ones) {
        out.append(String(tens + ones))
        i += 2
      } else if let n = numbers[w] {
        out.append(String(n))
        i += 1
      } else {
        out.append(w)
        i += 1
      }
    }
    return out.joined(separator: " ")
  }

  private static func convertVietnameseNumbers(_ tokens: [String]) -> String {
    let numbers = VoicePhraseTable.vietnamese.numbers
    let numberWords = Set(numbers.keys).union(["muoi", "tram"])
    var out: [String] = []
    var i = 0
    while i < tokens.count {
      if numberWords.contains(tokens[i]) {
        var run: [String] = []
        while i < tokens.count, numberWords.contains(tokens[i]) {
          run.append(tokens[i])
          i += 1
        }
        if let value = viNumber(run, numbers: numbers) {
          out.append(value == value.rounded() ? String(Int(value)) : String(value))
        } else {
          out.append(contentsOf: run)
        }
      } else {
        out.append(tokens[i])
        i += 1
      }
    }
    return out.joined(separator: " ")
  }

  /// "tám mươi lăm" → 85, "mười lăm" → 15, "hai mươi mốt" → 21, "một trăm" → 100.
  private static func viNumber(_ run: [String], numbers: [String: Int]) -> Double? {
    var current = 0.0
    for w in run {
      switch w {
      case "muoi":  // "mười" (10) vs "mươi" (×10): ×10 only after a lone digit
        current = (current > 0 && current < 10) ? current * 10 : 10
      case "tram":  // "trăm" (×100)
        current *= 100
      default:
        guard let n = numbers[w] else { return nil }
        current += Double(n)
      }
    }
    return current
  }

  /// "rưỡi" means a half: "hai kg rưỡi" → "2.5 kg", "bớt 2 kg rưỡi" → "bớt 2.5 kg".
  private static func applyHalf(_ s: String) -> String {
    var out: [String] = []
    for tok in s.split(separator: " ").map(String.init) {
      if tok == "ruoi" {
        if let idx = out.lastIndex(where: { Double($0) != nil }) {
          let v = (Double(out[idx]) ?? 0) + 0.5
          out[idx] = v == v.rounded() ? String(Int(v)) : String(v)
        }
      } else {
        out.append(tok)
      }
    }
    return out.joined(separator: " ")
  }

  // MARK: - Matching helpers

  private static func fullMatch(_ pattern: String, _ s: String) -> [String]? {
    guard let rx = try? NSRegularExpression(pattern: pattern) else { return nil }
    let ns = s as NSString
    guard let m = rx.firstMatch(in: s, options: [], range: NSRange(location: 0, length: ns.length)),
          m.range.location == 0, m.range.length == ns.length else { return nil }
    return (0..<m.numberOfRanges).map { i in
      let r = m.range(at: i)
      return r.location == NSNotFound ? "" : ns.substring(with: r)
    }
  }

  private static func number(_ s: String) -> Double {
    Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0
  }

  private static func isCommand(_ s: String, in phrases: [String]) -> Bool {
    folded(phrases).contains(s)
  }

  private static func kgValue(_ value: Double, unit: String, defaultLb: Bool, poundWords: [String]) -> Double {
    if poundWords.contains(unit) { return Plates.lbToKg(value) }
    if unit.isEmpty { return defaultLb ? Plates.lbToKg(value) : value }
    return value
  }

  // MARK: - Entry points (English-default wrappers keep existing callers working)

  public static func parse(_ transcript: String, candidates: [QuickLogCandidate], defaultLb: Bool) -> VoiceCommand {
    parse(transcript, candidates: candidates, defaultLb: defaultLb, language: .en)
  }

  public static func candidate(_ partial: String, candidates: [QuickLogCandidate], defaultLb: Bool) -> VoiceCandidate? {
    candidate(partial, candidates: candidates, defaultLb: defaultLb, language: .en)
  }

  public static func stripActivation(_ transcript: String, required: Bool) -> String? {
    stripActivation(transcript, required: required, language: .en)
  }

  public static let activationPhrases = VoicePhraseTable.english.activation

  public static func parse(_ transcript: String, candidates: [QuickLogCandidate], defaultLb: Bool, language: VoiceLanguage) -> VoiceCommand {
    let table = VoicePhraseTable.forLanguage(language)
    let original = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    let s = normalize(transcript, language: language)
    guard !s.isEmpty else { return .unrecognised(original) }

    // 1. askCoach wins.
    for phrase in folded(table.askCoach).sorted(by: { $0.count > $1.count }) {
      if s == phrase { return .askCoach("") }
      if s.hasPrefix(phrase + " ") {
        return .askCoach(String(original.dropFirst(phrase.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines))
      }
    }

    // 2. swapExercise.
    for verb in folded(table.swapVerbs) {
      let prefix = verb + " "
      if s.hasPrefix(prefix) {
        let name = String(s.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
        if !name.isEmpty, let ex = WorkoutImport.match(name) {
          return .swapExercise(exerciseID: ex.id)
        }
        break
      }
    }

    // 3. Set shape.
    if language == .en, let parsed = QuickLog.parse(s, candidates: candidates, defaultLb: defaultLb) {
      return .logSet(parsed)
    }
    if language == .vi, let parsed = parseVietnameseSet(s, table: table) {
      return .logSet(parsed)
    }

    // 3b. English set shape with the exercise implied ("eight reps at eighty kilos").
    if language == .en {
      if let m = fullMatch(#"^(\d+)(?:\s+reps?)?\s+at\s+(\d+(?:[.,]\d+)?)(?:\s+(kg|kilos|kilograms|lb|lbs|pounds))?$"#, s),
         let reps = Int(m[1]), reps >= 1 {
        let kg = kgValue(number(m[2]), unit: m[3], defaultLb: defaultLb, poundWords: ["lb", "lbs", "pounds"])
        return .logSet(QuickLogParse(exerciseID: "", weightKg: kg, reps: reps, rpe: nil))
      }
    }

    // 4. Short commands.
    if isCommand(s, in: table.completeSet) { return .completeSet }
    if isCommand(s, in: table.nextExercise) { return .nextExercise }
    if isCommand(s, in: table.skipRest) { return .skipRest }
    if isCommand(s, in: table.confirm) { return .confirm }
    if isCommand(s, in: table.cancel) { return .cancel }
    if isCommand(s, in: table.undo) { return .undo }

    // 5. Rest.
    if isCommand(s, in: table.startRest) { return .startRest(seconds: nil) }
    if let rest = numberedRest(s, table: table, language: language) { return rest }

    // 6. RPE.
    if let m = fullMatch(#"^rpe (\d+(?:[.,]\d+)?)$"#, s) { return .changeRPE(number(m[1])) }
    for phrase in folded(table.makeItWords) {
      let p = NSRegularExpression.escapedPattern(for: phrase) + " rpe"
      if let m = fullMatch("^\(p) (\\d+(?:[.,]\\d+)?)$", s) { return .changeRPE(number(m[1])) }
    }

    // 7. Reps.
    let repAlt = alternation(folded(table.repWords))
    for phrase in folded(table.makeItWords) {
      let p = NSRegularExpression.escapedPattern(for: phrase)
      if let m = fullMatch("^\(p) (\\d+) (\(repAlt))$", s) { return .changeReps(to: Int(m[1]), delta: nil) }
    }
    for word in folded(table.addWords) {
      let w = NSRegularExpression.escapedPattern(for: word)
      if let m = fullMatch("^\(w) (\\d+) (\(repAlt))$", s) { return .changeReps(to: nil, delta: Int(m[1])) }
    }
    if let m = fullMatch("^(\\d+) more (\(repAlt))$", s) { return .changeReps(to: nil, delta: Int(m[1])) }
    if let m = fullMatch("^(\\d+) (less|fewer) (\(repAlt))$", s) { return .changeReps(to: nil, delta: -Int(m[1])!) }
    if let m = fullMatch("^(\\d+) (\(repAlt))$", s) { return .changeReps(to: Int(m[1]), delta: nil) }

    // 8. Weight change.
    let poundWords = folded(table.poundWords)
    let unitAlt = alternation(folded(table.kiloWords) + poundWords)
    for word in folded(table.addWords) {
      let w = NSRegularExpression.escapedPattern(for: word)
      if let m = fullMatch("^\(w) (\\d+(?:[.,]\\d+)?)(?: (\(unitAlt)))?$", s) {
        return .changeWeight(deltaKg: kgValue(number(m[1]), unit: m[2], defaultLb: defaultLb, poundWords: poundWords))
      }
    }
    for word in folded(table.removeWords) {
      let w = NSRegularExpression.escapedPattern(for: word)
      if let m = fullMatch("^\(w) (\\d+(?:[.,]\\d+)?)(?: (\(unitAlt)))?$", s) {
        return .changeWeight(deltaKg: -kgValue(number(m[1]), unit: m[2], defaultLb: defaultLb, poundWords: poundWords))
      }
    }

    return .unrecognised(original)
  }

  // MARK: - Vietnamese set grammar

  /// "bench 80 ký 8 lần @ 8", "80 ký 8 lần", "8 lần 80 ký", with the exercise first or last.
  /// No exercise name → `.logSet` with an empty exerciseID, resolved to the active exercise by the caller.
  private static func parseVietnameseSet(_ s: String, table: VoicePhraseTable) -> QuickLogParse? {
    var tokens = s.split(separator: " ").map(String.init)
    guard tokens.count >= 4 else { return nil }

    var rpe: Double? = nil
    if let at = tokens.firstIndex(of: "@"), at + 1 < tokens.count, let v = Double(tokens[at + 1]) {
      rpe = v
      tokens = Array(tokens[..<at])
    } else if let rp = tokens.firstIndex(of: "rpe"), rp + 1 < tokens.count, let v = Double(tokens[rp + 1]) {
      rpe = v
      tokens = Array(tokens[..<rp])
    }

    let kilo = Set(folded(table.kiloWords))
    let rep = Set(folded(table.repWords))

    var weightIdx: Int? = nil
    var repsIdx: Int? = nil
    for i in 0..<(tokens.count - 1) {
      if weightIdx == nil, Double(tokens[i]) != nil, kilo.contains(tokens[i + 1]) {
        weightIdx = i
      }
      if repsIdx == nil, Int(tokens[i]) != nil, rep.contains(tokens[i + 1]) {
        repsIdx = i
      }
    }
    guard let wi = weightIdx, let ri = repsIdx,
          let weight = Double(tokens[wi]),
          let reps = Int(tokens[ri]), reps >= 1 else { return nil }

    var exerciseWords: [String] = []
    for i in tokens.indices where i != wi && i != wi + 1 && i != ri && i != ri + 1 {
      exerciseWords.append(tokens[i])
    }
    let name = exerciseWords.joined(separator: " ")
    let exerciseID: String
    if name.isEmpty {
      exerciseID = ""
    } else if let ex = WorkoutImport.match(name) {
      exerciseID = ex.id
    } else {
      return nil
    }

    return QuickLogParse(exerciseID: exerciseID, weightKg: weight, reps: reps, rpe: rpe)
  }

  // MARK: - Rest

  private static func numberedRest(_ s: String, table: VoicePhraseTable, language: VoiceLanguage) -> VoiceCommand? {
    let minuteAlt = alternation(folded(table.restMinuteWords))
    let secondAlt = alternation(folded(table.restSecondWords))
    let n = #"(\d+(?:[.,]\d+)?)"#
    if language == .en {
      if let m = fullMatch("^start \(n) (\(minuteAlt)) rest$", s) { return .startRest(seconds: Int((number(m[1]) * 60).rounded())) }
      if let m = fullMatch("^start \(n) (\(secondAlt)) rest$", s) { return .startRest(seconds: Int(number(m[1]).rounded())) }
      if let m = fullMatch("^rest \(n) (\(minuteAlt))$", s) { return .startRest(seconds: Int((number(m[1]) * 60).rounded())) }
      if let m = fullMatch("^rest \(n) (\(secondAlt))$", s) { return .startRest(seconds: Int(number(m[1]).rounded())) }
      if let m = fullMatch("^\(n) (\(minuteAlt)) rest$", s) { return .startRest(seconds: Int((number(m[1]) * 60).rounded())) }
      if let m = fullMatch("^\(n) (\(secondAlt)) rest$", s) { return .startRest(seconds: Int(number(m[1]).rounded())) }
    } else {
      // Vietnamese: "nghỉ 2 phút", "nghỉ 90 giây".
      if let m = fullMatch("^nghi \(n) (\(minuteAlt))$", s) { return .startRest(seconds: Int((number(m[1]) * 60).rounded())) }
      if let m = fullMatch("^nghi \(n) (\(secondAlt))$", s) { return .startRest(seconds: Int(number(m[1]).rounded())) }
    }
    return nil
  }

  // MARK: - Activation and partial reads

  public static func stripActivation(_ transcript: String, required: Bool, language: VoiceLanguage) -> String? {
    let table = VoicePhraseTable.forLanguage(language)
    let trimmed = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    let lower = fold(trimmed)
    for phrase in folded(table.activation).sorted(by: { $0.count > $1.count }) {
      if lower == phrase { return "" }
      if lower.hasPrefix(phrase + " ") {
        return String(trimmed.dropFirst(phrase.count + 1)).trimmingCharacters(in: .whitespacesAndNewlines)
      }
    }
    return required ? nil : trimmed
  }

  public static func candidate(_ partial: String, candidates: [QuickLogCandidate], defaultLb: Bool, language: VoiceLanguage) -> VoiceCandidate? {
    let table = VoicePhraseTable.forLanguage(language)
    let original = partial.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !original.isEmpty else { return nil }
    let s = normalize(partial, language: language)
    guard !s.isEmpty else { return nil }

    var isComplete = true
    if let last = s.split(separator: " ").last, folded(table.connectors).contains(String(last)) {
      isComplete = false
    }

    let command = parse(partial, candidates: candidates, defaultLb: defaultLb, language: language)
    if case .unrecognised = command { return nil }
    return VoiceCandidate(command: command, isComplete: isComplete)
  }
}
