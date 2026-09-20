import ForgeCore
import Foundation
import SwiftData

protocol SyncModel: PersistentModel {
  var remoteID: String { get set }
  var updatedAt: Date { get set }
  static func apply(_ data: [String: Any], to model: Self)
}

private func epochDate(_ value: Any?) -> Date? {
  (value as? Double).map { Date(timeIntervalSince1970: $0) }
}

extension SyncModel {
  func ensureRemoteID() {
    if remoteID.isEmpty { remoteID = UUID().uuidString }
  }
}

enum AccountActivationError: Error, LocalizedError, Equatable {
  case storeUnavailable
  case invalidAccount
  case syncInProgress
  case differentLocalOwner

  var errorDescription: String? {
    switch self {
    case .storeUnavailable: return "Training data is not ready yet. Try again."
    case .invalidAccount: return "The signed-in account has no stable identifier."
    case .syncInProgress: return "Wait for the current sync to finish before switching accounts."
    case .differentLocalOwner:
      return
        "This device contains another account's training data and cannot switch accounts safely. Sign back into that account or reset this app's local data first."
    }
  }
}

@MainActor @Observable final class SyncEngine {
  static let shared = SyncEngine()

  private(set) var lastSync: Date?
  private(set) var syncing = false
  private(set) var lastError: String?

  private var container: ModelContainer?
  private var rerun = false
  private let cursorKey = "forge.sync.cursor"
  private let pushedAtKey = "forge.sync.pushedAt"
  static let adoptServerKey = "forge.sync.adoptServer"

  private static let iso: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private init() {}

  func configure(container: ModelContainer) {
    self.container = container
  }

  func markFreshLogin() {
    let defaults = UserDefaults.standard
    defaults.set(true, forKey: Self.adoptServerKey)
    defaults.set(0, forKey: cursorKey)
  }

