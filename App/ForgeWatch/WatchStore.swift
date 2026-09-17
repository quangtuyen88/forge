import Foundation
import WatchConnectivity
import HealthKit
import Observation
import ForgeCore

struct WatchExercise: Codable, Hashable, Identifiable {
  let id: String
  let name: String
  let sets: Int
  let repLow: Int
  let repHigh: Int
  let targetRPE: Double
  let suggestedKg: Double
  let restSeconds: Int
}

struct WatchSet: Codable, Hashable {
  let exerciseID: String
  let setIndex: Int
  let weightKg: Double
  let reps: Int
  let rpe: Double
  let targetRPE: Double
  let date: Date
}

struct WatchPlanPayload: Codable {
  let dayName: String
  let exercises: [WatchExercise]
}

@MainActor @Observable final class WatchStore: NSObject, WCSessionDelegate {
  static let shared = WatchStore()

  var plan: [WatchExercise] = []
  var dayName = ""
  var logged: [WatchSet] = []
  var heartRate: Double?
  var hrOn = false
  var restEnd: Date?
  var planDate: Date?
  var pending = 0
  var lastQuestion = ""
  var lastAnswer = ""
  var voicePending: VoiceCommand?
  var voiceTranscript = ""

  @ObservationIgnored private let health = HKHealthStore()
  @ObservationIgnored private var workoutSession: HKWorkoutSession?
  @ObservationIgnored private var workoutBuilder: HKLiveWorkoutBuilder?
  @ObservationIgnored private var lastHRSent = Date.distantPast

  private override init() {
    super.init()
    if let data = UserDefaults.standard.data(forKey: "forge.plan"),
       let payload = try? JSONDecoder().decode(WatchPlanPayload.self, from: data) {
      plan = payload.exercises
      dayName = payload.dayName
      planDate = UserDefaults.standard.object(forKey: "forge.planDate") as? Date
    }
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
#if DEBUG
    if ProcessInfo.processInfo.arguments.contains("--seed-demo") {
      dayName = "Full B"
      planDate = .now
      heartRate = 128
      plan = [
        WatchExercise(id: "deadlift", name: "Deadlift", sets: 4, repLow: 8, repHigh: 12, targetRPE: 8, suggestedKg: 132.5, restSeconds: 180),
        WatchExercise(id: "landmine_press", name: "Landmine Press", sets: 4, repLow: 8, repHigh: 12, targetRPE: 8, suggestedKg: 27.5, restSeconds: 120),
        WatchExercise(id: "barbell_curl", name: "Barbell Curl", sets: 3, repLow: 10, repHigh: 15, targetRPE: 8, suggestedKg: 25, restSeconds: 90),
        WatchExercise(id: "db_calf_raise", name: "Dumbbell Calf Raise", sets: 3, repLow: 12, repHigh: 20, targetRPE: 8, suggestedKg: 30, restSeconds: 60)
      ]
    }
#endif
  }

  func log(_ set: WatchSet) {
    logged.append(set)
    let seconds = plan.first { $0.id == set.exerciseID }?.restSeconds ?? 120
    restEnd = Date.now.addingTimeInterval(TimeInterval(seconds))
    if let data = try? JSONEncoder().encode(set) {
      WCSession.default.transferUserInfo(["set": data])
    }
    pending = WCSession.default.outstandingUserInfoTransfers.count
  }

  func startHR() {
    let config = HKWorkoutConfiguration()
    config.activityType = .traditionalStrengthTraining
    config.locationType = .indoor
    health.requestAuthorization(
      toShare: [HKObjectType.workoutType()],
      read: [HKQuantityType(.heartRate)]
    ) { _, _ in }
    do {
      let session = try HKWorkoutSession(healthStore: health, configuration: config)
      let builder = session.associatedWorkoutBuilder()
      builder.dataSource = HKLiveWorkoutDataSource(healthStore: health, workoutConfiguration: config)
      builder.delegate = self
      session.delegate = self
      session.startActivity(with: .now)
      workoutSession = session
      workoutBuilder = builder
      hrOn = true
    } catch {
      // ponytail: no error surface on watch; HR just stays off.
    }
  }

  func endWorkout() {
    hrOn = false
    heartRate = nil
    if WCSession.default.isReachable {
      WCSession.default.sendMessage(["hrEnded": true], replyHandler: nil)
    }
    let session = workoutSession
    let builder = workoutBuilder
    workoutSession = nil
    workoutBuilder = nil
    session?.end()
    builder?.endCollection(withEnd: .now) { _, _ in
      builder?.finishWorkout { _, _ in }
    }
  }

  private func applyPlan(_ data: Data) {
    guard let payload = try? JSONDecoder().decode(WatchPlanPayload.self, from: data) else { return }
    plan = payload.exercises
    dayName = payload.dayName
    planDate = .now
    UserDefaults.standard.set(data, forKey: "forge.plan")
    UserDefaults.standard.set(Date.now, forKey: "forge.planDate")
  }

  // MARK: WCSessionDelegate

  nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {
    if let data = session.receivedApplicationContext["plan"] as? Data {
      Task { @MainActor in self.applyPlan(data) }
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    if let data = message["plan"] as? Data {
      Task { @MainActor in self.applyPlan(data) }
    }
    if message["startWorkout"] != nil {
      Task { @MainActor in if !self.hrOn { self.startHR() } }
    }
    if message["endWorkout"] != nil {
      Task { @MainActor in self.endWorkout() }
    }
  }

  nonisolated func session(_ session: WCSession, didFinish userInfoTransfer: WCSessionUserInfoTransfer, error: Error?) {
    Task { @MainActor in self.pending = session.outstandingUserInfoTransfers.count }
  }

  nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
    if let data = applicationContext["plan"] as? Data {
      Task { @MainActor in self.applyPlan(data) }
    }
  }
}

extension WatchStore: HKWorkoutSessionDelegate {
  nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didChangeTo state: HKWorkoutSessionState, from oldState: HKWorkoutSessionState, date: Date) {}

  nonisolated func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {}
}

extension WatchStore: HKLiveWorkoutBuilderDelegate {
  nonisolated func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder, didCollectDataOf collectedTypes: Set<HKSampleType>) {
    guard let stats = workoutBuilder.statistics(for: HKQuantityType(.heartRate)),
          let bpm = stats.mostRecentQuantity() ?? stats.averageQuantity() else { return }
    let value = bpm.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    Task { @MainActor in
      self.heartRate = value
      let now = Date.now
      guard WCSession.default.isReachable,
            now.timeIntervalSince(self.lastHRSent) >= 5 else { return }
      self.lastHRSent = now
      WCSession.default.sendMessage(
        ["hr": Int(value.rounded()), "at": now.timeIntervalSince1970],
        replyHandler: nil)
    }
  }

  nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
