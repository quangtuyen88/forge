import Foundation
import Observation

/// Flexible decoded JSON for post payloads (strings, numbers, nested objects).
enum JSONValue: Codable, Equatable {
  case string(String)
  case number(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case null

  var stringValue: String? { if case .string(let v) = self { return v } else { return nil } }
  var doubleValue: Double? { if case .number(let v) = self { return v } else { return nil } }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() { self = .null }
    else if let v = try? container.decode(Bool.self) { self = .bool(v) }
    else if let v = try? container.decode(Double.self) { self = .number(v) }
    else if let v = try? container.decode(String.self) { self = .string(v) }
    else if let v = try? container.decode([String: JSONValue].self) { self = .object(v) }
    else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value") }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let v): try container.encode(v)
    case .number(let v): try container.encode(v)
    case .bool(let v): try container.encode(v)
    case .object(let v): try container.encode(v)
    case .null: try container.encodeNil()
    }
  }

  /// Wrap any JSON-serializable dictionary value tree.
  static func from(any: Any) -> JSONValue? {
    guard let data = try? JSONSerialization.data(withJSONObject: ["v": any]),
          let dict = try? JSONDecoder().decode([String: JSONValue].self, from: data),
          let v = dict["v"] else { return nil }
    return v
  }
}

/// ISO 8601 with or without fractional seconds → Date.
enum SocialDate {
  private static let plain = ISO8601DateFormatter()
  private static let fractional: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
  }()

  static func parse(_ raw: String) -> Date? {
    plain.date(from: raw) ?? fractional.date(from: raw)
  }
}

enum SocialError: LocalizedError {
  case message(String)
  var errorDescription: String? {
    if case .message(let text) = self { return text }
    return nil
  }
}

struct CrewProfile: Codable, Identifiable, Equatable {
  let userId: String
  let handle: String
  let displayName: String
  let bio: String
  var id: String { userId }
}

struct CrewUser: Codable, Equatable {
  let id: String
  let handle: String?
  let displayName: String?
}

struct TopPR: Codable, Equatable {
  let exercise: String
  let e1rm: Double
}

struct CrewStats: Codable, Equatable {
  let sessions: Int
  let streakWeeks: Int
  let topPRs: [TopPR]
}

struct CrewUserDetail: Codable {
  let profile: CrewProfile
  let stats: CrewStats
  var following: Bool
}

extension CrewUserDetail: Identifiable {
  var id: String { profile.userId }
}

struct Post: Codable, Identifiable, Equatable {
  let id: String
  let user: CrewUser
  let type: String
  let payload: [String: JSONValue]?
  let createdAt: String
  var kudos: Int
  var kudoed: Bool
  var comments: Int

  var date: Date? { SocialDate.parse(createdAt) }

  func str(_ key: String) -> String? { payload?[key]?.stringValue }
  func num(_ key: String) -> Double? { payload?[key]?.doubleValue }
  var muscleLine: String? {
    guard case .object(let muscles)? = payload?["muscles"], !muscles.isEmpty else { return nil }
    return muscles.sorted { $0.value.doubleValue ?? 0 > $1.value.doubleValue ?? 0 }
      .compactMap { kv -> String? in kv.value.doubleValue.map { "\(kv.key) \(Int($0))" } }
      .prefix(4)
      .joined(separator: " · ")
  }
}

struct Comment: Codable, Identifiable, Equatable {
  let id: String
  let userId: String
  let text: String
  let createdAt: String

  var date: Date? { SocialDate.parse(createdAt) }
}

struct LeaderRow: Codable, Identifiable, Equatable {
  let userId: String
  let handle: String?
  let sessions: Int
  let tonnageKg: Double
  var id: String { userId }
}

struct FeedPage: Codable {
  let posts: [Post]
  let nextCursor: String?
}

private struct ProfileEnvelope: Codable { let profile: CrewProfile }
private struct OK: Codable { let ok: Bool }
private struct CommentsEnvelope: Codable { let comments: [Comment] }
private struct CommentEnvelope: Codable { let comment: Comment }
private struct PostEnvelope: Codable { let post: Post }

@MainActor @Observable final class SocialClient {
  static let shared = SocialClient()
  private init() {}

  private(set) var lastError: String?

