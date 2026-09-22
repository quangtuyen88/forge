import Foundation
import ForgeCore

/// Network layer for the coach chat, extracted from CoachView so TodayView can ask questions too.
enum CoachAPI {
  struct Reply: Decodable {
    struct Action: Decodable {
      let type: String
      let from: String?
      let to: String?
      let note: String?
    }
    let answer: String
    let refused: Bool?
    let citations: [String]?
    let action: Action?
  }

  enum Failure: Error {
    case notConfigured, unauthorized, warmingUp, limit(String), offline, server(String)
  }

  /// What the app can honestly say about the coach server. "Connected" used to be printed
  /// whenever a secret was bundled, so a build with no reachable server still claimed a live
  /// coach. Reachability, configuration and authentication are three different answers.
  enum ServerStatus: Equatable {
    case notConfigured
    case checking
    case available
    case authenticationRequired
    case unavailable

    var label: String {
      switch self {
      case .notConfigured:
        return String(localized: "Not configured", bundle: L10n.bundle)
      case .checking:
        return String(localized: "Checking\u{2026}", bundle: L10n.bundle)
      case .available:
        return String(localized: "Available", bundle: L10n.bundle)
      case .authenticationRequired:
        return String(localized: "Sign-in required", bundle: L10n.bundle)
      case .unavailable:
        return String(localized: "Unavailable", bundle: L10n.bundle)
      }
    }
  }

  /// One unauthenticated GET /health against the configured base. Never claims more than the
  /// response supports, and never reports "available" from the presence of a key.
  static func probeServer() async -> ServerStatus {
    let stored = UserDefaults.standard.string(forKey: "coachServerURL") ?? ""
    let base = stored == Theme.legacyCoachServer || stored.isEmpty ? Theme.coachServer : stored
    guard let url = URL(string: base)?.appending(path: "health"), AppSecret.value != nil else {
      return .notConfigured
    }
    var req = URLRequest(url: url)
    req.httpMethod = "GET"
    req.timeoutInterval = 8
    do {
      let (_, response) = try await URLSession.shared.data(for: req)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      if status == 401 || status == 403 { return .authenticationRequired }
      return (200..<400).contains(status) ? .available : .unavailable
    } catch {
      return .unavailable
    }
  }

  static var languageCode: String { L10n.languageCode }

  static func ask(question: String, context: String, coach: String, history: [[String: String]], notes: [String] = []) async throws -> Reply {
    try await performAsk(question: question, context: context, decisions: nil, coach: coach, history: history, notes: notes)
  }

  static func ask(question: String, packet: CoachContextPacket, coach: String, history: [[String: String]], notes: [String] = []) async throws -> Reply {
    try await performAsk(question: question, context: packet.rendered(), decisions: DecisionLedger.payload(packet.decisions), coach: coach, history: history, notes: notes)
  }

  private static func performAsk(question: String, context: String, decisions: String?, coach: String, history: [[String: String]], notes: [String]) async throws -> Reply {
    let stored = UserDefaults.standard.string(forKey: "coachServerURL") ?? ""
    let base = stored == Theme.legacyCoachServer || stored.isEmpty ? Theme.coachServer : stored
    guard let url = URL(string: base)?.appending(path: "coach"),
          let secret = AppSecret.value else { throw Failure.notConfigured }
    var body: [String: Any] = [
      "question": question,
      "context": context,
      "coach": coach,
      "history": history,
      "notes": notes,
      "language": Self.languageCode]
    if let decisions { body["decisions"] = decisions }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    req.setValue(secret, forHTTPHeaderField: "x-forge-secret")
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    do {
      let (data, response) = try await URLSession.shared.data(for: req)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      if status == 401 { throw Failure.unauthorized }
      if let reply = try? JSONDecoder().decode(Reply.self, from: data) { return reply }
      if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
         let message = obj["error"] as? String {
        if message.contains("no model key") { throw Failure.warmingUp }
        if status >= 500 { throw Failure.offline }
        if status == 429 { throw Failure.limit(message) }
        throw Failure.server(message)
      }
      if status >= 500 || status == 0 { throw Failure.offline }
      throw Failure.server("\(status)")
    } catch let failure as Failure {
      throw failure
    } catch {
      #if DEBUG
      print("coach transport:", error.localizedDescription)
      #endif
      throw Failure.offline
    }
  }

