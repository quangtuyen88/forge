import Foundation
import WatchConnectivity
import SwiftData
import ForgeCore

struct WatchPlanPayload: Codable {
  let dayName: String
  let exercises: [WatchExercise]
}

struct WatchExercise: Codable, Hashable {
  let id: String
  let name: String
  let sets: Int
  let repLow: Int
  let repHigh: Int
  let targetRPE: Double
  let suggestedKg: Double
  let restSeconds: Int
}

struct WatchSet: Codable {
  let exerciseID: String
  let setIndex: Int
  let weightKg: Double
  let reps: Int
  let rpe: Double
  let targetRPE: Double
  let date: Date
}

@MainActor final class WatchSync: NSObject, WCSessionDelegate {
  static let shared = WatchSync()

  private var container: ModelContainer?
  private var lastDayName = "Watch"

  private override init() { super.init() }

  func configure(container: ModelContainer) {
    self.container = container
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  func sendPlan(_ day: PlannedDay, suggested: (Exercise) -> Double, rest: (Exercise) -> Int, dayName: String) {
    lastDayName = dayName
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.isPaired && session.isWatchAppInstalled else { return }
    let payload = WatchPlanPayload(
      dayName: dayName,
      exercises: day.exercises.map { planned in
        WatchExercise(
          id: planned.exercise.id,
          name: planned.exercise.name,
          sets: planned.sets,
          repLow: planned.repRange.lowerBound,
          repHigh: planned.repRange.upperBound,
          targetRPE: planned.targetRPE,
          suggestedKg: suggested(planned.exercise),
          restSeconds: rest(planned.exercise))
      })
    guard let data = try? JSONEncoder().encode(payload) else { return }
    try? session.updateApplicationContext(["plan": data])
  }

  // MARK: WCSessionDelegate

  nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

  nonisolated func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    guard let data = userInfo["set"] as? Data,
          let set = try? JSONDecoder().decode(WatchSet.self, from: data) else { return }
    Task { @MainActor in self.insert(set) }
  }

  private func insert(_ set: WatchSet) {
    guard let container else { return }
    let context = ModelContext(container)
    let calendar = Calendar.current
    let dayStart = calendar.startOfDay(for: set.date)
    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
    let descriptor = FetchDescriptor<WorkoutSession>(
      predicate: #Predicate { $0.completed == false && $0.date >= dayStart && $0.date < dayEnd })
    let sessions = (try? context.fetch(descriptor)) ?? []
    let session = sessions.first ?? {
      let week = ((try? context.fetch(FetchDescriptor<UserProfile>()))?.first?.currentWeek) ?? 1
      let new = WorkoutSession(date: set.date, dayName: lastDayName, week: week, completed: false)
      context.insert(new)
      return new
    }()
    let logged = LoggedSet(
      exerciseID: set.exerciseID,
      setIndex: set.setIndex,
      weightKg: set.weightKg,
      reps: set.reps,
      rpe: set.rpe,
      targetRPE: set.targetRPE,
      loggedAt: set.date)
    context.insert(logged)
    session.sets.append(logged)
    try? context.save()
  }
}
