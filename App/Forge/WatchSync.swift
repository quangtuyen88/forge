import Foundation
import Observation
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
  let suggestedKg: Double?
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

@MainActor @Observable final class WatchSync: NSObject, WCSessionDelegate {
  static let shared = WatchSync()

  var heartRate: Int?

  private var container: ModelContainer?
  private var lastDayName = "Watch"
  private var lastPlanData: Data?
  @ObservationIgnored private var lastHRAt: Date?
  @ObservationIgnored private var stalenessTask: Task<Void, Never>?

  private override init() { super.init() }

  func startWatchWorkout(dayName: String) {
    guard WCSession.isSupported(), WCSession.default.isReachable else {
      // ponytail: no-op when unreachable — watch app must be open; workout-mirroring API can replace this later.
      return
    }
    WCSession.default.sendMessage(["startWorkout": dayName], replyHandler: nil)
  }

  func endWatchWorkout() {
    heartRate = nil
    lastHRAt = nil
    guard WCSession.isSupported(), WCSession.default.isReachable else { return }
    WCSession.default.sendMessage(["endWorkout": true], replyHandler: nil)
  }

  private func startStalenessLoop() {
    guard stalenessTask == nil else { return }
    stalenessTask = Task { [weak self] in
      defer { self?.stalenessTask = nil }
      guard let self else { return }
      while !Task.isCancelled, self.lastHRAt != nil {
        try? await Task.sleep(for: .seconds(5))
        guard let at = self.lastHRAt else { break }
        if Date.now.timeIntervalSince(at) > 20 {
          self.heartRate = nil
          self.lastHRAt = nil
          break
        }
      }
    }
  }

  func configure(container: ModelContainer) {
    self.container = container
    guard WCSession.isSupported() else { return }
    WCSession.default.delegate = self
    WCSession.default.activate()
  }

  func sendPlan(_ day: PlannedDay, suggested: (Exercise) -> Double?, rest: (Exercise) -> Int, dayName: String) {
    lastDayName = dayName
    guard WCSession.isSupported() else { return }
    let session = WCSession.default
    guard session.isPaired && session.isWatchAppInstalled else { return }
    let payload = WatchPlanPayload(
      dayName: localizedDayName(dayName),
      exercises: day.exercises.map { planned in
        WatchExercise(
          id: planned.exercise.id,
          name: planned.exercise.localizedName,
          sets: planned.sets,
          repLow: planned.repRange.lowerBound,
          repHigh: planned.repRange.upperBound,
          targetRPE: planned.targetRPE,
          suggestedKg: suggested(planned.exercise),
          restSeconds: rest(planned.exercise))
      })
    guard let data = try? JSONEncoder().encode(payload) else { return }
    lastPlanData = data
    try? session.updateApplicationContext(["plan": data])
  }

  // MARK: WCSessionDelegate

  nonisolated func session(_ session: WCSession, activationDidCompleteWith activationState: WCSessionActivationState, error: Error?) {}

  nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

  nonisolated func sessionDidDeactivate(_ session: WCSession) {
    session.activate()
  }

  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any], replyHandler: @escaping ([String: Any]) -> Void) {
    guard let question = message["ask"] as? String else { return }
    Task { @MainActor in
      await self.handleAsk(question, replyHandler: replyHandler)
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
    if let hr = message["hr"] as? Int, let at = message["at"] as? TimeInterval {
      Task { @MainActor in
        self.heartRate = hr
        self.lastHRAt = Date(timeIntervalSince1970: at)
        self.startStalenessLoop()
      }
      return
    }
    if message["hrEnded"] != nil {
      Task { @MainActor in
        self.heartRate = nil
        self.lastHRAt = nil
      }
      return
    }
    guard message["wantPlan"] != nil else { return }
    Task { @MainActor in
      guard let data = self.lastPlanData else { return }
      try? session.updateApplicationContext(["plan": data])
    }
  }

  nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any] = [:]) {
    guard let data = userInfo["set"] as? Data,
          let set = try? JSONDecoder().decode(WatchSet.self, from: data) else { return }
    Task { @MainActor in self.insert(set) }
  }

  private func handleAsk(_ question: String, replyHandler: @escaping ([String: Any]) -> Void) async {
    guard UserDefaults.standard.bool(forKey: "coachConsent") else {
      replyHandler(["answer": String(localized: "Turn on the coach in Regulift on iPhone first.", bundle: L10n.bundle)])
      return
    }
    guard let container else {
      replyHandler(["answer": String(localized: "Coach is offline right now.", bundle: L10n.bundle)])
      return
    }
    let context = ModelContext(container)
    let profiles = (try? context.fetch(FetchDescriptor<UserProfile>())) ?? []
    let sessions = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
    let checkIns = (try? context.fetch(FetchDescriptor<CheckIn>())) ?? []
    let noteTexts = ((try? context.fetch(FetchDescriptor<CoachNote>(sortBy: [SortDescriptor(\.date, order: .reverse)]))) ?? [])
      .prefix(20).map(\.text)
    let coach = Coach.from(UserDefaults.standard.string(forKey: Coach.storageKey) ?? "")
    let contextText = CoachAPI.dataBlock(profile: profiles.first, sessions: sessions, checkIns: checkIns, usesLb: profiles.first?.usesLb ?? false)
    do {
      let reply = try await CoachAPI.ask(
        question: question,
        context: contextText,
        coach: coach.name,
        history: [],
        notes: noteTexts)
      replyHandler(["answer": reply.answer])
    } catch {
      replyHandler(["answer": String(localized: "Coach is offline right now.", bundle: L10n.bundle)])
    }
  }

  private func insert(_ set: WatchSet) {
    guard let container else { return }
    let context = ModelContext(container)
    let calendar = Calendar.current
    let profile = (try? context.fetch(FetchDescriptor<UserProfile>()))?.first
    profile?.seedEquipmentPassportIfEmpty()
    let dayStart = calendar.startOfDay(for: set.date)
    let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
    let descriptor = FetchDescriptor<WorkoutSession>(
      predicate: #Predicate { $0.completed == false && $0.date >= dayStart && $0.date < dayEnd })
    let sessions = (try? context.fetch(descriptor)) ?? []
    let session = sessions.first ?? {
      let all = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
      let week = profile?.currentWeek(sessions: all) ?? 1
      let new = WorkoutSession(date: set.date, dayName: lastDayName, week: week, completed: false)
      context.insert(new)
      return new
    }()
    // A Watch set resolves the same descriptor the phone logger would: the bag carries kg and
    // no display string, so the original value is that kg number under the profile's context.
    let kind = ExerciseDB.find(set.exerciseID).map { EquipmentKind(equipment: $0.equipment) } ?? .unknown
    let loadDescriptor = profile?.equipmentLoadDescriptor(
      exerciseID: set.exerciseID,
      variant: nil,
      displayValue: "",
      displayUnit: "kg",
      weightKg: set.weightKg,
      side: UserProfile.defaultSide(for: kind))
      ?? LoggedSet.inferredDescriptor(exerciseID: set.exerciseID, weightKg: set.weightKg)
    let logged = LoggedSet(
      exerciseID: set.exerciseID,
      setIndex: set.setIndex,
      weightKg: set.weightKg,
      reps: set.reps,
      rpe: set.rpe,
      targetRPE: set.targetRPE,
      loggedAt: set.date,
      loadDescriptor: loadDescriptor,
      effortReported: true)
    context.insert(logged)
    session.sets.append(logged)
    try? context.save()
  }
}