  /// Builds the privacy-filtered coach context: app fields, Health-sourced fields
  /// (withheld by the builder), and coach notes, plus the decision ledger.
  static func contextPacket(
    profile: UserProfile?, sessions: [WorkoutSession], checkIns: [CheckIn],
    decisions: [DecisionRecord], bodyweightKg: Double?, usesLb: Bool, notes: [String],
    hrv: Double? = nil, restingHR: Double? = nil
  ) -> CoachContextPacket {
    var fields: [ContextField] = []
    let completed = sessions.filter(\.completed).sorted { $0.date < $1.date }
    let trusted = completed.flatMap(\.trustedSets)

    if let p = profile {
      fields.append(ContextField(key: "goal", value: Goal(rawValue: p.goal)?.name ?? p.goal, source: .app))
      fields.append(ContextField(key: "days_a_week", value: "\(p.daysPerWeek)", source: .app))
      fields.append(ContextField(key: "current_week", value: "\(p.currentWeek(sessions: sessions))", source: .app))
      fields.append(ContextField(key: "injuries", value: p.injuryFlags.isEmpty ? "none" : p.injuryFlags.joined(separator: ", "), source: .app))
    }
    if let bw = bodyweightKg {
      fields.append(ContextField(key: "bodyweight_kg", value: Fmt.num(bw), source: .app))
    }

    let cal = Calendar.current
    let thisWeekInterval = cal.dateInterval(of: .weekOfYear, for: .now)
    let thisWeekSessions = completed.filter { thisWeekInterval?.contains($0.date) ?? false }
    let lastWeekSessions = completed.filter { s in
      guard let interval = thisWeekInterval,
            let start = cal.date(byAdding: .weekOfYear, value: -1, to: interval.start) else { return false }
      return s.date >= start && s.date < interval.start
    }
    func summarize(_ list: [WorkoutSession]) -> (sessions: Int, sets: Int, tonnage: Double) {
      let sets = list.flatMap(\.trustedSets)
      let tonnage = sets.reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
      return (list.count, sets.count, tonnage)
    }
    let tw = summarize(thisWeekSessions)
    let lw = summarize(lastWeekSessions)
    fields.append(ContextField(key: "this_week", value: "\(tw.sessions) sessions, \(tw.sets) sets, \(Int(tw.tonnage)) kg", source: .app))
    fields.append(ContextField(key: "last_week", value: "\(lw.sessions) sessions, \(lw.sets) sets, \(Int(lw.tonnage)) kg", source: .app))

    var bestByLift: [String: Double] = [:]
    for set in trusted {
      let e = Strength.epley(weightKg: set.weightKg, reps: set.reps)
      if e > bestByLift[set.exerciseID] ?? 0 { bestByLift[set.exerciseID] = e }
    }
    if !bestByLift.isEmpty {
      let lines = bestByLift.sorted { $0.key < $1.key }
        .map { "\(ExerciseDB.find($0.key)?.name ?? $0.key) \(Fmt.num($0.value)) e1RM" }
      fields.append(ContextField(key: "per_lift_bests", value: lines.joined(separator: "; "), source: .app))
    }

    let lastByLift = Dictionary(grouping: trusted, by: \.exerciseID)
      .compactMapValues { $0.max { $0.loggedAt < $1.loggedAt } }
    if !lastByLift.isEmpty {
      let lines = lastByLift.sorted { $0.key < $1.key }.compactMap { id, set -> String? in
        guard let ex = ExerciseDB.find(id) else { return nil }
        let w = usesLb ? Plates.kgToLb(set.weightKg) : set.weightKg
        // The coach must not be told a plan target is a reported RPE; an unrated set says so.
        let base = "\(ex.name) \(Fmt.num(w)) \(usesLb ? "lb" : "kg") × \(set.reps)"
        guard set.effortReported else { return base + " (effort not recorded)" }
        return base + " @ \(Fmt.num(set.rpe))"
      }
      fields.append(ContextField(key: "last_sets", value: lines.joined(separator: "; "), source: .app))
    }

    let delta = volumeDelta(profile: profile, sessions: sessions, checkIns: checkIns)
    if !delta.isEmpty {
      let entries = delta.sorted { $0.key.rawValue < $1.key.rawValue }
        .map { "\($0.key.rawValue) \($0.value > 0 ? "+" : "−")1 set" }
      fields.append(ContextField(key: "volume_autoregulation", value: entries.joined(separator: ", "), source: .app))
    }

    let plateaued = plateauedExerciseIDs(sessions: sessions).sorted().compactMap { ExerciseDB.find($0)?.name }
    if !plateaued.isEmpty {
      fields.append(ContextField(key: "plateaued_lifts", value: plateaued.joined(separator: ", "), source: .app))
    }

    if let sleepHours = checkIns.last?.sleepHours {
      fields.append(ContextField(key: "sleep_hours", value: Fmt.num(sleepHours), source: .healthKit))
    }
    if let hrv {
      fields.append(ContextField(key: "hrv_ms", value: Fmt.num(hrv), source: .healthKit))
    }
    if let restingHR {
      fields.append(ContextField(key: "resting_hr", value: Fmt.num(restingHR), source: .healthKit))
    }
    if !notes.isEmpty {
      fields.append(ContextField(key: "coach_notes", value: notes.joined(separator: "; "), source: .user))
    }

    return CoachContextBuilder.packet(fields: fields, decisions: decisions)
  }