  func sync() async {
    guard let container, AuthClient.shared.token != nil else { return }
    if syncing {
      rerun = true
      return
    }
    syncing = true
    defer { syncing = false }
    repeat {
      rerun = false
      do {
        let context = container.mainContext
        try context.save()
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: Self.adoptServerKey) {
          let adopt = try await ForgeAPI.request(
            "POST", "sync", body: ["cursor": 0, "changes": []], authorized: true)
          try apply(Self.parse(adopt["changes"]), context: context, adoptServer: true)
          defaults.set(adopt["cursor"] as? Int ?? 0, forKey: cursorKey)
          defaults.set(false, forKey: Self.adoptServerKey)
        }
        let pushedAt = Date(timeIntervalSince1970: defaults.double(forKey: pushedAtKey))
        var pending = try localChanges(since: pushedAt, context: context)
        let newPushedAt = pending.compactMap {
          Self.iso.date(from: $0["updatedAt"] as? String ?? "")
        }.max()
        var cursor = defaults.integer(forKey: cursorKey)
        while true {
          let batch = Array(pending.prefix(500))
          pending.removeFirst(batch.count)
          let json = try await ForgeAPI.request(
            "POST", "sync", body: ["cursor": cursor, "changes": batch], authorized: true)
          try apply(Self.parse(json["changes"]), context: context)
          cursor = json["cursor"] as? Int ?? cursor
          defaults.set(cursor, forKey: cursorKey)
          if batch.count < 500 { break }
        }
        if let newPushedAt {
          defaults.set(newPushedAt.timeIntervalSince1970, forKey: pushedAtKey)
        }
        lastSync = .now
        lastError = nil
      } catch {
        lastError = error.localizedDescription
        break
      }
    } while rerun
  }

  private func localChanges(since cutoff: Date, context: ModelContext) throws -> [[String: Any]] {
    var changes: [[String: Any]] = []
    if let profile = try context.fetch(FetchDescriptor<UserProfile>()).first,
      profile.updatedAt > cutoff
    {
      profile.ensureRemoteID()
      changes.append(
        Self.changeJSON(
          type: "profile", id: profile.remoteID, updatedAt: profile.updatedAt, deleted: false,
          data: profile.syncData))
    }
    for session in try context.fetch(FetchDescriptor<WorkoutSession>())
    where session.updatedAt > cutoff {
      session.ensureRemoteID()
      changes.append(
        Self.changeJSON(
          type: "session", id: session.remoteID, updatedAt: session.updatedAt,
          deleted: session.tombstoned, data: session.syncData))
    }
    for checkin in try context.fetch(FetchDescriptor<CheckIn>()) where checkin.updatedAt > cutoff {
      checkin.ensureRemoteID()
      changes.append(
        Self.changeJSON(
          type: "checkin", id: checkin.remoteID, updatedAt: checkin.updatedAt,
          deleted: checkin.tombstoned, data: checkin.syncData))
    }
    for measurement in try context.fetch(FetchDescriptor<BodyMeasurement>())
    where measurement.updatedAt > cutoff {
      measurement.ensureRemoteID()
      changes.append(
        Self.changeJSON(
          type: "measurement", id: measurement.remoteID, updatedAt: measurement.updatedAt,
          deleted: measurement.tombstoned, data: measurement.syncData))
    }
    for profile in try context.fetch(FetchDescriptor<NutritionProfile>())
    where profile.updatedAt > cutoff {
      profile.ensureRemoteID()
      changes.append(
        Self.changeJSON(
          type: "nutrition", id: "profile-\(profile.remoteID)", updatedAt: profile.updatedAt,
          deleted: false, data: profile.syncData))
    }
    for entry in try context.fetch(FetchDescriptor<FoodEntry>()) where entry.updatedAt > cutoff {
      entry.ensureRemoteID()
      changes.append(
        Self.changeJSON(
          type: "nutrition", id: "food-\(entry.remoteID)", updatedAt: entry.updatedAt,
          deleted: entry.tombstoned, data: entry.syncData))
    }
    for exercise in try context.fetch(FetchDescriptor<CustomExercise>())
    where exercise.updatedAt > cutoff {
      exercise.ensureRemoteID()
      changes.append(
        Self.changeJSON(
          type: "exercise", id: exercise.remoteID, updatedAt: exercise.updatedAt,
          deleted: exercise.tombstoned, data: exercise.syncData))
    }
    return changes
  }

  private static func changeJSON(
    type: String, id: String, updatedAt: Date, deleted: Bool, data: [String: Any]
  ) -> [String: Any] {
    var json: [String: Any] = [
      "type": type, "id": id, "updatedAt": iso.string(from: updatedAt), "data": data,
    ]
    if deleted { json["deleted"] = true }
    return json
  }

  private struct PullChange {
    let type: String
    let id: String
    let updatedAt: Date
    let deleted: Bool
    let data: [String: Any]
  }

  private static func parse(_ raw: Any?) -> [PullChange] {
    guard let array = raw as? [[String: Any]] else { return [] }
    return array.compactMap { dict in
      guard let type = dict["type"] as? String,
        let id = dict["id"] as? String,
        let updated = (dict["updatedAt"] as? String).flatMap({ iso.date(from: $0) })
      else { return nil }
      return PullChange(
        type: type, id: id, updatedAt: updated, deleted: dict["deleted"] as? Bool ?? false,
        data: dict["data"] as? [String: Any] ?? [:])
    }
  }

  private func apply(_ changes: [PullChange], context: ModelContext, adoptServer: Bool = false)
    throws
  {
    guard !changes.isEmpty else { return }
    let profiles = try context.fetch(FetchDescriptor<UserProfile>())
    let sessionMap = Dictionary(
      try context.fetch(FetchDescriptor<WorkoutSession>()).map { ($0.remoteID, $0) },
      uniquingKeysWith: { first, _ in first })
    let checkinMap = Dictionary(
      try context.fetch(FetchDescriptor<CheckIn>()).map { ($0.remoteID, $0) },
      uniquingKeysWith: { first, _ in first })
    let measurementMap = Dictionary(
      try context.fetch(FetchDescriptor<BodyMeasurement>()).map { ($0.remoteID, $0) },
      uniquingKeysWith: { first, _ in first })
    let nutritionMap = Dictionary(
      try context.fetch(FetchDescriptor<NutritionProfile>()).map { ($0.remoteID, $0) },
      uniquingKeysWith: { first, _ in first })
    let entryMap = Dictionary(
      try context.fetch(FetchDescriptor<FoodEntry>()).map { ($0.remoteID, $0) },
      uniquingKeysWith: { first, _ in first })
    let customExerciseMap = Dictionary(
      try context.fetch(FetchDescriptor<CustomExercise>()).map { ($0.remoteID, $0) },
      uniquingKeysWith: { first, _ in first })

    for change in changes {
      switch change.type {
      case "profile":
        if let local = profiles.first {
          let adopt = adoptServer && !change.deleted
          guard adopt || change.updatedAt > local.updatedAt else { break }
          if change.deleted {
            context.delete(local)
          } else {
            UserProfile.apply(change.data, to: local)
            local.remoteID = change.id
            local.updatedAt = change.updatedAt
          }
        } else if !change.deleted {
          let local = UserProfile(
            goal: .hypertrophy, experience: .intermediate, daysPerWeek: 3, sessionMinutes: 60,
            equipment: [], injuryFlags: [], recoveryReduced: false, bodyweightKg: 0, usesLb: false,
            startingLoads: [:])
          UserProfile.apply(change.data, to: local)
          local.remoteID = change.id
          local.updatedAt = change.updatedAt
          context.insert(local)
        }
      case "session":
        if let local = sessionMap[change.id] {
          guard change.updatedAt > local.updatedAt else { break }
          if change.deleted {
            context.delete(local)
          } else {
            for set in local.sets { context.delete(set) }
            WorkoutSession.apply(change.data, to: local)
            local.updatedAt = change.updatedAt
          }
        } else if !change.deleted {
          let local = WorkoutSession(date: .now, dayName: "", week: 1, completed: false)
          WorkoutSession.apply(change.data, to: local)
          local.remoteID = change.id
          local.updatedAt = change.updatedAt
          context.insert(local)
        }
      case "checkin":
        applyModel(
          change, remoteID: change.id, existing: checkinMap[change.id],
          make: { CheckIn(date: .now, sleep: 3, soreness: 3, energy: 3, sleepHours: 7) },
          context: context)
      case "measurement":
        applyModel(
          change, remoteID: change.id, existing: measurementMap[change.id],
          make: { BodyMeasurement(date: .now) }, context: context)
      case "nutrition":
        if change.id.hasPrefix("food-") {
          let id = String(change.id.dropFirst(5))
          applyModel(
            change, remoteID: id, existing: entryMap[id],
            make: {
              FoodEntry(
                date: .now, meal: .snack, itemID: "", name: "", grams: 0, kcal: 0, proteinG: 0,
                carbsG: 0, fatG: 0)
            }, context: context)
        } else {
          let id = String(change.id.dropFirst("profile-".count))
          applyModel(
            change, remoteID: id, existing: nutritionMap[id],
            make: {
              NutritionProfile(
                sex: .male, age: 30, heightCm: 175, activity: .moderate, phase: .recomp)
            }, context: context)
        }
      case "exercise":
        applyModel(
          change, remoteID: change.id, existing: customExerciseMap[change.id],
          make: {
            CustomExercise(
              name: "", primary: .chest, synergists: [], isCompound: false, equipment: .machine)
          }, context: context)
      default:
        break
      }
    }
    try context.save()
    CustomExerciseRegistry.reload(context)
  }

  private func applyModel<M: SyncModel>(
    _ change: PullChange, remoteID: String, existing: M?, make: () -> M, context: ModelContext
  ) {
    if let existing {
      guard change.updatedAt > existing.updatedAt else { return }
      if change.deleted {
        context.delete(existing)
      } else {
        M.apply(change.data, to: existing)
        existing.remoteID = remoteID
        existing.updatedAt = change.updatedAt
      }
    } else if !change.deleted {
      let local = make()
      M.apply(change.data, to: local)
      local.remoteID = remoteID
      local.updatedAt = change.updatedAt
      context.insert(local)
    }
  }

  static let storeOwnerKey = "forge.sync.storeOwner"

  func prepareAccountActivation(userID: String) throws {
    guard !syncing else { throw AccountActivationError.syncInProgress }
    guard let container else { throw AccountActivationError.storeUnavailable }
    let owner = JourneyEventID.canonicalOwner(userID)
    guard !owner.isEmpty else { throw AccountActivationError.invalidAccount }

    let context = container.mainContext
    let profile = try context.fetch(FetchDescriptor<UserProfile>()).first
    let storedOwner = JourneyEventID.canonicalOwner(
      UserDefaults.standard.string(forKey: Self.storeOwnerKey) ?? "")
    let profileOwner = JourneyEventID.canonicalOwner(profile?.journeyBoundAccountID ?? "")
    for existingOwner in [storedOwner, profileOwner] where !existingOwner.isEmpty {
      guard existingOwner == owner else { throw AccountActivationError.differentLocalOwner }
    }

    UserDefaults.standard.set(owner, forKey: Self.storeOwnerKey)
  }
}

