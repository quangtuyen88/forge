import Foundation

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
  case unrecognised(String)

  /// True when acting on it changes the plan or the log, so the app must confirm first.
  public var needsConfirmation: Bool {
    switch self {
    case .logSet, .completeSet, .changeWeight, .changeReps, .changeRPE, .swapExercise: return true
    case .startRest, .skipRest, .nextExercise, .askCoach, .unrecognised: return false
    }
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
    case .unrecognised(let raw): return raw
    }
  }
}

public enum VoiceCommandParser {
  private static let wordNumbers: [String: Int] = [
    "zero": 0, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6, "seven": 7,
    "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "thirteen": 13, "fourteen": 14,
    "fifteen": 15, "sixteen": 16, "seventeen": 17, "eighteen": 18, "nineteen": 19, "twenty": 20,
    "thirty": 30, "forty": 40, "fifty": 50, "sixty": 60, "seventy": 70, "eighty": 80, "ninety": 90,
  ]
  private static let tensValues: Set<Int> = [20, 30, 40, 50, 60, 70, 80, 90]

  private static func convertWordNumbers(_ s: String) -> String {
    let tokens = s.split(separator: " ")
    var out: [String] = []
    var i = 0
    while i < tokens.count {
      let w = String(tokens[i])
      if let tens = wordNumbers[w], tensValues.contains(tens), i + 1 < tokens.count,
         let ones = wordNumbers[String(tokens[i + 1])], (1...9).contains(ones) {
        out.append(String(tens + ones))
        i += 2
      } else if let n = wordNumbers[w] {
        out.append(String(n))
        i += 1
      } else {
        out.append(w)
        i += 1
      }
    }
    return out.joined(separator: " ")
  }

  private static func normalize(_ raw: String) -> String {
    var s = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
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
    return convertWordNumbers(cleaned.split(separator: " ").joined(separator: " "))
  }

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

  public static func parse(_ transcript: String, candidates: [QuickLogCandidate], defaultLb: Bool) -> VoiceCommand {
    let original = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    let s = normalize(transcript)
    guard !s.isEmpty else { return .unrecognised(original) }

    // 1. askCoach wins.
    if s.hasPrefix("ask coach ") {
      return .askCoach(String(original.dropFirst("ask coach ".count)).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    if s == "ask coach" { return .askCoach("") }
    if s.hasPrefix("coach ") {
      return .askCoach(String(original.dropFirst("coach ".count)).trimmingCharacters(in: .whitespacesAndNewlines))
    }
    if s == "coach" { return .askCoach("") }

    // 2. swapExercise.
    for verb in ["swap", "change", "replace"] {
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
    if let parsed = QuickLog.parse(s, candidates: candidates, defaultLb: defaultLb) {
      return .logSet(parsed)
    }

    // 4. Short commands.
    if s == "complete set" || s == "done" || s == "log it" || s == "thats it" { return .completeSet }
    if s == "next exercise" || s == "move on" { return .nextExercise }
    if s == "skip rest" || s == "skip the timer" { return .skipRest }

    if s == "start rest" { return .startRest(seconds: nil) }
    if let m = fullMatch(#"^start (\d+(?:[.,]\d+)?) (minute|minutes|min|mins) rest$"#, s) {
      return .startRest(seconds: Int((number(m[1]) * 60).rounded()))
    }
    if let m = fullMatch(#"^start (\d+(?:[.,]\d+)?) (second|seconds|sec|secs) rest$"#, s) {
      return .startRest(seconds: Int(number(m[1]).rounded()))
    }
    if let m = fullMatch(#"^rest (\d+(?:[.,]\d+)?) (minute|minutes|min|mins)$"#, s) {
      return .startRest(seconds: Int((number(m[1]) * 60).rounded()))
    }
    if let m = fullMatch(#"^rest (\d+(?:[.,]\d+)?) (second|seconds|sec|secs)$"#, s) {
      return .startRest(seconds: Int(number(m[1]).rounded()))
    }
    if let m = fullMatch(#"^(\d+(?:[.,]\d+)?) (minute|minutes|min|mins) rest$"#, s) {
      return .startRest(seconds: Int((number(m[1]) * 60).rounded()))
    }
    if let m = fullMatch(#"^(\d+(?:[.,]\d+)?) (second|seconds|sec|secs) rest$"#, s) {
      return .startRest(seconds: Int(number(m[1]).rounded()))
    }

    if let m = fullMatch(#"^make it rpe (\d+(?:[.,]\d+)?)$"#, s) { return .changeRPE(number(m[1])) }
    if let m = fullMatch(#"^rpe (\d+(?:[.,]\d+)?)$"#, s) { return .changeRPE(number(m[1])) }

    if let m = fullMatch(#"^make it (\d+) reps?$"#, s) { return .changeReps(to: Int(m[1]), delta: nil) }
    if let m = fullMatch(#"^add (\d+) reps?$"#, s) { return .changeReps(to: nil, delta: Int(m[1])) }
    if let m = fullMatch(#"^(\d+) more reps?$"#, s) { return .changeReps(to: nil, delta: Int(m[1])) }
    if let m = fullMatch(#"^(\d+) (less|fewer) reps?$"#, s) { return .changeReps(to: nil, delta: -Int(m[1])!) }
    if let m = fullMatch(#"^(\d+) reps?$"#, s) { return .changeReps(to: Int(m[1]), delta: nil) }

    if let m = fullMatch(#"^(add|minus|take off|drop) (\d+(?:[.,]\d+)?)(?: (kg|kilos|kilograms|lb|lbs|pounds))?$"#, s) {
      let sign: Double = m[1] == "add" ? 1 : -1
      let value = number(m[2])
      let unit = m[3]
      let kg: Double
      if unit == "lb" || unit == "lbs" || unit == "pounds" {
        kg = Plates.lbToKg(value)
      } else if unit.isEmpty {
        kg = defaultLb ? Plates.lbToKg(value) : value
      } else {
        kg = value
      }
      return .changeWeight(deltaKg: sign * kg)
    }

    return .unrecognised(original)
  }
}
