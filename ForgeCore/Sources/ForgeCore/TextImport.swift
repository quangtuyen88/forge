import Foundation

public enum TextImport {
  public struct Line: Sendable, Equatable {
    public let raw: String
    public let parsed: QuickLogParse?

    public init(raw: String, parsed: QuickLogParse?) {
      self.raw = raw
      self.parsed = parsed
    }
  }

  private static let prefixRegex = try? NSRegularExpression(pattern: #"^(\d{1,3})\s*[x×*]\s*(\d{1,3})\s+"#, options: [.caseInsensitive])

  public static func parse(_ text: String, candidates: [QuickLogCandidate], defaultLb: Bool) -> [Line] {
    var out: [Line] = []
    for rawLine in text.split(separator: "\n") {
      let raw = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
      guard !raw.isEmpty else { continue }
      guard raw.rangeOfCharacter(from: .decimalDigits) != nil else { continue }  // header

      if let rx = prefixRegex, let m = rx.firstMatch(in: raw, options: [], range: NSRange(location: 0, length: raw.utf16.count)),
         let setsR = Range(m.range(at: 1), in: raw), let repsR = Range(m.range(at: 2), in: raw),
         let setsCount = Int(raw[setsR]), let reps = Int(raw[repsR]),
         let end = Range(m.range(at: 0), in: raw) {
        let remainder = String(raw[end.upperBound...])
        if let p = QuickLog.parse("\(remainder) x \(reps)", candidates: candidates, defaultLb: defaultLb) {
          for _ in 0..<setsCount { out.append(Line(raw: raw, parsed: p)) }
        } else {
          out.append(Line(raw: raw, parsed: nil))
        }
        continue
      }

      out.append(Line(raw: raw, parsed: QuickLog.parse(raw, candidates: candidates, defaultLb: defaultLb)))
    }
    return out
  }

  public static func sets(from lines: [Line]) -> [QuickLogParse] {
    lines.compactMap(\.parsed)
  }
}
