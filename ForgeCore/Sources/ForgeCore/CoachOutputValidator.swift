import Foundation

public struct ValidationIssue: Sendable, Equatable {
  public enum Kind: String, Sendable {
    case promptLeak, internalTag, medicalDisclaimerMisuse, unsupportedAction,
         actionWithoutConfirmation, inventedNumber, wrongLanguage, unitMismatch
  }
  public let kind: Kind
  public let detail: String

  public init(kind: Kind, detail: String) {
    self.kind = kind
    self.detail = detail
  }
}

public enum CoachOutputValidator {
  private static let promptLeakMarkers = [
    "system prompt", "you are an ai", "as an ai", "as a language model", "your instructions",
    "instructions", "openai", "anthropic", "you are chatgpt", "large language model",
  ]
  private static let internalTagMarkers = ["<<<", ">>>", "action {", "action{", "scope:", "fatigue:", "{{{", "}}}", "<<data", "system:"]
  private static let medicalDisclaimerPhrases = [
    "consult a healthcare professional", "consult a doctor", "consult a physician",
    "medical professional", "healthcare professional", "see a doctor", "medical advice",
    "seek medical", "talk to a doctor", "not medical advice",
  ]

  public static func validate(answer: String, intent: CoachIntent, context: String,
                              language: String, usesLb: Bool) -> [ValidationIssue] {
    var issues: [ValidationIssue] = []
    let lower = answer.lowercased()

    // prompt leak / internal tag
    for marker in promptLeakMarkers where lower.contains(marker) {
      issues.append(ValidationIssue(kind: .promptLeak, detail: marker))
    }
    for marker in internalTagMarkers where lower.contains(marker) {
      issues.append(ValidationIssue(kind: .internalTag, detail: marker))
    }

    // medical disclaimer misuse
    let nonMedicalIntent: Bool
    switch intent {
    case .profileFactMissing, .trainingQuestion: nonMedicalIntent = true
    default: nonMedicalIntent = false
    }
    if nonMedicalIntent {
      for phrase in medicalDisclaimerPhrases where lower.contains(phrase) {
        issues.append(ValidationIssue(kind: .medicalDisclaimerMisuse, detail: phrase))
      }
    }

    // invented number
    let contextNumbers = numbers(context)
    for (value, unit) in numberUnitPairs(stripQuoted(answer)) {
      let rounded = Int((value * 10).rounded())
      let found = contextNumbers.contains { Int(($0 * 10).rounded()) == rounded }
      if !found {
        issues.append(ValidationIssue(kind: .inventedNumber, detail: "\(formatNum(value)) \(unit)"))
      }
    }

    // wrong language
    if language == "ja" {
      let hasJapanese = answer.unicodeScalars.contains { (0x3040...0x30FF).contains($0.value) || (0x4E00...0x9FFF).contains($0.value) }
      if !hasJapanese { issues.append(ValidationIssue(kind: .wrongLanguage, detail: "not Japanese")) }
    } else if language == "ko" {
      let hasHangul = answer.unicodeScalars.contains { (0xAC00...0xD7AF).contains($0.value) || (0x1100...0x11FF).contains($0.value) }
      if !hasHangul { issues.append(ValidationIssue(kind: .wrongLanguage, detail: "not Korean")) }
    } else if language == "en" {
      let letters = answer.filter { $0.isLetter }
      let ascii = letters.filter { $0.isASCII }
      if !letters.isEmpty && Double(ascii.count) / Double(letters.count) < 0.5 {
        issues.append(ValidationIssue(kind: .wrongLanguage, detail: "non-ASCII dominates"))
      }
    }

    // unit mismatch
    if usesLb {
      if hasUnit(lower, units: ["kg", "kgs", "kilograms"]) {
        issues.append(ValidationIssue(kind: .unitMismatch, detail: "kg used in lb system"))
      }
    } else {
      if hasUnit(lower, units: ["lb", "lbs", "pounds"]) {
        issues.append(ValidationIssue(kind: .unitMismatch, detail: "lb used in kg system"))
      }
    }

    return issues
  }

