import Foundation
import SwiftData
import XCTest
import ForgeCore
@testable import Forge

/// Shared fixtures for the Journey integration tests.
///
/// The in-memory container registers **the same schema** `ForgeApp.sharedContainer` registers
/// (`App/Forge/ForgeApp.swift:12-17`). A narrower schema would not prove anything about the
/// shipped store, because SwiftData only persists a model that is registered in the container —
/// registering `JourneyReflection` here and nowhere else is exactly the bug these tests exist to
/// catch.
@MainActor
enum JourneyTestStore {

  /// Fixed UTC Gregorian calendar. Month boundaries, `startOfDay` and the "future day" validation
  /// must not move with the machine's time zone, or a run at 23:30 local would fail the suite.
  static let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
    calendar.locale = Locale(identifier: "en_US_POSIX")
    return calendar
  }()

  /// A deterministic instant, defaulting to local noon so `startOfDay` is unambiguous.
  static func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 12) -> Date {
    calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour))
      ?? Date(timeIntervalSince1970: 0)
  }

  /// Every model the app's container declares, in the app's order.
  static let models: [any PersistentModel.Type] = [
    UserProfile.self, CheckIn.self, WorkoutSession.self, LoggedSet.self,
    BodyMeasurement.self, ProgressPhoto.self, CoachMessage.self, CoachNote.self,
    NutritionProfile.self, FoodItem.self, FoodEntry.self, CustomExercise.self,
    DecisionLogEntry.self, JourneyReflection.self, JourneyVisibilityOverride.self,
    JourneyPrivateProfile.self,
  ]

  static func container(_ configuration: ModelConfiguration) throws -> ModelContainer {
    try ModelContainer(for: Schema(models), configurations: configuration)
  }

  static func inMemory() throws -> ModelContainer {
    try container(ModelConfiguration(isStoredInMemoryOnly: true))
  }

  /// A file-backed store, so a second container can be opened on the same URL.
  static func onDisk(at url: URL) throws -> ModelContainer {
    try container(ModelConfiguration(url: url))
  }

  /// The one profile row `JourneyRepository.resolveOwner` needs. Its `journeyLocalOwnerID`
  /// starts empty on purpose, which is what makes the repository mint a canonical owner.
  @discardableResult
  static func profile(in context: ModelContext) throws -> UserProfile {
    let profile = UserProfile(
      goal: .hypertrophy,
      experience: .intermediate,
      daysPerWeek: 4,
      sessionMinutes: 60,
      equipment: [.barbell, .dumbbell],
      injuryFlags: [],
      recoveryReduced: false,
      bodyweightKg: 80,
      usesLb: false,
      startingLoads: [:])
    context.insert(profile)
    try context.save()
    return profile
  }

  /// The stored property names SwiftData records for `type`, read off the schema rather than
  /// guessed from a `Mirror` (SwiftData classes mirror their backing storage, not their fields).
  static func attributeNames(of type: any PersistentModel.Type) -> Set<String> {
    let name = String(describing: type)
    let entity = Schema([type]).entities.first { $0.name == name }
    return Set((entity?.attributes ?? []).map(\.name))
  }

  /// A repository wired to the fixed calendar and a clock frozen at `now`.
  static func repository(
    context: ModelContext,
    profile: UserProfile,
    now: Date? = nil
  ) -> JourneyRepository {
    // Not a default argument: a default is evaluated in a nonisolated context, which cannot call
    // the main-actor-isolated `date(_:_:_:)`.
    let instant = now ?? date(2025, 6, 20)
    return JourneyRepository(context: context, profile: profile, calendar: calendar, now: { instant })
  }
}