  /// Sends a recorded audio clip to `/transcribe` and returns the transcript.
  static func transcribe(audio: Data, mimeType: String, language: String?, prompt: [String]) async throws -> String {
    let stored = UserDefaults.standard.string(forKey: "coachServerURL") ?? ""
    let base = stored == Theme.legacyCoachServer || stored.isEmpty ? Theme.coachServer : stored
    guard let baseURL = URL(string: base)?.appending(path: "transcribe"),
          let secret = AppSecret.value else { throw Failure.notConfigured }
    var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
    var query: [URLQueryItem] = []
    if let language, !language.isEmpty { query.append(URLQueryItem(name: "language", value: language)) }
    if !prompt.isEmpty { query.append(URLQueryItem(name: "prompt", value: prompt.joined(separator: ","))) }
    if !query.isEmpty { components?.queryItems = query }
    guard let url = components?.url else { throw Failure.notConfigured }
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue(mimeType, forHTTPHeaderField: "content-type")
    req.setValue(secret, forHTTPHeaderField: "x-forge-secret")
    req.httpBody = audio
    req.timeoutInterval = 20
    do {
      let (data, response) = try await URLSession.shared.data(for: req)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      if status == 401 { throw Failure.unauthorized }
      if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let text = obj["text"] as? String { return text }
        if let message = obj["error"] as? String {
          if status >= 500 { throw Failure.offline }
          if status == 429 { throw Failure.limit(message) }
          throw Failure.server(message)
        }
      }
      if status >= 500 || status == 0 { throw Failure.offline }
      throw Failure.server("\(status)")
    } catch let failure as Failure {
      throw failure
    } catch {
      #if DEBUG
      print("transcribe transport:", error.localizedDescription)
      #endif
      throw Failure.offline
    }
  }

  /// Weekly review in the coach's voice. POSTs `{ headline, lines, coach, language }`
  /// to `/review` (same auth as the chat) and returns the `text` field.
  static func review(headline: String, lines: [String], coach: String) async throws -> String {
    let stored = UserDefaults.standard.string(forKey: "coachServerURL") ?? ""
    let base = stored == Theme.legacyCoachServer || stored.isEmpty ? Theme.coachServer : stored
    guard let url = URL(string: base)?.appending(path: "review"),
          let secret = AppSecret.value else { throw Failure.notConfigured }
    let body: [String: Any] = [
      "headline": headline,
      "lines": lines,
      "coach": coach,
      "language": Self.languageCode]
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    req.setValue(secret, forHTTPHeaderField: "x-forge-secret")
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    do {
      let (data, response) = try await URLSession.shared.data(for: req)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      if status == 401 { throw Failure.unauthorized }
      if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
        if let text = obj["text"] as? String { return text }
        if let message = obj["error"] as? String {
          if status >= 500 { throw Failure.offline }
          if status == 429 { throw Failure.limit(message) }
          throw Failure.server(message)
        }
      }
      if status >= 500 || status == 0 { throw Failure.offline }
      throw Failure.server("\(status)")
    } catch let failure as Failure {
      throw failure
    } catch {
      #if DEBUG
      print("review transport:", error.localizedDescription)
      #endif
      throw Failure.offline
    }
  }

  static func dataBlock(profile: UserProfile?, sessions: [WorkoutSession], checkIns: [CheckIn], usesLb: Bool) -> String {
    var head: [String] = []
    if let p = profile {
      head.append("Profile: goal \(p.goal), \(p.daysPerWeek) days/week, week \(p.currentWeek(sessions: sessions)) of 6, injuries: \(p.injuryFlags.isEmpty ? "none" : p.injuryFlags.joined(separator: ", ")).")
    }
    let delta = volumeDelta(profile: profile, sessions: sessions, checkIns: checkIns)
    if !delta.isEmpty {
      let entries = delta
        .sorted { $0.key.rawValue < $1.key.rawValue }
        .map { "\($0.key.rawValue) \($0.value > 0 ? "+" : "−")1 set" }
        .joined(separator: ", ")
      head.append("Volume auto-regulation this week: " + entries + ".")
    }
    let plateauedNames = plateauedExerciseIDs(sessions: sessions)
      .sorted()
      .compactMap { ExerciseDB.find($0)?.name }
    if !plateauedNames.isEmpty {
      head.append("Plateaued lifts: \(plateauedNames.joined(separator: ", ")).")
    }
    if let line = exerciseIDLine(profile: profile, sessions: sessions, volumeDelta: delta) {
      head.append(line)
    }
    var history = sessionLines(sessions: sessions, usesLb: usesLb)
    let tail = bestLines(sessions: sessions)
    func joined() -> String { (head + history + tail).joined(separator: "\n") }
    var out = joined()
    while out.count > 3000, !history.isEmpty {
      history.removeFirst()
      out = joined()
    }
    return out
  }

  private static func previousMicrocycle(profile: UserProfile?, sessions: [WorkoutSession]) -> [WorkoutSession] {
    guard let profile else { return [] }
    let days = max(profile.daysPerWeek, 1)
    let done = sessions.filter { $0.completed && $0.date >= profile.mesoStart }.sorted { $0.date < $1.date }
    let index = done.count / days
    guard index >= 1 else { return [] }
    return Array(done[((index - 1) * days)..<min(index * days, done.count)])
  }

  private static func volumeDelta(profile: UserProfile?, sessions: [WorkoutSession], checkIns: [CheckIn]) -> [Muscle: Int] {
    guard let profile else { return [:] }
    let goal = Goal(rawValue: profile.goal) ?? .hypertrophy
    let performances: [ExercisePerformance] = Dictionary(grouping: previousMicrocycle(profile: profile, sessions: sessions).flatMap(\.sets), by: \.exerciseID)
      .compactMap { id, sets in
        guard let exercise = ExerciseDB.find(id), let first = sets.first else { return nil }
        return ExercisePerformance(
          exercise: exercise,
          repRange: Program.repRange(exercise, goal: goal),
          targetRPE: first.targetRPE,
          sets: sets.map {
        SetLog(weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe, effortReported: $0.effortReported)
      })
      }
    let soreness = checkIns.last(where: { Calendar.current.isDateInToday($0.date) })?.soreness
    return Autoregulation.volumeDelta(performances, soreness: soreness)
  }

  /// `Exercise ids: name=id, …` for the current plan and the last 3 completed sessions,
  /// so the coach can emit valid ACTION swap ids.
  private static func exerciseIDLine(profile: UserProfile?, sessions: [WorkoutSession], volumeDelta: [Muscle: Int]) -> String? {
    guard let profile else { return nil }
    var entries = Set<String>()
    let days = Program.week(
      profile.currentWeek(sessions: sessions),
      profile: profile.profileInput(plateaued: plateauedExerciseIDs(sessions: sessions)),
      volumeDelta: volumeDelta)
    for day in days {
      for planned in day.exercises {
        entries.insert("\(planned.exercise.name)=\(planned.exercise.id)")
      }
    }
    let recent = sessions.filter(\.completed).sorted { $0.date < $1.date }.suffix(3)
    for session in recent {
      for id in Set(session.sets.map(\.exerciseID)) {
        if let ex = ExerciseDB.find(id) {
          entries.insert("\(ex.name)=\(id)")
        }
      }
    }
    return entries.isEmpty ? nil : "Exercise ids: " + entries.sorted().joined(separator: ", ") + "."
  }

  private static func sessionLines(sessions: [WorkoutSession], usesLb: Bool) -> [String] {
    let cutoff = Date.now.addingTimeInterval(-28 * 86400)
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    return sessions
      .filter { $0.completed && $0.date > cutoff }
      .sorted { $0.date < $1.date }
      .map { s in
        let parts = Dictionary(grouping: s.sets, by: \.exerciseID).compactMap { id, sets -> String? in
          guard let ex = ExerciseDB.find(id),
                let best = sets.max(by: { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) < Strength.epley(weightKg: $1.weightKg, reps: $1.reps) }) else { return nil }
          let w = usesLb ? Plates.kgToLb(best.weightKg) : best.weightKg
          return String(format: "%@ %.1f×%d @%.1f (e1RM %.0f)", ex.name, w, best.reps, best.rpe, Strength.epley(weightKg: best.weightKg, reps: best.reps))
        }.sorted()
        return "\(df.string(from: s.date)) \(s.dayName): " + parts.joined(separator: "; ")
      }
  }

  private static func bestLines(sessions: [WorkoutSession]) -> [String] {
    var bests: [String: Double] = [:]
    for s in sessions.filter(\.completed) {
      for set in s.sets {
        let e = Strength.epley(weightKg: set.weightKg, reps: set.reps)
        if e > bests[set.exerciseID] ?? 0 { bests[set.exerciseID] = e }
      }
    }
    return bests
      .sorted { $0.key < $1.key }
      .map { String(format: "Best %@: %.0f e1RM", ExerciseDB.find($0.key)?.name ?? $0.key, $0.value) }
  }
}
