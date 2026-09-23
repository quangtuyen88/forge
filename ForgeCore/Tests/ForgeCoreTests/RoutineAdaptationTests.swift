import XCTest
@testable import ForgeCore

final class RoutineAdaptationTests: XCTestCase {
  func testAcceptedDayMarkerDecodesOldPlansAndRoundTripsNewOnes() throws {
    var day = WeekPlanDay(id: "d1", date: .now, sessionName: "Full A")
    let oldData = try JSONEncoder().encode(day)
    XCTAssertNil(try JSONDecoder().decode(WeekPlanDay.self, from: oldData).routineApplicationID)
    day.routineApplicationID = "confirmed-application"
    let newData = try JSONEncoder().encode(day)
    XCTAssertEqual(try JSONDecoder().decode(WeekPlanDay.self, from: newData).routineApplicationID,
      "confirmed-application")
    var plan = WeekPlan(id: "week", weekStart: day.date, enrollmentDate: day.date, days: [day])
    XCTAssertTrue(plan.move(dayID: day.id, to: day.date.addingTimeInterval(2 * 86400)))
    XCTAssertEqual(plan.days.first { $0.state == .planned }?.routineApplicationID,
      "confirmed-application")
  }

  private func profile(
    equipment: Set<Equipment> = [.barbell, .dumbbell],
    minutes: Int = 60,
    locked: Set<String> = [],
    injuries: Set<InjuryFlag> = []
  ) -> ProfileInput {
    ProfileInput(
      goal: .hypertrophy, daysPerWeek: 3, sessionLength: .m60,
      equipment: equipment, injuryFlags: injuries,
      lockedExerciseIDs: locked, sessionBudgetMinutes: minutes)
  }

  private func entry(
    _ id: String = "barbell_bench", sets: Int = 3,
    low: Int = 8, high: Int = 12, target: Double? = 8
  ) -> ProgramExerciseEntry {
    ProgramExerciseEntry(
      exerciseID: id, sets: sets, repRangeLower: low,
      repRangeUpper: high, targetRPE: target)
  }

  func testCopyKeepsFirstExerciseAppearanceNotPerExerciseSetIndexOrder() throws {
    let result = RoutineExtractionPolicy.extract(dayName: "Source", sets: [
      RoutineSetInput(exerciseID: "barbell_bench", setIndex: 2, reps: 8, targetRPE: 8),
      RoutineSetInput(exerciseID: "bent_row", setIndex: 0, reps: 10, targetRPE: 7),
      RoutineSetInput(exerciseID: "barbell_bench", setIndex: 3, reps: 9, targetRPE: 8),
    ])
    let day = try XCTUnwrap(result.day)
    XCTAssertEqual(day.exerciseIDs, ["barbell_bench", "bent_row"])
    XCTAssertEqual(day.exercises.first?.sets, 2)
    XCTAssertEqual(day.exercises.first?.repRange, 8...9)
    let json = String(decoding: try JSONEncoder().encode(day), as: UTF8.self)
    for key in ["weightKg", "reportedRPE", "effortReported", "notes", "equipmentInstanceID"] {
      XCTAssertFalse(json.contains("\"\(key)\""))
    }
  }

  func testCopyDoesNotFillMissingTargetsFromAnotherSet() throws {
    let result = RoutineExtractionPolicy.extract(dayName: "Source", sets: [
      RoutineSetInput(exerciseID: "barbell_bench", setIndex: 0, reps: 8, targetRPE: 8),
      RoutineSetInput(exerciseID: "barbell_bench", setIndex: 1, reps: 8, targetRPE: nil),
    ])
    XCTAssertNil(try XCTUnwrap(result.day).exercises.first?.targetRPE)
  }

  func testCopyNeverProducesInvertedRepRangeForOutOfBoundsHistory() {
    let result = RoutineExtractionPolicy.extract(dayName: "Source", sets: [
      RoutineSetInput(exerciseID: "barbell_bench", setIndex: 0, reps: 100),
    ])
    XCTAssertNil(result.day)
    XCTAssertFalse(result.notes.isEmpty)
  }

  func testUnconstrainedAdaptationPreservesSourceAndIsDeterministic() {
    let source = ProgramDay(name: "Source", exercises: [entry(), entry("bent_row")])
    let result = RoutineAdaptation.adapt(source, profile: profile())
    XCTAssertTrue(result.isExecutable)
    XCTAssertEqual(result.adaptedDay, source)
    XCTAssertEqual(result, RoutineAdaptation.adapt(source, profile: profile()))
  }

  func testEquipmentAdaptationUsesAvailableEquipmentAndExplainsTheChange() throws {
    let source = ProgramDay(name: "Source", exercises: [entry()])
    let result = RoutineAdaptation.adapt(source, profile: profile(equipment: [.dumbbell]))
    XCTAssertTrue(result.isExecutable)
    let adapted = try XCTUnwrap(result.adaptedDay.exercises.first)
    XCTAssertNotEqual(adapted.exerciseID, "barbell_bench")
    XCTAssertEqual(ExerciseDB.find(adapted.exerciseID)?.equipment, .dumbbell)
    XCTAssertTrue(result.entries[0].changes.contains { $0.kind == .equipmentSwap })
    XCTAssertEqual(result.sourceDay, source)
  }

