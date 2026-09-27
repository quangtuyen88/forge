import Foundation
import ForgeCore

struct CrewSnapshot: Codable, Equatable {
  let week: String
  let weekStart: String
  var members: [CrewMember]
  let streakWeeks: Int
  var records: [CrewRecord]
  let lifts: [String: [CrewLiftLine]]

  var others: [CrewMember] { members.filter { !$0.isSelf } }
  var hasCrew: Bool { !others.isEmpty }
  var sessionsTogether: Int { members.reduce(0) { $0 + $1.done } }
  var plannedTogether: Int { members.reduce(0) { $0 + $1.target } }
  var toGo: Int { members.reduce(0) { $0 + max(0, $1.target - $1.sessions) } }

  func member(_ userId: String) -> CrewMember? { members.first { $0.userId == userId } }
  var recordsByOthers: [CrewRecord] { records.filter { !$0.isSelf } }
  func lines(for exerciseId: String) -> [CrewLiftLine] { lifts[exerciseId] ?? [] }
  var crewLiftIDs: Set<String> { Set(lifts.keys) }
}

struct CrewMember: Codable, Equatable, Identifiable {
  let userId: String
  let handle: String?
  let displayName: String?
  let isSelf: Bool
  var target: Int
  var days: [String]
  var sessions: Int
  var id: String { userId }

  var name: String { displayName ?? handle ?? "—" }
  var initial: String { String(name.prefix(1)).uppercased() }
  var done: Int { min(sessions, target) }
  var isComplete: Bool { sessions >= target }
}

struct CrewRecord: Codable, Equatable, Identifiable {
  let postId: String
  let userId: String
  let handle: String?
  let displayName: String?
  let isSelf: Bool
  let exerciseId: String?
  let exercise: String
  let e1rm: Double
  let weightKg: Double?
  let reps: Int?
  let date: String
  var kudos: Int
  var kudoed: Bool
  var id: String { postId }

  var exerciseName: String { exerciseId.flatMap { ExerciseDB.find($0) }?.localizedName ?? exercise }
}

struct CrewLiftLine: Codable, Equatable {
  let userId: String
  let deltas: [Double]
  let changeKg: Double
  let record: Bool
  let lastDate: String
}

enum CrewWeek {
  static let calendar: Calendar = {
    var cal = Calendar(identifier: .iso8601)
    cal.timeZone = .autoupdatingCurrent
    return cal
  }()

  private static let dayFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.calendar = calendar
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .autoupdatingCurrent
    formatter.dateFormat = "yyyy-MM-dd"
    return formatter
  }()

  static func key(for date: Date = .now) -> String {
    let comps = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    return String(format: "%04d-W%02d", comps.yearForWeekOfYear ?? 0, comps.weekOfYear ?? 0)
  }

  static func start(for date: Date = .now) -> Date {
    calendar.dateInterval(of: .weekOfYear, for: date)?.start ?? date
  }

  static func dayString(_ date: Date) -> String { dayFormatter.string(from: date) }

  static func date(from string: String) -> Date? { dayFormatter.date(from: string) }

  static func days(ofWeekStarting start: Date) -> [Date] {
    (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
  }
}

struct CrewSelfWeek: Equatable {
  let days: [String]
  let sessions: Int
  let target: Int

  static func make(sessions: [WorkoutSession], target: Int, now: Date = .now) -> CrewSelfWeek {
    let weekStart = CrewWeek.start(for: now)
    let weekEnd = CrewWeek.calendar.date(byAdding: .day, value: 7, to: weekStart) ?? .distantFuture
    // Date range first; `verified` walks every set, so it stays last.
    let counted = sessions.filter {
      $0.date >= weekStart && $0.date < weekEnd && !$0.tombstoned && $0.completed && $0.verified
    }
    return CrewSelfWeek(
      days: Set(counted.map { CrewWeek.dayString($0.date) }).sorted(),
      sessions: counted.count,
      target: max(1, min(7, target)))
  }
}

@MainActor @Observable final class CrewStore {
  static let shared = CrewStore()
  private init() {}

  private(set) var snapshot: CrewSnapshot?
  private(set) var loading = false
  private(set) var failed = false
  private var fetchedWeek: String?
  private var fetchedAt: Date?
  private var kudosInFlight: Set<String> = []

