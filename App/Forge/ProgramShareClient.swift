import ForgeCore
import Foundation

/// Network boundary for unlisted, revocable program sharing.
///
/// The client owns exactly the server contract for `POST /programs/share`,
/// `GET /programs/share/:code` and `DELETE /programs/share/:code`, and nothing
/// else. Three rules are structural, not advisory:
///
///   1. It publishes only an already-redacted `ShareableProgram`, mapped onto the
///      server's strict allowlist (`v`, `title`, `days[].name`,
///      `exercises[].name|sets|reps`). A payload that still carries a sensitive key
///      is refused locally, before any bytes leave the device.
///   2. No credential ever enters the payload. The session bearer travels in the
///      `Authorization` header, and the app secret in `x-forge-secret` — both are
///      read per request from the keychain, never copied into a body.
///   3. A fetched share becomes a *private, unactivated* `ImportedProgram` draft, so
///      the existing import preview and the explicit `ProgramActivationPolicy` path
///      are reused unchanged. Fetching never activates anything.
///
/// Auth, session and server-URL handling mirror `ForgeAPI`/`SocialClient` so the
/// unlisted-link flow cannot drift from the rest of the app.
enum ProgramShareClient {

  /// Mirrors the server allowlist, so an out-of-range program fails with a sentence
  /// instead of a bare 400.
  enum Limits {
    static let maxDays = 14
    static let maxExercisesPerDay = 30
    static let maxSets = 20
    static let maxName = 80
    static let maxReps = 24
    static let maxPayloadBytes = 16 * 1024
    static let defaultExpiryDays = 30
    static let allowedExpiryDays = 1...90
  }

  /// Public share schema version the app speaks.
  static let schemaVersion = 1

  /// A share the server has minted. `code` is the bearer secret and the import code.
  struct PublishedShare: Equatable {
    let code: String
    let url: URL
    let expiresAt: Date
    let schemaVersion: Int
  }

  /// A share the server has served. `program` is already mapped back into the app's
  /// `ShareableProgram`, with exercise names resolved to known exercise ids.
  struct FetchedShare: Equatable {
    let code: String
    let title: String
    let schemaVersion: Int
    let expiresAt: Date
    let program: ShareableProgram
  }

  enum Failure: LocalizedError, Equatable {
    case notConfigured
    case unauthorized
    case offline
    case invalidCode
    case notFound
    case gone(String)
    case oversized(Int)
    case rejected(String)
    case server(String)

    var errorDescription: String? {
      switch self {
      case .notConfigured:
        return "Sharing is not configured on this build."
      case .unauthorized:
        return "Sign in to publish an unlisted link."
      case .offline:
        return "Could not reach the server. Nothing was published and your copy is unchanged."
      case .invalidCode:
        return "That does not look like an import code or a Regulift link."
      case .notFound:
        return "No program was found for that code."
      case .gone(let message):
        return message
      case .oversized(let bytes):
        return "This program is \(bytes) bytes — larger than the server will publish (max \(Limits.maxPayloadBytes))."
      case .rejected(let message):
        return message
      case .server(let message):
        return message
      }
    }
  }

  // MARK: - Server access

  static var baseURL: String { ForgeAPI.baseURL }

  /// Whether the build can talk to the share endpoints at all.
  static var isConfigured: Bool { AppSecret.value != nil && URL(string: baseURL) != nil }

  private static func url(_ path: String) -> URL? {
    URL(string: baseURL)?.appending(path: path)
  }

