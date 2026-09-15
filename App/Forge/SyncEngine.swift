import Foundation
import SwiftData
import ForgeCore

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

@MainActor @Observable final class SyncEngine {
  static let shared = SyncEngine()

  private(set) var lastSync: Date?
  private(set) var syncing = false
  private(set) var lastError: String?

  private var container: ModelContainer?
  private let cursorKey = "forge.sync.cursor"
  private let pushedAtKey = "forge.sync.pushedAt"

  private static let iso: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  private init() {}

  func configure(container: ModelContainer) {
    self.container = container
  }

  func sync() async {
    guard !syncing, let container, AuthClient.shared.token != nil else { return }
    syncing = true
    defer { syncing = false }
    do {
      let context = ModelContext(container)
      let defaults = UserDefaults.standard
      let pushedAt = Date(timeIntervalSince1970: defaults.double(forKey: pushedAtKey))
      var pending = try localChanges(since: pushedAt, context: context)
      var cursor = defaults.integer(forKey: cursorKey)
      while true {
        let batch = Array(pending.prefix(500))
        pending.removeFirst(batch.count)
        let json = try await ForgeAPI.request("POST", "sync", body: ["cursor": cursor, "changes": batch], authorized: true)
        try apply(Self.parse(json["changes"]), context: context)
        cursor = json["cursor"] as? Int ?? cursor
        defaults.set(cursor, forKey: cursorKey)
        if batch.count < 500 { break }
      }
      defaults.set(Date.now.timeIntervalSince1970, forKey: pushedAtKey)
      lastSync = .now
      lastError = nil
    } catch {
      lastError = error.localizedDescription
    }
  }

  private func localChanges(since cutoff: Date, context: ModelContext) throws -> [[String: Any]] {
    var changes: [[String: Any]] = []
    if let profile = try context.fetch(FetchDescriptor<UserProfile>()).first, profile.updatedAt > cutoff {
      profile.ensureRemoteID()
      changes.append(Self.changeJSON(type: "profile", id: profile.remoteID, updatedAt: profile.updatedAt, deleted: false, data: profile.syncData))
    }
    for session in try context.fetch(FetchDescriptor<WorkoutSession>()) where session.updatedAt > cutoff {
      session.ensureRemoteID()
      changes.append(Self.changeJSON(type: "session", id: session.remoteID, updatedAt: session.updatedAt, deleted: session.deleted, data: session.syncData))
    }
    for checkin in try context.fetch(FetchDescriptor<CheckIn>()) where checkin.updatedAt > cutoff {
      checkin.ensureRemoteID()
      changes.append(Self.changeJSON(type: "checkin", id: checkin.remoteID, updatedAt: checkin.updatedAt, deleted: checkin.deleted, data: checkin.syncData))
    }
    for measurement in try context.fetch(FetchDescriptor<BodyMeasurement>()) where measurement.updatedAt > cutoff {
      measurement.ensureRemoteID()
      changes.append(Self.changeJSON(type: "measurement", id: measurement.remoteID, updatedAt: measurement.updatedAt, deleted: measurement.deleted, data: measurement.syncData))
    }
    for profile in try context.fetch(FetchDescriptor<NutritionProfile>()) where profile.updatedAt > cutoff {
      profile.ensureRemoteID()
      changes.append(Self.changeJSON(type: "nutrition", id: "profile-\(profile.remoteID)", updatedAt: profile.updatedAt, deleted: false, data: profile.syncData))
    }
    for entry in try context.fetch(FetchDescriptor<FoodEntry>()) where entry.updatedAt > cutoff {
      entry.ensureRemoteID()
      changes.append(Self.changeJSON(type: "nutrition", id: "food-\(entry.remoteID)", updatedAt: entry.updatedAt, deleted: entry.deleted, data: entry.syncData))
    }
    return changes
  }

