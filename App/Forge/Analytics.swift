import Foundation

/// Event buffering + batch upload to the coach server's /events endpoint.
enum Analytics {
  private struct Event: Codable {
    let name: String
    let ts: Double
    let props: [String: String]?
  }

  private struct Payload: Codable {
    let device: String
    let events: [Event]
  }

  private static let lock = NSLock()
  private static let bufferKey = "forge.analytics.buffer"
  private static let deviceKey = "forge.device"
  private static let maxBuffered = 200
  private static let flushThreshold = 10
  private static let maxAttempts = 3

  static var deviceID: String {
    let defaults = UserDefaults.standard
    if let id = defaults.string(forKey: deviceKey) { return id }
    let id = UUID().uuidString
    defaults.set(id, forKey: deviceKey)
    return id
  }

  private static var buffer: [Event] =
    (UserDefaults.standard.data(forKey: bufferKey)).flatMap { try? JSONDecoder().decode([Event].self, from: $0) } ?? []

  private static func persist() {
    UserDefaults.standard.set((try? JSONEncoder().encode(buffer)) ?? Data(), forKey: bufferKey)
  }

  /// Sync wrapper keeps NSLock out of async lexical context (Swift 6 error otherwise).
  private static func withLock<T>(_ body: () -> T) -> T {
    lock.lock()
    defer { lock.unlock() }
    return body()
  }

  /// Same base-URL resolution as the coach chat (legacy localhost falls back to prod).
  private static var baseURL: String {
    let stored = UserDefaults.standard.string(forKey: "coachServerURL") ?? ""
    return stored == Theme.legacyCoachServer || stored.isEmpty ? Theme.coachServer : stored
  }

  static func track(_ name: String, _ props: [String: String] = [:]) {
    let shouldFlush = withLock { () -> Bool in
      buffer.append(Event(name: name, ts: Date.now.timeIntervalSince1970, props: props.isEmpty ? nil : props))
      if buffer.count > maxBuffered { buffer.removeFirst(buffer.count - maxBuffered) }
      persist()
      return buffer.count >= flushThreshold
    }
    if shouldFlush { Task { await flush() } }
  }

  static func flush() async {
    guard let secret = AppSecret.value,
          let url = URL(string: baseURL)?.appending(path: "events") else { return }
    for _ in 0..<maxAttempts {
      let batch = withLock { buffer }
      guard !batch.isEmpty else { return }
      var req = URLRequest(url: url)
      req.httpMethod = "POST"
      req.timeoutInterval = 10
      req.setValue("application/json", forHTTPHeaderField: "content-type")
      req.setValue(secret, forHTTPHeaderField: "x-forge-secret")
      req.httpBody = try? JSONEncoder().encode(Payload(device: deviceID, events: batch))
      do {
        let (_, response) = try await URLSession.shared.data(for: req)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        withLock {
          buffer.removeFirst(min(batch.count, buffer.count))
          persist()
        }
        return
      } catch {
        continue
      }
    }
    // ponytail: drop the whole batch after 3 failed attempts; events arriving mid-flush go with it
    withLock {
      buffer.removeAll()
      persist()
    }
  }
}
