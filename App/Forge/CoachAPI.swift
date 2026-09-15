import Foundation
import ForgeCore

/// Network layer for the coach chat, extracted from CoachView so TodayView can ask questions too.
enum CoachAPI {
  struct Reply: Decodable {
    struct Action: Decodable {
      let type: String
      let from: String?
      let to: String?
    }
    let answer: String
    let refused: Bool?
    let citations: [String]?
    let action: Action?
  }

  enum Failure: Error {
    case notConfigured, unauthorized, warmingUp, limit(String), offline, server(String)
  }

  static func ask(question: String, context: String, coach: String, history: [[String: String]]) async throws -> Reply {
    let stored = UserDefaults.standard.string(forKey: "coachServerURL") ?? ""
    let base = stored == Theme.legacyCoachServer || stored.isEmpty ? Theme.coachServer : stored
    guard let url = URL(string: base)?.appending(path: "coach"),
          let secret = AppSecret.value else { throw Failure.notConfigured }
    let body: [String: Any] = [
      "question": question,
      "context": context,
      "coach": coach,
      "history": history]
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
          sets: sets.map { SetLog(weightKg: $0.weightKg, reps: $0.reps, rpe: $0.rpe) })
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