extension FoodEntry: SyncModel {
  var syncData: [String: Any] {
    [
      "date": date.timeIntervalSince1970, "meal": meal, "itemID": itemID, "name": name,
      "grams": grams,
      "kcal": kcal, "proteinG": proteinG, "carbsG": carbsG, "fatG": fatG,
    ]
  }

  static func apply(_ data: [String: Any], to entry: FoodEntry) {
    entry.date = epochDate(data["date"]) ?? entry.date
    entry.meal = data["meal"] as? String ?? entry.meal
    entry.itemID = data["itemID"] as? String ?? entry.itemID
    entry.name = data["name"] as? String ?? entry.name
    entry.grams = data["grams"] as? Double ?? entry.grams
    entry.kcal = data["kcal"] as? Double ?? entry.kcal
    entry.proteinG = data["proteinG"] as? Double ?? entry.proteinG
    entry.carbsG = data["carbsG"] as? Double ?? entry.carbsG
    entry.fatG = data["fatG"] as? Double ?? entry.fatG
  }
}

extension NutritionProfile: SyncModel {
  var syncData: [String: Any] {
    [
      "sex": sex, "age": age, "heightCm": heightCm, "activity": activity, "phase": phase,
      "kcal": kcal, "proteinG": proteinG, "carbsG": carbsG, "fatG": fatG,
      "updated": updated.timeIntervalSince1970,
    ]
  }