  var isFixture: Bool {
    #if DEBUG
    // `--seed-crew` from simctl, `seedCrew` from Maestro's launchApp arguments.
    ProcessInfo.processInfo.arguments.contains { $0.contains("seed-crew") || $0.contains("seedCrew") }
      || UserDefaults.standard.bool(forKey: "seedCrew")
    #else
    false
    #endif
  }

  func refresh(selfWeek: CrewSelfWeek?) async {
    #if DEBUG
    if isFixture {
      snapshot = CrewFixture.snapshot()
      failed = false
      return
    }
    #endif
    guard AuthClient.shared.token != nil else { snapshot = nil; return }
    let week = CrewWeek.key()
    if snapshot != nil, week == fetchedWeek, let fetchedAt, Date.now.timeIntervalSince(fetchedAt) < 60 {
      if let snapshot { self.snapshot = Self.applying(selfWeek, to: snapshot) }
      return
    }
    loading = true
    if let fresh = await SocialClient.shared.crew(week: week) {
      snapshot = Self.applying(selfWeek, to: fresh)
      failed = false
      fetchedWeek = week
      self.fetchedAt = .now
    } else {
      failed = true
    }
    loading = false
  }

  func toggleKudos(_ record: CrewRecord) async {
    guard !record.isSelf, !kudosInFlight.contains(record.postId), let snapshot,
      let index = snapshot.records.firstIndex(where: { $0.postId == record.postId })
    else { return }
    let turningOn = !snapshot.records[index].kudoed
    let savedKudos = snapshot.records[index].kudos
    let savedKudoed = snapshot.records[index].kudoed
    applyKudos(at: index, kudoed: turningOn, delta: turningOn ? 1 : -1)
    if isFixture { return }
    kudosInFlight.insert(record.postId)
    let ok = await SocialClient.shared.kudos(postID: record.postId, on: turningOn)
    kudosInFlight.remove(record.postId)
    if !ok, let current = self.snapshot?.records.firstIndex(where: { $0.postId == record.postId }) {
      restoreKudos(at: current, kudos: savedKudos, kudoed: savedKudoed)
    }
  }

  /// Forces the next refresh to fetch; the current snapshot stays on screen until then.
  func invalidate() {
    fetchedWeek = nil
    fetchedAt = nil
  }

  func reset() {
    snapshot = nil
    fetchedWeek = nil
    fetchedAt = nil
    kudosInFlight.removeAll()
    loading = false
    failed = false
  }

  private func applyKudos(at index: Int, kudoed: Bool, delta: Int) {
    snapshot?.records[index].kudoed = kudoed
    snapshot?.records[index].kudos += delta
  }

  private func restoreKudos(at index: Int, kudos: Int, kudoed: Bool) {
    snapshot?.records[index].kudos = kudos
    snapshot?.records[index].kudoed = kudoed
  }

  private static func applying(_ selfWeek: CrewSelfWeek?, to snapshot: CrewSnapshot) -> CrewSnapshot {
    guard let selfWeek, let index = snapshot.members.firstIndex(where: \.isSelf) else { return snapshot }
    var updated = snapshot
    updated.members[index].days = selfWeek.days
    updated.members[index].sessions = selfWeek.sessions
    updated.members[index].target = selfWeek.target
    return updated
  }
}