  private func url(_ path: String, query: [String: String] = [:]) -> URL? {
    var comps = URLComponents(url: URL(string: ForgeAPI.baseURL)!.appending(path: path), resolvingAgainstBaseURL: false)
    if !query.isEmpty { comps?.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) } }
    return comps?.url
  }

  private func request(_ method: String, _ path: String, body: Data? = nil, query: [String: String] = [:]) async throws -> Data {
    guard let url = url(path, query: query) else { throw SocialError.message("Bad server URL") }
    var req = URLRequest(url: url)
    req.httpMethod = method
    req.timeoutInterval = 15
    if let body {
      req.setValue("application/json", forHTTPHeaderField: "content-type")
      req.httpBody = body
    }
    if let secret = AppSecret.value { req.setValue(secret, forHTTPHeaderField: "x-forge-secret") }
    if let token = AuthClient.shared.token { req.setValue("Bearer \(token)", forHTTPHeaderField: "authorization") }
    do {
      let (data, response) = try await URLSession.shared.data(for: req)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      guard (200..<300).contains(status) else {
        let message = ((try? JSONSerialization.jsonObject(with: data)) as? [String: Any])?["error"] as? String ?? "Server error (\(status))"
        if status == 401 {
          Keychain.delete("forge-session")
          throw SocialError.message("Session expired — sign in again")
        }
        throw SocialError.message(message)
      }
      return data
    } catch {
      if Self.isCancellation(error) || Task.isCancelled { throw error }
      if let social = error as? SocialError { throw social }
      throw SocialError.message(error.localizedDescription)
    }
  }

  /// Cancellation is "no result", not an error: callers make no state change for it.
  static func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
  }

  /// Never throws: decodes or sets lastError and returns nil.
  private func send<T: Decodable>(_ method: String, _ path: String, body: Data? = nil, query: [String: String] = [:], as type: T.Type) async -> T? {
    lastError = nil
    do {
      let data = try await request(method, path, body: body, query: query)
      guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
        lastError = "Unexpected server response"
        return nil
      }
      return decoded
    } catch let error as SocialError {
      lastError = error.errorDescription
      return nil
    } catch {
      if !Self.isCancellation(error) && !Task.isCancelled {
        lastError = error.localizedDescription
      }
      return nil
    }
  }

  private func sendThrowing<T: Decodable>(_ method: String, _ path: String, body: Data? = nil, query: [String: String] = [:], as type: T.Type) async throws -> T {
    lastError = nil
    let data = try await request(method, path, body: body, query: query)
    guard let decoded = try? JSONDecoder().decode(T.self, from: data) else {
      throw SocialError.message("Unexpected server response")
    }
    return decoded
  }

  func profile() async throws -> CrewProfile {
    try await sendThrowing("GET", "social/profile", as: ProfileEnvelope.self).profile
  }

  func updateProfile(handle: String, displayName: String, bio: String) async -> CrewProfile? {
    struct Body: Codable { let handle: String; let displayName: String; let bio: String }
    let body = try? JSONEncoder().encode(Body(handle: handle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(), displayName: displayName, bio: bio))
    return await send("PUT", "social/profile", body: body, as: ProfileEnvelope.self)?.profile
  }

  func user(handle: String) async throws -> CrewUserDetail {
    try await sendThrowing("GET", "social/users/\(handle.lowercased())", as: CrewUserDetail.self)
  }

  func follow(id: String) async -> Bool {
    await send("POST", "social/follow/\(id)", as: OK.self)?.ok ?? false
  }

  func unfollow(id: String) async -> Bool {
    await send("DELETE", "social/follow/\(id)", as: OK.self)?.ok ?? false
  }

  func feed(cursor: String? = nil) async throws -> FeedPage {
    var query: [String: String] = [:]
    if let cursor, !cursor.isEmpty { query["cursor"] = cursor }
    return try await sendThrowing("GET", "social/feed", query: query, as: FeedPage.self)
  }

  func post(type: String, payload: [String: Any]) async -> Post? {
    struct Body: Codable { let type: String; let payload: JSONValue }
    guard let value = JSONValue.from(any: payload) else { lastError = "Invalid post payload"; return nil }
    let body = try? JSONEncoder().encode(Body(type: type, payload: value))
    return await send("POST", "social/posts", body: body, as: PostEnvelope.self)?.post
  }

  func kudos(postID: String, on: Bool) async throws {
    _ = try await sendThrowing(on ? "POST" : "DELETE", "social/posts/\(postID)/kudos", as: OK.self)
  }

  func comments(postID: String) async throws -> [Comment] {
    try await sendThrowing("GET", "social/posts/\(postID)/comments", as: CommentsEnvelope.self).comments
  }

  func comment(postID: String, text: String) async throws -> Comment {
    struct Body: Codable { let text: String }
    let body = try? JSONEncoder().encode(Body(text: text))
    return try await sendThrowing("POST", "social/posts/\(postID)/comments", body: body, as: CommentEnvelope.self).comment
  }

  func leaderboard(week: String) async throws -> [LeaderRow] {
    try await sendThrowing("GET", "social/leaderboard", query: ["week": week], as: [LeaderRow].self)
  }
}

enum CrewBlocklist {
  static let key = "crewBlockedHandles"

  static func parse(_ raw: String) -> Set<String> {
    Set(
      raw.components(separatedBy: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        .filter { !$0.isEmpty })
  }

  static func contains(_ handle: String?, in raw: String) -> Bool {
    guard let handle, !handle.isEmpty else { return false }
    return parse(raw).contains(handle.lowercased())
  }

  static func adding(_ handle: String, to raw: String) -> String {
    var set = parse(raw)
    set.insert(handle.lowercased())
    return set.sorted().joined(separator: ",")
  }

  static func removing(_ handle: String, from raw: String) -> String {
    var set = parse(raw)
    set.remove(handle.lowercased())
    return set.sorted().joined(separator: ",")
  }
}