  private static func changeJSON(type: String, id: String, updatedAt: Date, deleted: Bool, data: [String: Any]) -> [String: Any] {
    var json: [String: Any] = ["type": type, "id": id, "updatedAt": iso.string(from: updatedAt), "data": data]
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
            let updated = (dict["updatedAt"] as? String).flatMap({ iso.date(from: $0) }) else { return nil }
      return PullChange(type: type, id: id, updatedAt: updated, deleted: dict["deleted"] as? Bool ?? false, data: dict["data"] as? [String: Any] ?? [:])
    }
  }

  private func apply(_ changes: [PullChange], context: ModelContext) throws {
    guard !changes.isEmpty else { return }
    let profiles = try context.fetch(FetchDescriptor<UserProfile>())
    let sessionMap = Dictionary(try context.fetch(FetchDescriptor<WorkoutSession>()).map { ($0.remoteID, $0) }, uniquingKeysWith: { first, _ in first })
    let checkinMap = Dictionary(try context.fetch(FetchDescriptor<CheckIn>()).map { ($0.remoteID, $0) }, uniquingKeysWith: { first, _ in first })
    let measurementMap = Dictionary(try context.fetch(FetchDescriptor<BodyMeasurement>()).map { ($0.remoteID, $0) }, uniquingKeysWith: { first, _ in first })
    let nutritionMap = Dictionary(try context.fetch(FetchDescriptor<NutritionProfile>()).map { ($0.remoteID, $0) }, uniquingKeysWith: { first, _ in first })
    let entryMap = Dictionary(try context.fetch(FetchDescriptor<FoodEntry>()).map { ($0.remoteID, $0) }, uniquingKeysWith: { first, _ in first })

    for change in changes {
      switch change.type {
      case "profile":
        if let local = profiles.first {
          guard change.updatedAt > local.updatedAt else { break }
          if change.deleted {
            context.delete(local)
          } else {
            UserProfile.apply(change.data, to: local)
            local.remoteID = change.id
            local.updatedAt = change.updatedAt
          }
        } else if !change.deleted {
          let local = UserProfile(goal: .hypertrophy, experience: .intermediate, daysPerWeek: 3, sessionMinutes: 60, equipment: [], injuryFlags: [], recoveryReduced: false, bodyweightKg: 0, usesLb: false, startingLoads: [:])
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
        applyModel(change, remoteID: change.id, existing: checkinMap[change.id], make: { CheckIn(date: .now, sleep: 3, soreness: 3, energy: 3, sleepHours: 7) }, context: context)
      case "measurement":
        applyModel(change, remoteID: change.id, existing: measurementMap[change.id], make: { BodyMeasurement(date: .now) }, context: context)
      case "nutrition":
        if change.id.hasPrefix("food-") {
          let id = String(change.id.dropFirst(5))
          applyModel(change, remoteID: id, existing: entryMap[id], make: { FoodEntry(date: .now, meal: .snack, itemID: "", name: "", grams: 0, kcal: 0, proteinG: 0, carbsG: 0, fatG: 0) }, context: context)
        } else {
          let id = String(change.id.dropFirst("profile-".count))
          applyModel(change, remoteID: id, existing: nutritionMap[id], make: { NutritionProfile(sex: .male, age: 30, heightCm: 175, activity: .moderate, phase: .recomp) }, context: context)
        }
      default:
        break
      }
    }
    try context.save()
  }

  private func applyModel<M: SyncModel>(_ change: PullChange, remoteID: String, existing: M?, make: () -> M, context: ModelContext) {
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
}

extension FoodEntry: SyncModel {
  var syncData: [String: Any] {
    [
      "date": date.timeIntervalSince1970, "meal": meal, "itemID": itemID, "name": name, "grams": grams,
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
      "kcal": kcal, "proteinG": proteinG, "carbsG": carbsG, "fatG": fatG, "updated": updated.timeIntervalSince1970,
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
  var syncData: [String: Any] {
    [
      "date": date.timeIntervalSince1970, "sleep": sleep, "soreness": soreness, "energy": energy,
      "sleepHours": sleepHours, "motivation": motivation, "soreMuscles": soreMuscles,
    ]
  }

  static func apply(_ data: [String: Any], to checkin: CheckIn) {
    checkin.date = epochDate(data["date"]) ?? checkin.date
    checkin.sleep = data["sleep"] as? Int ?? checkin.sleep
    checkin.soreness = data["soreness"] as? Int ?? checkin.soreness
    checkin.energy = data["energy"] as? Int ?? checkin.energy
    checkin.sleepHours = data["sleepHours"] as? Double ?? checkin.sleepHours
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
      "sets": sets.sorted { $0.setIndex < $1.setIndex }.map {
        [
          "exerciseID": $0.exerciseID, "setIndex": $0.setIndex, "weightKg": $0.weightKg, "reps": $0.reps,
          "rpe": $0.rpe, "targetRPE": $0.targetRPE, "variant": $0.variant, "loggedAt": $0.loggedAt.timeIntervalSince1970,
        ]
      },
    ]
  }

  static func apply(_ data: [String: Any], to session: WorkoutSession) {
    session.date = epochDate(data["date"]) ?? session.date
    session.dayName = data["dayName"] as? String ?? session.dayName
    session.week = data["week"] as? Int ?? session.week
    session.completed = data["completed"] as? Bool ?? session.completed
    session.notes = data["notes"] as? String ?? session.notes
    session.order = data["order"] as? [String] ?? session.order
    session.supersets = data["supersets"] as? [String] ?? session.supersets
    session.extraExerciseIDs = data["extraExerciseIDs"] as? [String] ?? session.extraExerciseIDs
    session.removedExerciseIDs = data["removedExerciseIDs"] as? [String] ?? session.removedExerciseIDs
    session.setCounts = data["setCounts"] as? [String: Int] ?? session.setCounts
    var logged: [LoggedSet] = []
    for raw in data["sets"] as? [[String: Any]] ?? [] {
      logged.append(LoggedSet(
        exerciseID: raw["exerciseID"] as? String ?? "",
        setIndex: raw["setIndex"] as? Int ?? 0,
        weightKg: raw["weightKg"] as? Double ?? 0,
        reps: raw["reps"] as? Int ?? 0,
        rpe: raw["rpe"] as? Double ?? 0,
        targetRPE: raw["targetRPE"] as? Double ?? 0,
        variant: raw["variant"] as? String ?? "straight",
        loggedAt: epochDate(raw["loggedAt"]) ?? .now))
    }
    session.sets = logged
  }
}

extension UserProfile: SyncModel {
  var syncData: [String: Any] {
    [
      "goal": goal, "experience": experience, "daysPerWeek": daysPerWeek, "sessionMinutes": sessionMinutes,
      "equipment": equipment, "injuryFlags": injuryFlags, "recoveryReduced": recoveryReduced,
      "bodyweightKg": bodyweightKg, "usesLb": usesLb, "startingLoads": startingLoads,
      "mesoStart": mesoStart.timeIntervalSince1970,
      "trialStartedAt": trialStartedAt?.timeIntervalSince1970 ?? NSNull(),
      "nextDayIndex": nextDayIndex, "restCompoundSeconds": restCompoundSeconds, "restIsolationSeconds": restIsolationSeconds,
      "restOverrides": restOverrides,
      "deloadStartedAt": deloadStartedAt?.timeIntervalSince1970 ?? NSNull(),
      "unitOverrides": unitOverrides, "barKg": barKg, "barLb": barLb, "platesKg": platesKg, "platesLb": platesLb,
      "exerciseNotes": exerciseNotes, "exerciseOverrides": exerciseOverrides, "split": split, "theme": theme,
      "reminderHour": reminderHour ?? NSNull(), "reminderMinute": reminderMinute,
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
    profile.restIsolationSeconds = data["restIsolationSeconds"] as? Int ?? profile.restIsolationSeconds
    profile.restOverrides = data["restOverrides"] as? [String: Int] ?? profile.restOverrides
    profile.deloadStartedAt = epochDate(data["deloadStartedAt"])
    profile.unitOverrides = data["unitOverrides"] as? [String: Bool] ?? profile.unitOverrides
    profile.barKg = data["barKg"] as? Double ?? profile.barKg
    profile.barLb = data["barLb"] as? Double ?? profile.barLb
    profile.platesKg = data["platesKg"] as? [Double] ?? profile.platesKg
    profile.platesLb = data["platesLb"] as? [Double] ?? profile.platesLb
    profile.exerciseNotes = data["exerciseNotes"] as? [String: String] ?? profile.exerciseNotes
    profile.exerciseOverrides = data["exerciseOverrides"] as? [String: String] ?? profile.exerciseOverrides
    profile.split = data["split"] as? String ?? profile.split
    profile.theme = data["theme"] as? String ?? profile.theme
    profile.reminderHour = data["reminderHour"] as? Int
    profile.reminderMinute = data["reminderMinute"] as? Int ?? profile.reminderMinute
  }
}