  static func apply(_ data: [String: Any], to profile: NutritionProfile) {
    profile.sex = data["sex"] as? String ?? profile.sex
    profile.age = data["age"] as? Int ?? profile.age
    profile.heightCm = data["heightCm"] as? Double ?? profile.heightCm
    profile.activity = data["activity"] as? String ?? profile.activity
    profile.phase = data["phase"] as? String ?? profile.phase
    profile.kcal = data["kcal"] as? Int ?? profile.kcal
    profile.proteinG = data["proteinG"] as? Int ?? profile.proteinG
    profile.carbsG = data["carbsG"] as? Int ?? profile.carbsG
    profile.fatG = data["fatG"] as? Int ?? profile.fatG
    profile.updated = epochDate(data["updated"]) ?? profile.updated
  }
}

extension BodyMeasurement: SyncModel {
  var syncData: [String: Any] {
    [
      "date": date.timeIntervalSince1970,
      "weightKg": weightKg ?? NSNull(),
      "bodyFatPercent": bodyFatPercent ?? NSNull(),
      "tape": tape,
    ]
  }

  static func apply(_ data: [String: Any], to measurement: BodyMeasurement) {
    measurement.date = epochDate(data["date"]) ?? measurement.date
    measurement.weightKg = data["weightKg"] as? Double
    measurement.bodyFatPercent = data["bodyFatPercent"] as? Double
    measurement.tape = data["tape"] as? [String: Double] ?? measurement.tape
  }
}

extension CheckIn: SyncModel {
  // Only subjective scores travel. `sleepHours` may be HealthKit-derived, so the client
  // omits it, the server strips it from older clients, and migration 0003 removes stored copies.
  var syncData: [String: Any] {
    [
      "date": date.timeIntervalSince1970, "sleep": sleep, "soreness": soreness, "energy": energy,
      "motivation": motivation, "soreMuscles": soreMuscles,
    ]
  }

