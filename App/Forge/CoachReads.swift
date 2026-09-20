import Foundation
import ForgeCore

/// The four local reads the coach is allowed to make, over data the caller already holds.
///
/// A value type built from snapshots, not a live store handle: a tool call cannot widen its
/// own access, cannot reach another profile, and cannot read a Health value — there is
/// nothing here that holds one. Every answer carries the plan revision it was true for, so
/// a stale read is visible as stale instead of being answered as current.
@MainActor
struct CoachLocalReads: CoachReadSource {
  let planRevision: String
  let asOf: Date
  let dayName: String?
  let prescriptions: [SetPrescription]
  let sessionID: String?
  let decisions: [DecisionRecord]
  let sets: [(exerciseID: String, at: Date, weightKg: Double, reps: Int, rpe: Double, effortReported: Bool)]
  let equipmentIDs: [String]
  let excludedExerciseIDs: [String]
  let minutesPerSession: Int?
  let daysPerWeek: Int?
  let usesLb: Bool

  func currentWorkout() -> CoachEnvelope<CurrentWorkoutProjection> {
    guard let dayName, let sessionID else {
      return .failure(.notFound, asOf: asOf, planRevision: planRevision)
    }
    return .ok(
      CurrentWorkoutProjection(sessionID: sessionID, dayName: dayName, prescriptions: prescriptions),
      asOf: asOf, planRevision: planRevision)
  }

  /// Lineage decides, not the caller: a decision that read readiness, sleep or soreness is
  /// `not_shared` even though the app can show its full reason on this screen.
  func decision(id: String) -> CoachEnvelope<DecisionProjection> {
    CoachReadContracts.decision(
      decisions.first(where: { $0.id == id }), asOf: asOf, planRevision: planRevision)
  }

  func recentSets(exerciseID: String, limit: Int) -> CoachEnvelope<[RecentSetProjection]> {
    let matches = sets
      .filter { $0.exerciseID == exerciseID }
      .sorted { $0.at > $1.at }
      .prefix(max(1, limit))
    guard !matches.isEmpty else {
      return .failure(.notFound, asOf: asOf, planRevision: planRevision)
    }
    let projections = matches.map { set in
      RecentSetProjection(
        exerciseID: set.exerciseID,
        performedAt: set.at,
        load: CoachLocalReads.load(kg: set.weightKg, usesLb: usesLb),
        reps: set.reps,
        // An unreported effort is absent, never the target value dressed up as an observation.
        rpeTenths: set.effortReported ? Int((set.rpe * 10).rounded()) : nil)
    }
    return .ok(Array(projections), asOf: asOf, planRevision: planRevision)
  }

  func constraints() -> CoachEnvelope<ConstraintsProjection> {
    .ok(
      ConstraintsProjection(
        equipmentIDs: equipmentIDs,
        excludedExerciseIDs: excludedExerciseIDs,
        minutesPerSession: minutesPerSession,
        daysPerWeek: daysPerWeek),
      asOf: asOf, planRevision: planRevision)
  }

  /// Kilograms are what the log stores; the lifter's unit is what the answer should speak.
  /// Converted once, here, so nothing downstream converts a second time.
  static func load(kg: Double, usesLb: Bool) -> LoadValue? {
    guard kg > 0 else { return nil }
    return usesLb
      ? LoadValue(milliUnits: Int64((Plates.kgToLb(kg) * 1000).rounded()), unit: .lb)
      : LoadValue(milliUnits: Int64((kg * 1000).rounded()), unit: .kg)
  }
}