  /// Shared transport. Returns the raw body so a caller can decode it, and maps every
  /// non-2xx into a `Failure` with the server's own error text where there is one.
  private static func send(
    _ method: String,
    _ path: String,
    body: [String: Any]? = nil,
    authorized: Bool,
    secret: Bool
  ) async throws -> Data {
    guard let url = url(path) else { throw Failure.notConfigured }
    var request = URLRequest(url: url)
    request.httpMethod = method
    request.timeoutInterval = 20
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "content-type")
      request.httpBody = try? JSONSerialization.data(withJSONObject: body)
    }
    if secret {
      guard let value = AppSecret.value else { throw Failure.notConfigured }
      request.setValue(value, forHTTPHeaderField: "x-forge-secret")
    }
    if authorized {
      guard let token = Keychain.get("forge-session") else { throw Failure.unauthorized }
      request.setValue("Bearer \(token)", forHTTPHeaderField: "authorization")
    }

    let data: Data
    let response: URLResponse
    do {
      (data, response) = try await URLSession.shared.data(for: request)
    } catch {
      throw Failure.offline
    }
    let status = (response as? HTTPURLResponse)?.statusCode ?? 0
    guard (200..<300).contains(status) else {
      let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
      throw mapError(status: status, object: object)
    }
    return data
  }

  private static func mapError(status: Int, object: [String: Any]) -> Failure {
    let message = (object["error"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
    switch status {
    case 400:
      let code = object["errorCode"] as? String
      return .rejected(reviewText(code, message))
    case 401:
      // Match `ForgeAPI.request`: a rejected bearer means the session is dead.
      Keychain.delete("forge-session")
      return .unauthorized
    case 403:
      return .rejected(message ?? "You do not own that share.")
    case 404:
      return .notFound
    case 410:
      return .gone(message ?? "This share is no longer available.")
    case 413:
      return .oversized(Limits.maxPayloadBytes)
    default:
      if status == 0 || status >= 500 { return .offline }
      return .server(message ?? "Server error (\(status))")
    }
  }

  /// Turns the server's machine error code into a sentence a lifter can act on.
  private static func reviewText(_ errorCode: String?, _ message: String?) -> String {
    switch errorCode {
    case "malformed":
      return "The server could not read this program."
    case "unknown_field":
      return "The program carried a field the server does not accept."
    case "sensitive_field":
      return "The program carried a field the server treats as personal data, so it was refused."
    case "unsupported_version":
      return "The server does not accept this share format version."
    case "oversized":
      return "The program is larger than the server will publish (max \(Limits.maxPayloadBytes) bytes)."
    case "out_of_bounds":
      return "A title, day, exercise or set count is outside the server's limits."
    default:
      return message ?? "The server refused this program."
    }
  }

  // MARK: - Publish

  /// Publishes an already-redacted program. `rightsConfirmed` must be true; the caller
  /// owns asking the lifter, this only refuses to send a half-answered request.
  static func publish(
    _ program: ShareableProgram,
    expiresInDays: Int = Limits.defaultExpiryDays,
    rightsConfirmed: Bool
  ) async throws -> PublishedShare {
    guard rightsConfirmed else {
      throw Failure.rejected("Confirm you have the rights to share this program before publishing.")
    }

    // The server's bounds, mirrored locally so a program it cannot accept fails with a
    // specific sentence instead of a generic 400 — and so the review screen and the wire
    // payload stay the same object rather than two renderings that can drift.
    let issues = violations(in: program)
    guard issues.isEmpty else {
      throw Failure.rejected("This copy cannot be published: " + issues.prefix(3).joined(separator: "; ") + ".")
    }

    let payload = payload(for: program)
    // The second boundary. `ProgramRedactor` ran first; this refuses to publish even if
    // something sensitive slipped through the mapping.
    let offending = ProgramImportDecoder.sensitiveKeys(in: payload)
    guard offending.isEmpty else {
      throw Failure.rejected("Refusing to publish: the payload still carried \(offending.joined(separator: ", ")).")
    }
    if let encoded = try? JSONSerialization.data(withJSONObject: payload), encoded.count > Limits.maxPayloadBytes {
      throw Failure.oversized(encoded.count)
    }

    let data = try await send(
      "POST", "programs/share",
      body: [
        "program": payload,
        "rightsConfirmed": true,
        "expiresInDays": clampExpiry(expiresInDays),
      ],
      authorized: true, secret: true)

    let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
    guard let code = object["code"] as? String,
      let urlString = object["url"] as? String,
      let url = URL(string: urlString),
      let expiresRaw = object["expiresAt"] as? String,
      let expiresAt = SocialDate.parse(expiresRaw)
    else {
      throw Failure.server("The server returned an unexpected share response.")
    }
    return PublishedShare(
      code: code, url: url, expiresAt: expiresAt,
      schemaVersion: object["schemaVersion"] as? Int ?? schemaVersion)
  }

  // MARK: - Fetch

  /// Public fetch of a share. No app secret and no session are required — an unlisted
  /// link is exactly that.
  static func fetch(codeOrLink raw: String) async throws -> FetchedShare {
    guard let code = importCode(from: raw) else { throw Failure.invalidCode }
    let data = try await send("GET", "programs/share/\(code)", authorized: false, secret: false)

    struct Envelope: Decodable {
      let program: ServerProgram
      let code: String
      let expiresAt: String
      let schemaVersion: Int
    }
    guard let envelope = try? JSONDecoder().decode(Envelope.self, from: data) else {
      throw Failure.server("The server returned an unreadable program.")
    }
    let expiresAt = SocialDate.parse(envelope.expiresAt) ?? .distantFuture
    let program = shareable(from: envelope.program)
    return FetchedShare(
      code: envelope.code,
      title: program.title,
      schemaVersion: envelope.schemaVersion,
      expiresAt: expiresAt,
      program: program)
  }

  // MARK: - Revoke

  /// Owner-only revoke. Idempotent on the server; a revoked share keeps its payload but
  /// stops being served.
  static func revoke(codeOrLink raw: String) async throws {
    guard let code = importCode(from: raw) else { throw Failure.invalidCode }
    _ = try await send("DELETE", "programs/share/\(code)", authorized: true, secret: true)
  }

  // MARK: - Allowlisted mapping (upload)

  /// The exact JSON the server accepts: keys are the whole allowlist, and nothing else.
  static func payload(for program: ShareableProgram) -> [String: Any] {
    let days = program.days.map { day -> [String: Any] in
      let exercises = day.exercises.map { entry -> [String: Any] in
        var exercise: [String: Any] = ["name": displayName(for: entry)]
        if entry.sets > 0 { exercise["sets"] = entry.sets }
        if let reps = repsLabel(entry) { exercise["reps"] = reps }
        return exercise
      }
      return ["name": day.name, "exercises": exercises]
    }
    return ["v": schemaVersion, "title": program.title, "days": days]
  }

  /// The name a recipient sees. The stored display name wins; the catalogue name is the
  /// fallback so a payload never ships an opaque id as a label.
  static func displayName(for entry: ProgramExerciseEntry) -> String {
    let stored = (entry.exerciseName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    if !stored.isEmpty { return stored }
    return ExerciseDB.find(entry.exerciseID)?.localizedName ?? entry.exerciseID
  }

  /// "8-12", or "10" for a fixed range. Nil when the entry carries no usable range, so
  /// the field is omitted rather than invented.
  static func repsLabel(_ entry: ProgramExerciseEntry) -> String? {
    guard entry.repRangeLower >= 1, entry.repRangeUpper >= entry.repRangeLower else { return nil }
    return entry.repRangeLower == entry.repRangeUpper
      ? "\(entry.repRangeLower)"
      : "\(entry.repRangeLower)-\(entry.repRangeUpper)"
  }

  static func clampExpiry(_ days: Int) -> Int {
    min(max(days, Limits.allowedExpiryDays.lowerBound), Limits.allowedExpiryDays.upperBound)
  }

  /// Local mirror of the server's bounds. Each entry names one specific problem, so a
  /// rejection is actionable rather than a bare 400.
  static func violations(in program: ShareableProgram) -> [String] {
    var issues: [String] = []
    if program.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      issues.append("the program needs a title")
    } else if program.title.count > Limits.maxName {
      issues.append("the title is longer than \(Limits.maxName) characters")
    }
    if program.days.isEmpty { issues.append("the program has no training days") }
    if program.days.count > Limits.maxDays {
      issues.append("\(program.days.count) days is more than the \(Limits.maxDays) the server accepts")
    }
    for day in program.days {
      if day.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        issues.append("a day has no name")
      } else if day.name.count > Limits.maxName {
        issues.append("“\(day.name.prefix(20))…” is longer than \(Limits.maxName) characters")
      }
      if day.exercises.isEmpty { issues.append("“\(day.name)” has no exercises") }
      if day.exercises.count > Limits.maxExercisesPerDay {
        issues.append("“\(day.name)” has more than \(Limits.maxExercisesPerDay) exercises")
      }
      for entry in day.exercises {
        let name = displayName(for: entry)
        if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
          issues.append("an exercise has no name")
        } else if name.count > Limits.maxName {
          issues.append("“\(name.prefix(20))…” is longer than \(Limits.maxName) characters")
        }
        if entry.sets < 1 { issues.append("\(name) has no sets") }
        if entry.sets > Limits.maxSets { issues.append("\(name) has more than \(Limits.maxSets) sets") }
        if let reps = repsLabel(entry), reps.count > Limits.maxReps {
          issues.append("\(name) has a rep range longer than \(Limits.maxReps) characters")
        }
      }
    }
    return issues
  }

  // MARK: - Allowlisted mapping (download)

  /// The only shape a share can hold, decoded. Unknown keys are not represented at all.
  struct ServerProgram: Decodable {
    let v: Int
    let title: String
    let days: [ServerDay]

    struct ServerDay: Decodable {
      let name: String
      let exercises: [ServerExercise]
    }

    struct ServerExercise: Decodable {
      let name: String
      let sets: Int?
      let reps: String?
    }
  }

  /// Server payload → the app's `ShareableProgram`. Exercise names are matched against
  /// the catalogue with `WorkoutImport.match`; an unmatched name stays as its own id so
  /// the import validator reports it honestly instead of guessing.
  static func shareable(from program: ServerProgram, at date: Date = .now) -> ShareableProgram {
    ShareableProgram(
      formatVersion: program.v,
      title: program.title,
      note: nil,
      createdAt: date,
      days: program.days.map { day in
        ProgramDay(
          name: day.name,
          exercises: day.exercises.map { exercise in
            let (lower, upper) = repRange(from: exercise.reps)
            return ProgramExerciseEntry(
              exerciseID: exerciseID(for: exercise.name),
              exerciseName: exercise.name,
              sets: exercise.sets ?? 1,
              repRangeLower: lower,
              repRangeUpper: upper,
              targetRPE: nil)
          })
      })
  }

  static func exerciseID(for name: String) -> String {
    WorkoutImport.match(name)?.id ?? name
  }

  /// Parses "8-12", "10" or "AMRAP" back into a validated rep range. A missing range
  /// becomes `1...1` — the model has no "unknown", and `1` is what the import validator
  /// accepts without pretending a prescription that was never sent.
  static func repRange(from raw: String?) -> (lower: Int, upper: Int) {
    guard let raw else { return (1, 1) }
    let numbers = raw.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.filter { $0 > 0 }
    switch numbers.count {
    case 0: return (1, 1)
    case 1: return (numbers[0], numbers[0])
    default: return (min(numbers[0], numbers[1]), max(numbers[0], numbers[1]))
    }
  }

  // MARK: - Draft

  /// Deterministic draft identity, so re-opening the same code replaces the draft rather
  /// than stacking duplicates in the library.
  static func draftID(for code: String) -> String { "share.\(code)" }

  /// The private, unactivated draft a fetched share becomes. `activeVersionNumber` is
  /// deliberately nil: opening a code can never make a program live.
  static func draft(from share: FetchedShare, at date: Date = .now) -> ImportedProgram {
    ImportedProgram(
      id: draftID(for: share.code),
      formatVersion: share.program.formatVersion,
      title: share.program.title,
      source: ProgramSource(kind: .share, name: nil, tokenID: share.code),
      importedAt: date,
      versions: [
        ProgramVersion(number: 1, createdAt: date, note: share.program.note, days: share.program.days)
      ],
      activeVersionNumber: nil)
  }

  // MARK: - Codes

  /// Accepts a bare 43-character code, a `/p/<code>` preview link or a
  /// `/programs/share/<code>` API link and returns the bearer code, or nil.
  static func importCode(from raw: String) -> String? {
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    let candidates: [String]
    if trimmed.contains("/") {
      candidates = trimmed
        .split(whereSeparator: { $0 == "/" || $0 == "?" || $0 == "#" })
        .map(String.init)
        .reversed()
    } else {
      candidates = [trimmed]
    }
    return candidates.first(where: isCode)
  }

  private static let codeCharacters = CharacterSet(
    charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-")

  /// 32 random bytes as base64url: exactly 43 characters of the URL-safe alphabet.
  static func isCode(_ candidate: String) -> Bool {
    candidate.count == 43 && candidate.unicodeScalars.allSatisfy { codeCharacters.contains($0) }
  }
}