  static func apply(_ data: [String: Any], to checkin: CheckIn) {
    checkin.date = epochDate(data["date"]) ?? checkin.date
    checkin.sleep = data["sleep"] as? Int ?? checkin.sleep
    checkin.soreness = data["soreness"] as? Int ?? checkin.soreness
    checkin.energy = data["energy"] as? Int ?? checkin.energy
    checkin.motivation = data["motivation"] as? Int ?? checkin.motivation
    checkin.soreMuscles = data["soreMuscles"] as? [String] ?? checkin.soreMuscles
  }
}

extension WorkoutSession: SyncModel {
  var syncData: [String: Any] {
    [
      "date": date.timeIntervalSince1970, "dayName": dayName, "week": week, "completed": completed,
      "notes": notes, "order": order, "supersets": supersets, "extraExerciseIDs": extraExerciseIDs,
      "removedExerciseIDs": removedExerciseIDs, "setCounts": setCounts,
      // Objective signal that the session was actually trained. Round-tripped so a
      // restored or re-installed device keeps the same plausibility verdict.
      "heartRateSeen": heartRateSeen,
      "sets": sets.sorted { $0.setIndex < $1.setIndex }.map {
        [
          "exerciseID": $0.exerciseID, "setIndex": $0.setIndex, "weightKg": $0.weightKg,
          "reps": $0.reps,
          "rpe": $0.rpe, "targetRPE": $0.targetRPE, "variant": $0.variant,
          "loggedAt": $0.loggedAt.timeIntervalSince1970,
          "originalLoadValue": $0.originalLoadValue, "originalLoadUnit": $0.originalLoadUnit,
          "loadDomain": $0.loadDomain, "loadingConvention": $0.loadingConvention,
          "equipmentInstanceID": $0.equipmentInstanceID ?? NSNull(),
          "loadModelRevision": $0.loadModelRevision ?? NSNull(),
          "loadSide": $0.loadSide, "loadNormalizationStatus": $0.loadNormalizationStatus,
          // The trust flags travel with the set. Without these a suspect, unreported or
          // lifter-withheld set would come back as clean, trusted data on another device.
          "suspect": $0.suspect, "effortReported": $0.effortReported,
          "feedbackJSON": $0.feedbackJSON,
        ]
      },
    ]
  }

  static func apply(_ data: [String: Any], to session: WorkoutSession) {
    session.date = epochDate(data["date"]) ?? session.date
    session.dayName = data["dayName"] as? String ?? session.dayName
    session.week = data["week"] as? Int ?? session.week
    session.completed = data["completed"] as? Bool ?? session.completed
    session.heartRateSeen = data["heartRateSeen"] as? Bool ?? session.heartRateSeen
    session.notes = data["notes"] as? String ?? session.notes
    session.order = data["order"] as? [String] ?? session.order
    session.supersets = data["supersets"] as? [String] ?? session.supersets
    session.extraExerciseIDs = data["extraExerciseIDs"] as? [String] ?? session.extraExerciseIDs
    session.removedExerciseIDs =
      data["removedExerciseIDs"] as? [String] ?? session.removedExerciseIDs
    session.setCounts = data["setCounts"] as? [String: Int] ?? session.setCounts
    var logged: [LoggedSet] = []
    for raw in data["sets"] as? [[String: Any]] ?? [] {
      let weightKg = raw["weightKg"] as? Double ?? 0
      let descriptor: LoadDescriptor
      if let conventionRaw = raw["loadingConvention"] as? String {
        descriptor = LoadDescriptor(
          originalValue: raw["originalLoadValue"] as? String ?? String(weightKg),
          originalUnit: raw["originalLoadUnit"] as? String ?? "kg",
          domain: LoadDomain(rawValue: raw["loadDomain"] as? String ?? "") ?? .externalMass,
          convention: LoadingConvention(rawValue: conventionRaw) ?? .unknown,
          equipmentInstanceID: raw["equipmentInstanceID"] as? String,
          loadModelRevision: raw["loadModelRevision"] as? Int,
          side: LoadSide(rawValue: raw["loadSide"] as? String ?? "") ?? .unspecified,
          normalizationStatus: LoadNormalizationStatus(
            rawValue: raw["loadNormalizationStatus"] as? String ?? "") ?? .ambiguous)
      } else {
        descriptor = .legacy(weightKg: weightKg)
      }
      let set = LoggedSet(
        exerciseID: raw["exerciseID"] as? String ?? "",
        setIndex: raw["setIndex"] as? Int ?? 0,
        weightKg: weightKg,
        reps: raw["reps"] as? Int ?? 0,
        rpe: raw["rpe"] as? Double ?? 0,
        targetRPE: raw["targetRPE"] as? Double ?? 0,
        variant: raw["variant"] as? String ?? "straight",
        loggedAt: epochDate(raw["loggedAt"]) ?? .now,
        loadDescriptor: descriptor,
        effortReported: raw["effortReported"] as? Bool ?? false)
      // Absent keys keep the legacy defaults (not suspect, effort unknown, no feedback),
      // so an older payload is never upgraded into trusted or reported data.
      set.suspect = raw["suspect"] as? Bool ?? false
      set.feedbackJSON = raw["feedbackJSON"] as? String ?? ""
      logged.append(set)
    }
    session.sets = logged
  }
}