  /// True when the answer must be replaced rather than shown.
  public static func mustReplace(_ issues: [ValidationIssue]) -> Bool {
    issues.contains {
      $0.kind == .promptLeak || $0.kind == .internalTag
        || $0.kind == .medicalDisclaimerMisuse || $0.kind == .inventedNumber
    }
  }

  /// True when a reply says something was saved, changed or waits for confirmation; only valid when an action backs it.
  public static func claimsUnbackedChange(_ answer: String) -> Bool {
    let t = answer.replacingOccurrences(of: "’", with: "'").lowercased()
    let phrases = [
      "i'll remember", "i will remember", "i remember that", "remembering that", "i've noted", "i have noted",
      "i'll keep that in mind", "i'll keep it in mind", "i'll keep this in mind",
      "i'll adjust", "i will adjust", "i've adjusted", "i'll update", "i will update", "i've updated",
      "i'll change your", "i've changed", "i'll plan around", "i will plan around",
      "your plan is updated", "your plan has been updated", "your schedule is updated", "your schedule has been updated",
      "i've prepared", "i have prepared", "for your review",
    ]
    if phrases.contains(where: t.contains) { return true }
    // Bare "noted" at the start of a sentence, or a confirmation that points at a card below.
    let patterns = [#"(?:^|[.!?]\s+)noted(?:\s*[—-]|\.|,)"#, #"\b(?:confirm|tap|apply|approve|review)[^.!?]{0,40}\bbelow\b"#]
    return patterns.contains { pattern in
      let rx = try? NSRegularExpression(pattern: pattern)
      return rx?.firstMatch(in: t, range: NSRange(t.startIndex..., in: t)) != nil
    }
  }

  // MARK: helpers

  private static func stripQuoted(_ s: String) -> String {
    var out = s
    for pattern in [#""[^"]*""#, #"'[^']*'"#] {
      if let rx = try? NSRegularExpression(pattern: pattern) {
        out = rx.stringByReplacingMatches(in: out, range: NSRange(out.startIndex..., in: out), withTemplate: "")
      }
    }
    return out
  }

  private static func numberUnitPairs(_ s: String) -> [(Double, String)] {
    let pattern = #"(\d+(?:\.\d+)?)\s*(kg|kgs|kilograms|lb|lbs|pounds|%|reps|rep|sets|set)"#
    guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
    let ns = s as NSString
    var out: [(Double, String)] = []
    for m in rx.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length)) {
      let numR = m.range(at: 1), unitR = m.range(at: 2)
      guard numR.location != NSNotFound, unitR.location != NSNotFound else { continue }
      if let v = Double(ns.substring(with: numR)) {
        out.append((v, ns.substring(with: unitR).lowercased()))
      }
    }
    return out
  }

  private static func numbers(_ s: String) -> [Double] {
    let pattern = #"\d+(?:\.\d+)?"#
    guard let rx = try? NSRegularExpression(pattern: pattern) else { return [] }
    let ns = s as NSString
    return rx.matches(in: s, options: [], range: NSRange(location: 0, length: ns.length)).compactMap {
      $0.range.location != NSNotFound ? Double(ns.substring(with: $0.range)) : nil
    }
  }

  private static func hasUnit(_ s: String, units: [String]) -> Bool {
    let pattern = #"\d+(?:\.\d+)?\s*(?:"# + units.joined(separator: "|") + #")"#
    guard let rx = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return false }
    return rx.firstMatch(in: s, options: [], range: NSRange(location: 0, length: (s as NSString).length)) != nil
  }

  private static func formatNum(_ d: Double) -> String {
    d == d.rounded() ? String(Int(d)) : String(format: "%.1f", d)
  }
}