  func testUnknownExerciseBlocksWholeRoutineRatherThanSavingPartialSuccess() {
    let result = RoutineAdaptation.adapt(
      ProgramDay(name: "Source", exercises: [entry(), entry("private_custom_lift")]),
      profile: profile())
    XCTAssertFalse(result.isExecutable)
    XCTAssertTrue(result.blockers.contains { $0.kind == .unknownExercise })
  }

  func testMalformedPrescriptionsDoNotBecomeExecutableBySilentRepair() {
    for invalid in [entry(sets: -1), entry(low: 12, high: 8), entry(target: .nan)] {
      let result = RoutineAdaptation.adapt(
        ProgramDay(name: "Source", exercises: [invalid]), profile: profile())
      XCTAssertFalse(result.isExecutable)
    }
  }

  func testDuplicateExerciseSlotsDoNotLoseDifferentPrescriptionsInLogger() {
    let result = RoutineAdaptation.adapt(
      ProgramDay(name: "Source", exercises: [entry(), entry(sets: 2, low: 3, high: 5)]),
      profile: profile())
    XCTAssertFalse(result.isExecutable)
  }

  func testLockedWorkThatCannotFitTimeBudgetBlocksApply() {
    let ids = ["barbell_bench", "bent_row", "back_squat"]
    let result = RoutineAdaptation.adapt(
      ProgramDay(name: "Source", exercises: ids.map { entry($0, sets: 2) }),
      profile: profile(minutes: 10, locked: Set(ids)))
    XCTAssertFalse(result.isExecutable)
  }

  func testTimeBudgetAlsoHoldsWhenNoExercisesAreLocked() {
    let result = RoutineAdaptation.adapt(
      ProgramDay(name: "Source", exercises: ["barbell_bench", "bent_row", "back_squat"].map {
        entry($0, sets: 2)
      }), profile: profile(minutes: 10))
    if result.isExecutable {
      XCTAssertLessThanOrEqual(result.estimatedMinutes, 10)
    } else {
      XCTAssertFalse(result.blockers.isEmpty)
    }
  }

  func testEquipmentSwapsDoNotIntroduceDuplicateLoggerIdentities() throws {
    let original = try XCTUnwrap(ExerciseDB.find("barbell_bench"))
    let replacement = try XCTUnwrap(ExerciseDB.replacements(
      for: original, equipment: [.dumbbell], injuries: []).first)
    let result = RoutineAdaptation.adapt(
      ProgramDay(name: "Source", exercises: [entry(), entry(replacement.id)]),
      profile: profile(equipment: [.dumbbell]))
    if result.isExecutable {
      XCTAssertEqual(Set(result.adaptedDay.exerciseIDs).count, result.adaptedDay.exercises.count)
    } else {
      XCTAssertFalse(result.blockers.isEmpty)
    }
  }

  func testInvalidStoredPrescriptionCannotBecomeExecutable() {
    let malformed = ProgramDay(
      name: "Malformed", exercises: [entry(sets: -1, low: -8, high: -2, target: 99)])
    XCTAssertNil(RoutineAdaptation.plannedDay(malformed))
  }

  func testUnavailableInjurySubstitutionDoesNotKeepFlaggedLiftExecutable() {
    let result = RoutineAdaptation.adapt(
      ProgramDay(name: "Source", exercises: [entry()]),
      profile: profile(equipment: [.barbell], injuries: [.shoulder]))
    XCTAssertFalse(result.isExecutable)
  }

  func testWeeklyVolumeAffectsPrescriptionInsteadOfOnlyAddingWarning() throws {
    let result = RoutineAdaptation.adapt(
      ProgramDay(name: "Source", exercises: [entry(sets: 5)]), profile: profile(),
      weeklySetsByMuscle: [.chest: 18])
    if result.isExecutable {
      let maximum = try XCTUnwrap(VolumeLandmarks.base(for: .chest)).mrv
      XCTAssertLessThanOrEqual(result.adaptedDay.totalSets + 18, maximum)
    } else {
      XCTAssertFalse(result.blockers.isEmpty)
    }
  }

  func testAdaptedPrescriptionIsExecutableAndDeloadUsesExistingRules() throws {
    let source = ProgramDay(
      name: "Copied source", exercises: [entry("bent_row", sets: 3, low: 6, high: 8)])
    let adapted = try XCTUnwrap(RoutineAdaptation.plannedDay(source))
    XCTAssertEqual(adapted.exercises.map(\.exercise.id), ["bent_row"])
    XCTAssertEqual(adapted.exercises[0].sets, 3)
    XCTAssertEqual(adapted.exercises[0].repRange, 6...8)
    let result = RoutineAdaptation.adapt(source, profile: profile(), week: Mesocycle.deloadWeek)
    let deload = try XCTUnwrap(RoutineAdaptation.plannedDay(result.adaptedDay))
    XCTAssertEqual(deload.exercises.map(\.exercise.id), ["bent_row"])
    XCTAssertLessThan(deload.exercises[0].sets, 3)
    XCTAssertLessThanOrEqual(deload.exercises[0].targetRPE, 6)
  }
}