extension CustomExercise: SyncModel {
  var syncData: [String: Any] {
    [
      "name": name, "primary": primary, "synergists": synergists, "equipment": equipment,
      "isCompound": isCompound, "pattern": pattern,
    ]
  }

  static func apply(_ data: [String: Any], to exercise: CustomExercise) {
    exercise.name = data["name"] as? String ?? exercise.name
    exercise.primary = data["primary"] as? String ?? exercise.primary
    exercise.synergists = data["synergists"] as? [String] ?? exercise.synergists
    exercise.equipment = data["equipment"] as? String ?? exercise.equipment
    exercise.isCompound = data["isCompound"] as? Bool ?? exercise.isCompound
    exercise.pattern = data["pattern"] as? String ?? exercise.pattern
  }
}

extension UserProfile: SyncModel {
  var syncData: [String: Any] {
    [
      "goal": goal, "experience": experience, "daysPerWeek": daysPerWeek,
      "sessionMinutes": sessionMinutes,
      "equipment": equipment, "injuryFlags": injuryFlags, "recoveryReduced": recoveryReduced,
      "bodyweightKg": bodyweightKg, "usesLb": usesLb, "startingLoads": startingLoads,
      "mesoStart": mesoStart.timeIntervalSince1970,
      "trialStartedAt": trialStartedAt?.timeIntervalSince1970 ?? NSNull(),
      "nextDayIndex": nextDayIndex, "restCompoundSeconds": restCompoundSeconds,
      "restIsolationSeconds": restIsolationSeconds,
      "restOverrides": restOverrides,
      "deloadStartedAt": deloadStartedAt?.timeIntervalSince1970 ?? NSNull(),
      "unitOverrides": unitOverrides, "barKg": barKg, "barLb": barLb, "platesKg": platesKg,
      "platesLb": platesLb,
      "exerciseNotes": exerciseNotes, "exerciseOverrides": exerciseOverrides, "split": split,
      "gymPreset": gymPreset, "theme": theme,
      "constraintsJSON": constraintsJSON, "experimentJSON": experimentJSON,
      // Rotational state and feature payloads. `shareTokensJSON` is deliberately omitted —
      // a share token is a bearer secret and must never leave the device.
      "setDeltas": setDeltas, "repRangeOverrides": repRangeOverrides,
      "mesoSessionOffset": mesoSessionOffset,
      "equipmentPassportJSON": equipmentPassportJSON,
      "equipmentBindingsJSON": equipmentBindingsJSON,
      "weekPlanJSON": weekPlanJSON, "goalRecordsJSON": goalRecordsJSON,
      "recommendationLedgerJSON": recommendationLedgerJSON,
      "importedProgramJSON": importedProgramJSON,
      "activeProgramVersionJSON": activeProgramVersionJSON,
      "reminderHour": reminderHour ?? NSNull(), "reminderMinute": reminderMinute,
      "coachID": UserDefaults.standard.string(forKey: Coach.storageKey) ?? Coach.nova.rawValue,
    ]
  }

