import Foundation
import WatchConnectivity
import HealthKit
import Observation

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

  @ObservationIgnored private let health = HKHealthStore()
  @ObservationIgnored private var workoutSession: HKWorkoutSession?
  @ObservationIgnored private var workoutBuilder: HKLiveWorkoutBuilder?

  private override init() {
    super.init()
    if WCSession.isSupported() {
      WCSession.default.delegate = self
      WCSession.default.activate()
    }
  }

  func log(_ set: WatchSet) {
    logged.append(set)
    let seconds = plan.first { $0.id == set.exerciseID }?.restSeconds ?? 120
    restEnd = Date.now.addingTimeInterval(TimeInterval(seconds))
    if let data = try? JSONEncoder().encode(set) {
      WCSession.default.transferUserInfo(["set": data])
    }
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

  func stopHR() {
    workoutSession?.end()
    workoutBuilder?.discardWorkout()
    workoutSession = nil
    workoutBuilder = nil
    heartRate = nil
    hrOn = false
  }

  private func applyPlan(_ data: Data) {
    guard let payload = try? JSONDecoder().decode(WatchPlanPayload.self, from: data) else { return }
    plan = payload.exercises
    dayName = payload.dayName
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
          let bpm = stats.averageQuantity() else { return }
    let value = bpm.doubleValue(for: HKUnit.count().unitDivided(by: .minute()))
    Task { @MainActor in self.heartRate = value }
  }

  nonisolated func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