#if DEBUG
/// Debug-only crew mock (docs/design/crew-progress/): `--seed-crew` shows a full crew week
/// without a server. Compiled out of Release builds.
enum CrewFixture {
  static func snapshot(now: Date = .now) -> CrewSnapshot {
    let weekStart = CrewWeek.start(for: now)
    let days = CrewWeek.days(ofWeekStarting: weekStart).map(CrewWeek.dayString)
    func name(_ id: String) -> String { ExerciseDB.find(id)?.localizedName ?? id }
    func line(_ userId: String, _ deltas: [Double], record: Bool = false, lastDay: Int) -> CrewLiftLine {
      CrewLiftLine(userId: userId, deltas: deltas, changeKg: deltas.last ?? 0, record: record, lastDate: days[lastDay])
    }
    let members = [
      CrewMember(userId: "fixture-self", handle: "an_lifts", displayName: "An", isSelf: true, target: 4, days: [days[0], days[2], days[4], days[5]], sessions: 4),
      CrewMember(userId: "fixture-kenji", handle: "kenji", displayName: "Kenji", isSelf: false, target: 3, days: [days[1], days[4]], sessions: 2),
      CrewMember(userId: "fixture-linh", handle: "linh", displayName: "Linh", isSelf: false, target: 4, days: [days[0], days[1], days[3]], sessions: 3),
      CrewMember(userId: "fixture-mai", handle: "mai", displayName: "Mai", isSelf: false, target: 3, days: [days[0], days[2], days[4]], sessions: 3),
      CrewMember(userId: "fixture-sam", handle: "sam", displayName: "Sam", isSelf: false, target: 4, days: [days[1], days[3]], sessions: 2),
    ]
    let records = [
      CrewRecord(postId: "fx-1", userId: "fixture-self", handle: "an_lifts", displayName: "An", isSelf: true, exerciseId: "deadlift", exercise: name("deadlift"), e1rm: 176, weightKg: 160, reps: 3, date: days[5], kudos: 3, kudoed: false),
      CrewRecord(postId: "fx-2", userId: "fixture-kenji", handle: "kenji", displayName: "Kenji", isSelf: false, exerciseId: "back_squat", exercise: name("back_squat"), e1rm: 117, weightKg: 97.5, reps: 6, date: days[4], kudos: 0, kudoed: false),
      CrewRecord(postId: "fx-3", userId: "fixture-mai", handle: "mai", displayName: "Mai", isSelf: false, exerciseId: "barbell_bench", exercise: name("barbell_bench"), e1rm: 63.3, weightKg: 50, reps: 8, date: days[4], kudos: 2, kudoed: true),
      CrewRecord(postId: "fx-4", userId: "fixture-linh", handle: "linh", displayName: "Linh", isSelf: false, exerciseId: "deadlift", exercise: name("deadlift"), e1rm: 140, weightKg: 120, reps: 5, date: days[3], kudos: 1, kudoed: false),
    ]
    let lifts: [String: [CrewLiftLine]] = [
      "back_squat": [
        line("fixture-kenji", [0, 0, 1, 2, 1, 3, 3, 4, 5, 4, 5, 6], record: true, lastDay: 4),
        line("fixture-linh", [0, 1, 3, 4, 3, 6, 7, 8, 9, 12, 13, 12], lastDay: 3),
        line("fixture-mai", [0, 1, 1, 3, 4, 4, 5, 7, 6, 8, 9, 9], lastDay: 4),
        line("fixture-sam", [0, 1, -1, 0, 1, 0, -1, 1, 0, 0, 1, 0], lastDay: 3),
      ],
      "deadlift": [
        line("fixture-linh", [0, 2, 3, 5, 6, 6, 8, 9, 11, 12, 13, 15], record: true, lastDay: 3),
        line("fixture-sam", [0, 1, 2, 2, 3, 4, 4, 5, 5, 6, 7, 8], lastDay: 3),
        line("fixture-kenji", [0, 1, 1, 2, 3, 3, 4, 4, 5, 6, 6, 7], lastDay: 4),
      ],
      "hip_thrust": [
        line("fixture-mai", [0, 1, 2, 2, 3, 4, 4, 5, 6, 6, 7, 8], lastDay: 4),
        line("fixture-linh", [0, 0, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6], lastDay: 3),
      ],
      "barbell_bench": [
        line("fixture-mai", [0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5], record: true, lastDay: 4),
        line("fixture-kenji", [0, 1, 1, 2, 2, 3, 3, 3, 4, 4, 5, 5], lastDay: 4),
        line("fixture-sam", [0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4], lastDay: 3),
      ],
      "dips": [
        line("fixture-kenji", [0, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4, 4], lastDay: 4),
      ],
      "lateral_raise": [
        line("fixture-mai", [0, 0, 0, 1, 0, 1, 1, 1, 1, 2, 1, 2], lastDay: 4),
        line("fixture-linh", [0, 0, 1, 0, 1, 1, 1, 1, 2, 1, 2, 2], lastDay: 3),
      ],
      "overhead_press": [
        line("fixture-sam", [0, 1, 1, 2, 2, 3, 3, 3, 4, 4, 5, 5], lastDay: 3),
      ],
      "lat_pulldown": [
        line("fixture-linh", [0, 1, 2, 2, 3, 4, 4, 5, 5, 6, 6, 7], lastDay: 3),
        line("fixture-kenji", [0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 5], lastDay: 4),
      ],
      "bent_row": [
        line("fixture-mai", [0, 1, 1, 2, 3, 3, 4, 4, 5, 5, 6, 6], lastDay: 4),
      ],
    ]
    return CrewSnapshot(week: CrewWeek.key(for: now), weekStart: days[0], members: members, streakWeeks: 3, records: records, lifts: lifts)
  }
}
#endif