  static func apply(_ data: [String: Any], to profile: UserProfile) {
    profile.goal = data["goal"] as? String ?? profile.goal
    profile.experience = data["experience"] as? String ?? profile.experience
    profile.daysPerWeek = data["daysPerWeek"] as? Int ?? profile.daysPerWeek
    profile.sessionMinutes = data["sessionMinutes"] as? Int ?? profile.sessionMinutes
    profile.equipment = data["equipment"] as? [String] ?? profile.equipment
    profile.injuryFlags = data["injuryFlags"] as? [String] ?? profile.injuryFlags
    profile.recoveryReduced = data["recoveryReduced"] as? Bool ?? profile.recoveryReduced
    profile.bodyweightKg = data["bodyweightKg"] as? Double ?? profile.bodyweightKg
    profile.usesLb = data["usesLb"] as? Bool ?? profile.usesLb
    profile.startingLoads = data["startingLoads"] as? [String: Double] ?? profile.startingLoads
    profile.mesoStart = epochDate(data["mesoStart"]) ?? profile.mesoStart
    profile.trialStartedAt = epochDate(data["trialStartedAt"])
    profile.nextDayIndex = data["nextDayIndex"] as? Int ?? profile.nextDayIndex
    profile.restCompoundSeconds = data["restCompoundSeconds"] as? Int ?? profile.restCompoundSeconds
    profile.restIsolationSeconds =
      data["restIsolationSeconds"] as? Int ?? profile.restIsolationSeconds
    profile.restOverrides = data["restOverrides"] as? [String: Int] ?? profile.restOverrides
    profile.deloadStartedAt = epochDate(data["deloadStartedAt"])
    profile.unitOverrides = data["unitOverrides"] as? [String: Bool] ?? profile.unitOverrides
    profile.barKg = data["barKg"] as? Double ?? profile.barKg
    profile.barLb = data["barLb"] as? Double ?? profile.barLb
    profile.platesKg = data["platesKg"] as? [Double] ?? profile.platesKg
    profile.platesLb = data["platesLb"] as? [Double] ?? profile.platesLb
    profile.exerciseNotes = data["exerciseNotes"] as? [String: String] ?? profile.exerciseNotes
    profile.exerciseOverrides =
      data["exerciseOverrides"] as? [String: String] ?? profile.exerciseOverrides
    profile.split = data["split"] as? String ?? profile.split
    profile.gymPreset = data["gymPreset"] as? String ?? profile.gymPreset
    profile.theme = data["theme"] as? String ?? profile.theme
    profile.constraintsJSON = data["constraintsJSON"] as? String ?? profile.constraintsJSON
    profile.experimentJSON = data["experimentJSON"] as? String ?? profile.experimentJSON
    // Absent keys keep the local value — including the never-synced share tokens, which
    // this list must not touch.
    profile.setDeltas = data["setDeltas"] as? [String: Int] ?? profile.setDeltas
    profile.repRangeOverrides =
      data["repRangeOverrides"] as? [String: String] ?? profile.repRangeOverrides
    profile.mesoSessionOffset = data["mesoSessionOffset"] as? Int ?? profile.mesoSessionOffset
    profile.equipmentPassportJSON =
      data["equipmentPassportJSON"] as? String ?? profile.equipmentPassportJSON
    profile.equipmentBindingsJSON =
      data["equipmentBindingsJSON"] as? String ?? profile.equipmentBindingsJSON
    profile.weekPlanJSON = data["weekPlanJSON"] as? String ?? profile.weekPlanJSON
    profile.goalRecordsJSON = data["goalRecordsJSON"] as? String ?? profile.goalRecordsJSON
    profile.recommendationLedgerJSON =
      data["recommendationLedgerJSON"] as? String ?? profile.recommendationLedgerJSON
    profile.importedProgramJSON =
      data["importedProgramJSON"] as? String ?? profile.importedProgramJSON
    profile.activeProgramVersionJSON =
      data["activeProgramVersionJSON"] as? String ?? profile.activeProgramVersionJSON
    profile.reminderHour = data["reminderHour"] as? Int
    profile.reminderMinute = data["reminderMinute"] as? Int ?? profile.reminderMinute
    if let id = data["coachID"] as? String, Coach(rawValue: id) != nil {
      UserDefaults.standard.set(id, forKey: Coach.storageKey)
    }
  }
}
