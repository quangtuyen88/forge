import Foundation
import SwiftData
import XCTest
import ForgeCore
@testable import Forge

@MainActor
final class RoutineAdaptationServiceTests: XCTestCase {
  private var routine: ProgramDay {
    ProgramDay(name: "Copied routine", exercises: [
      ProgramExerciseEntry(
        exerciseID: "barbell_bench", sets: 3, repRangeLower: 8,
        repRangeUpper: 10, targetRPE: 8),
    ])
  }

  @discardableResult
  private func save(_ profile: UserProfile, _ context: ModelContext) throws -> UserProfile.SavedRoutine {
    try RoutineAdaptationService.saveRoutine(
      day: routine, name: "My routine", sourceKind: .history,
      sourceName: "My finished workout", profile: profile, context: context)
  }

  private func acceptedDay(_ profile: UserProfile, _ context: ModelContext) throws -> WeekPlanDay {
    let calendar = Calendar.current
    let today = calendar.startOfDay(for: .now)
    profile.mesoStart = today
    var plan = WeekPlanBuilder.plan(
      programWeek: 1, profile: profile.profileInput,
      constraints: profile.trainingConstraints, startingOn: today,
      enrollmentDate: today, calendar: calendar)
    plan.days = plan.days.enumerated().map { offset, built in
      var day = built
      day.date = calendar.date(byAdding: .day, value: offset, to: today) ?? today
      return day
    }
    profile.weekPlan = plan
    try context.save()
    return try XCTUnwrap(plan.days.first)
  }

  private func apply(_ day: WeekPlanDay, _ profile: UserProfile, _ context: ModelContext) throws {
    let preview = try RoutineAdaptationService.preview(day: routine, toDayID: day.id,
      profile: profile, sessions: context.fetch(FetchDescriptor<WorkoutSession>()))
    _ = try RoutineAdaptationService.apply(
      preview: preview, sourceName: "My routine", profile: profile, context: context)
  }

  func testRepeatedSaveDoesNotCreateDuplicateRoutineOrChangePlan() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    _ = try acceptedDay(profile, context)
    let previousPlan = profile.weekPlanJSON
    let first = try save(profile, context)
    let second = try save(profile, context)
    XCTAssertEqual(first.id, second.id)
    XCTAssertEqual(profile.routineLibrary.count, 1)
    XCTAssertEqual(profile.weekPlanJSON, previousPlan)
    XCTAssertTrue(profile.appliedRoutines.isEmpty)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<DecisionLogEntry>()), 0)
  }

  func testProfileSyncCannotOverwriteDeviceLocalRoutines() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    let profileSyncTimestamp = profile.updatedAt
    _ = try save(profile, context)
    XCTAssertEqual(profile.updatedAt, profileSyncTimestamp)
    try apply(day, profile, context)
    let library = profile.routineLibraryJSON
    let applied = profile.appliedRoutinesJSON

    XCTAssertNil(profile.syncData["routineLibraryJSON"])
    XCTAssertNil(profile.syncData["appliedRoutinesJSON"])
    UserProfile.apply([
      "goal": "strength",
      "routineLibraryJSON": "[]",
      "appliedRoutinesJSON": "[]",
    ], to: profile)
    XCTAssertEqual(profile.goal, "strength")
    XCTAssertEqual(profile.routineLibraryJSON, library)
    XCTAssertEqual(profile.appliedRoutinesJSON, applied)
  }

  func testSyncedAcceptedReplacementWithoutLocalPrescriptionCannotStartTemplate() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    XCTAssertFalse(RoutineAdaptationService.needsReview(day, profile: profile, sessions: []))
    try apply(day, profile, context)
    // The accepted week reaches another device, but the routine payload does not.
    profile.appliedRoutinesJSON = ""
    let syncedDay = try XCTUnwrap(profile.weekPlan?.days.first)
    XCTAssertTrue(RoutineAdaptationService.needsReview(syncedDay, profile: profile, sessions: []))
    XCTAssertNil(RoutineAdaptationService.currentDay(profile: profile, sessions: []))
  }

  func testSyncedApplicationMarkerBlocksSameIDsAndSameSetTotalWithoutPrescription() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    let generated = try XCTUnwrap(RoutineAdaptationService.generatedDay(day, profile: profile, sessions: []))
    XCTAssertEqual(day.exerciseIDs, generated.exercises.map(\.exercise.id))
    XCTAssertEqual(day.plannedSetCount, generated.exercises.reduce(0) { $0 + $1.sets })
    var plan = try XCTUnwrap(profile.weekPlan)
    plan.days[0].routineApplicationID = "remote-application-with-different-reps-or-effort"
    profile.weekPlan = plan
    XCTAssertTrue(RoutineAdaptationService.needsReview(plan.days[0], profile: profile, sessions: []))
    XCTAssertNil(RoutineAdaptationService.currentDay(profile: profile, sessions: []))
  }

  func testUnreadableAcceptedWeekCannotStartOrQuickLogGeneratedWorkout() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    _ = try acceptedDay(profile, context)
    profile.weekPlanJSON = "future-week-format"
    try context.save()
    XCTAssertTrue(RoutineAdaptationService.weekPlanUnreadable(profile))
    XCTAssertNil(RoutineAdaptationService.currentDay(profile: profile, sessions: []))
    XCTAssertThrowsError(try SetInserter.insert(exerciseID: "barbell_bench", weightKg: 60,
      reps: 8, rpe: nil, in: context)) { error in
      XCTAssertEqual(error as? SetInserter.Failure, .weekPlanUnreadable)
    }
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
  }

  func testUnreadableAcceptedWeekAllowsLoggingIntoReadableStartedWorkout() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    let planned = try XCTUnwrap(RoutineAdaptation.plannedDay(routine))
    let open = WorkoutSession(date: .now, dayName: day.sessionName, week: 1, completed: false)
    open.rememberPrescription(planned, planDayID: day.id)
    context.insert(open)
    profile.weekPlanJSON = "future-week-format"
    try context.save()

    XCTAssertNotNil(RoutineAdaptationService.currentDay(profile: profile, sessions: [open]))
    let logged = try SetInserter.insert(exerciseID: "barbell_bench", weightKg: 60,
      reps: 8, rpe: nil, in: context)
    XCTAssertEqual(logged.session?.persistentModelID, open.persistentModelID)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
  }

  func testUnreadableLibraryCannotReportSuccessfulSave() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    profile.routineLibraryJSON = "future-format-do-not-overwrite"
    try context.save()
    let updatedAt = profile.updatedAt
    XCTAssertThrowsError(try save(profile, context))
    XCTAssertEqual(profile.routineLibraryJSON, "future-format-do-not-overwrite")
    XCTAssertEqual(profile.updatedAt, updatedAt)
  }

  func testSaveDoesNotCommitUnrelatedDraftEdits() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    context.autosaveEnabled = false
    let profile = try JourneyTestStore.profile(in: context)
    let history = WorkoutSession(date: .now, dayName: "Original", week: 1, completed: true)
    history.notes = "Original note"
    context.insert(history)
    try context.save()
    history.notes = "Unsaved editing draft"
    _ = try save(profile, context)
    let observer = ModelContext(container)
    let persisted = try XCTUnwrap(observer.fetch(FetchDescriptor<WorkoutSession>()).first)
    XCTAssertEqual(persisted.notes, "Original note")
    XCTAssertEqual(history.notes, "Unsaved editing draft")
    XCTAssertEqual(try XCTUnwrap(observer.fetch(FetchDescriptor<UserProfile>()).first).routineLibrary.count, 1)
  }

  func testStartedSessionCannotBeReplacedEvenBeforeFirstSet() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    let started = WorkoutSession(
      date: .now, dayName: day.plannedSessionID ?? day.sessionName, week: 1, completed: false)
    context.insert(started)
    try context.save()
    let previousPlan = profile.weekPlanJSON
    XCTAssertThrowsError(try apply(day, profile, context))
    XCTAssertEqual(profile.weekPlanJSON, previousPlan)
    XCTAssertTrue(profile.appliedRoutines.isEmpty)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<DecisionLogEntry>()), 0)
  }

  func testUnreadableApplicationPayloadCannotPartiallyChangePlan() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    profile.appliedRoutinesJSON = "future-format-do-not-overwrite"
    try context.save()
    let previousPlan = profile.weekPlanJSON
    XCTAssertThrowsError(try apply(day, profile, context))
    XCTAssertEqual(profile.weekPlanJSON, previousPlan)
    XCTAssertEqual(profile.appliedRoutinesJSON, "future-format-do-not-overwrite")
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<DecisionLogEntry>()), 0)
  }

  func testRepeatedApplyDoesNotDuplicateDecisionAndMatchesPlanner() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    try apply(day, profile, context)
    try apply(day, profile, context)
    XCTAssertEqual(profile.appliedRoutines.count, 1)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<DecisionLogEntry>()), 1)
    let planned = try XCTUnwrap(RoutineAdaptationService.resolvedDay(day, profile: profile, sessions: []))
    XCTAssertEqual(planned.exercises.map(\.exercise.id), routine.exerciseIDs)
    XCTAssertEqual(planned.exercises.reduce(0) { $0 + $1.sets }, routine.totalSets)
  }

  func testNewTrainingBlockCannotReuseOldAppliedRoutine() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    try apply(day, profile, context)
    XCTAssertNotNil(RoutineAdaptationService.resolvedDay(day, profile: profile, sessions: []))
    profile.startNewBlock()
    XCTAssertNil(RoutineAdaptationService.resolvedDay(day, profile: profile, sessions: []))
  }

  func testApplicationDoesNotReplaceAnotherDayWithTheSameNameOrGeneratedWeeks() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let first = try acceptedDay(profile, context)
    var plan = try XCTUnwrap(profile.weekPlan)
    var second = first
    second.id = first.id + "-another"
    second.date = first.date.addingTimeInterval(86400)
    plan.days = [first, second]
    profile.weekPlan = plan
    try context.save()
    let generated = Program.week(1, profile: profile.profileInput)
    try apply(first, profile, context)
    XCTAssertNotNil(RoutineAdaptationService.resolvedDay(first, profile: profile, sessions: []))
    XCTAssertNil(RoutineAdaptationService.resolvedDay(second, profile: profile, sessions: []))
    XCTAssertEqual(Program.week(1, profile: profile.profileInput).map { $0.exercises.map(\.exercise.id) },
      generated.map { $0.exercises.map(\.exercise.id) })
  }

  func testMovingAppliedWorkoutToEmptyDayKeepsItsPrescription() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    var plan = try XCTUnwrap(profile.weekPlan)
    plan.days = [day]
    profile.weekPlan = plan
    try context.save()
    try apply(day, profile, context)
    plan = try XCTUnwrap(profile.weekPlan)
    XCTAssertTrue(plan.move(dayID: day.id, to: day.date.addingTimeInterval(86400)))
    profile.weekPlan = plan
    let moved = try XCTUnwrap(plan.days.first { $0.state == .planned })
    XCTAssertEqual(moved.routineApplicationID, plan.days.first { $0.id == day.id }?.routineApplicationID)
    XCTAssertNotNil(RoutineAdaptationService.resolvedDay(moved, profile: profile, sessions: []))
    XCTAssertFalse(RoutineAdaptationService.needsReview(moved, profile: profile, sessions: []))
  }

  func testMovingAppliedWorkoutToDifferentWeekRequiresReview() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    var plan = try XCTUnwrap(profile.weekPlan)
    plan.days = [day]
    profile.weekPlan = plan
    try context.save()
    try apply(day, profile, context)
    plan = try XCTUnwrap(profile.weekPlan)
    XCTAssertTrue(plan.move(dayID: day.id, to: day.date.addingTimeInterval(8 * 86400)))
    profile.weekPlan = plan
    let moved = try XCTUnwrap(plan.days.first { $0.state == .planned })
    XCTAssertNil(RoutineAdaptationService.resolvedDay(moved, profile: profile, sessions: []))
    XCTAssertTrue(RoutineAdaptationService.needsReview(moved, profile: profile, sessions: []))
  }

  func testReacceptingSameWeekRetiresPreviousApplication() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    try apply(day, profile, context)
    var plan = try XCTUnwrap(profile.weekPlan)
    plan.acceptanceID = UUID().uuidString
    profile.weekPlan = plan
    XCTAssertNil(RoutineAdaptationService.resolvedDay(day, profile: profile, sessions: []))
    XCTAssertTrue(RoutineAdaptationService.needsReview(day, profile: profile, sessions: []))
    XCTAssertNil(RoutineAdaptationService.currentDay(profile: profile, sessions: []))
  }

  func testUnreadableApplicationAndOpenSnapshotFailClosed() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    profile.appliedRoutinesJSON = "future-format"
    XCTAssertTrue(RoutineAdaptationService.needsReview(day, profile: profile, sessions: []))
    XCTAssertNil(RoutineAdaptationService.currentDay(profile: profile, sessions: []))
    let open = WorkoutSession(date: .now, dayName: day.sessionName, week: 1, completed: false)
    open.routinePrescriptionJSON = "future-format"
    XCTAssertTrue(RoutineAdaptationService.hasUnreadableOpenSnapshot([open]))
    XCTAssertNil(RoutineAdaptationService.currentDay(profile: profile, sessions: [open]))
  }

  func testQuickLogRefusesRoutineReviewWithoutCreatingSessionOrSet() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    try apply(day, profile, context)
    var plan = try XCTUnwrap(profile.weekPlan)
    plan.acceptanceID = UUID().uuidString
    profile.weekPlan = plan
    try context.save()
    XCTAssertThrowsError(try SetInserter.insert(exerciseID: "barbell_bench", weightKg: 60,
      reps: 8, rpe: 8, in: context)) { error in
      XCTAssertEqual(error as? SetInserter.Failure, .routineNeedsReview)
    }
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 0)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<LoggedSet>()), 0)
  }

  func testSessionBindingAndSyncCannotCompleteNewAcceptance() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    var plan = try XCTUnwrap(profile.weekPlan)
    plan.acceptanceID = UUID().uuidString
    profile.weekPlan = plan
    let session = WorkoutSession(date: .now, dayName: day.sessionName, week: 1, completed: false)
    session.plannedDayID = day.id
    session.plannedPlanID = plan.id
    session.plannedAcceptanceID = plan.acceptanceID
    let restored = WorkoutSession(date: .now, dayName: "", week: 1, completed: false)
    WorkoutSession.apply(session.syncData, to: restored)
    XCTAssertTrue(RoutineAdaptationService.canComplete(restored, dayID: day.id, in: plan))
    plan.acceptanceID = UUID().uuidString
    XCTAssertFalse(RoutineAdaptationService.canComplete(restored, dayID: day.id, in: plan))
    XCTAssertEqual(restored.plannedPlanID, session.plannedPlanID)
    XCTAssertEqual(restored.plannedAcceptanceID, session.plannedAcceptanceID)
  }

  func testStageChangeRequiresReviewBeforeStart() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    try apply(day, profile, context)
    XCTAssertNotNil(RoutineAdaptationService.currentDay(profile: profile, sessions: []))
    profile.mesoSessionOffset = profile.daysPerWeek
    XCTAssertTrue(RoutineAdaptationService.needsReview(day, profile: profile, sessions: []))
    XCTAssertNil(RoutineAdaptationService.currentDay(profile: profile, sessions: []))
  }

  func testSameWeekVolumeChangeRequiresFreshReview() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    try apply(day, profile, context)
    XCTAssertFalse(RoutineAdaptationService.needsReview(day, profile: profile, sessions: []))
    let history = WorkoutSession(date: .now, dayName: "Extra", week: 1, completed: true)
    history.heartRateSeen = true
    context.insert(history)
    let set = LoggedSet(exerciseID: "barbell_bench", setIndex: 0, weightKg: 60,
      reps: 8, rpe: 8, targetRPE: 8, loggedAt: .now, effortReported: true)
    set.session = history
    context.insert(set)
    try context.save()
    XCTAssertEqual(profile.currentWeek(sessions: [history]), 1)
    XCTAssertTrue(RoutineAdaptationService.needsReview(day, profile: profile, sessions: [history]))
    XCTAssertNil(RoutineAdaptationService.currentDay(profile: profile, sessions: [history]))
  }

  func testChangedTrainingDataRejectsFrozenPreviewWithoutPlanMutation() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    let preview = try RoutineAdaptationService.preview(day: routine, toDayID: day.id,
      profile: profile, sessions: [])
    let history = WorkoutSession(date: .now.addingTimeInterval(-86400), dayName: "New history", week: 1, completed: true)
    context.insert(history)
    try context.save()
    let original = profile.weekPlanJSON
    XCTAssertThrowsError(try RoutineAdaptationService.apply(preview: preview, sourceName: "Routine",
      profile: profile, context: context)) { error in
      XCTAssertEqual(error as? RoutineAdaptationService.Failure, .stalePreview)
    }
    XCTAssertEqual(profile.weekPlanJSON, original)
    XCTAssertTrue(profile.appliedRoutines.isEmpty)
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<DecisionLogEntry>()), 0)
  }

  func testChangedApplicationRejectsFrozenPreviewEvenWhenSetCountsMatch() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    try apply(day, profile, context)
    func variant(_ targetRPE: Double) -> ProgramDay {
      ProgramDay(name: "Alternate", exercises: [
        ProgramExerciseEntry(exerciseID: "barbell_bench", sets: 3,
          repRangeLower: 8, repRangeUpper: 10, targetRPE: targetRPE),
      ])
    }
    let pending = try RoutineAdaptationService.preview(day: variant(7), toDayID: day.id,
      profile: profile, sessions: [])
    let other = try RoutineAdaptationService.preview(day: variant(6), toDayID: day.id,
      profile: profile, sessions: [])
    try RoutineAdaptationService.apply(preview: other, sourceName: "Other",
      profile: profile, context: context)
    let applied = profile.appliedRoutinesJSON
    XCTAssertThrowsError(try RoutineAdaptationService.apply(preview: pending,
      sourceName: "Pending", profile: profile, context: context)) { error in
      XCTAssertEqual(error as? RoutineAdaptationService.Failure, .stalePreview)
    }
    XCTAssertEqual(profile.appliedRoutinesJSON, applied)
  }

  func testStartedPrescriptionSurvivesPlanCompletionAndConstraintChanges() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let day = try acceptedDay(profile, context)
    try apply(day, profile, context)
    let prescription = try XCTUnwrap(RoutineAdaptationService.resolvedDay(day, profile: profile, sessions: []))
    let session = WorkoutSession(date: .now, dayName: prescription.name, week: 1, completed: false)
    session.rememberPrescription(prescription, planDayID: day.id)
    context.insert(session)
    profile.equipment = ["dumbbell"]
    XCTAssertNil(RoutineAdaptationService.resolvedDay(day, profile: profile, sessions: [session]))
    XCTAssertEqual(RoutineAdaptationService.currentDay(profile: profile, sessions: [session])?.exercises.map(\.exercise.id),
      prescription.exercises.map(\.exercise.id))
    session.completed = true
    try context.save()
    let observer = ModelContext(container)
    let persisted = try XCTUnwrap(observer.fetch(FetchDescriptor<WorkoutSession>()).first)
    XCTAssertEqual(persisted.routinePrescription?.exerciseIDs, prescription.exercises.map(\.exercise.id))
    XCTAssertEqual(persisted.plannedDayID, day.id)
  }

  func testSavedRoutineSurvivesOfflineStoreReopen() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "routine.store")
    let id: String
    do {
      let container = try JourneyTestStore.onDisk(at: url)
      let context = ModelContext(container)
      let profile = try JourneyTestStore.profile(in: context)
      id = try save(profile, context).id
    }
    let reopened = try JourneyTestStore.onDisk(at: url)
    let observer = ModelContext(reopened)
    let profile = try XCTUnwrap(observer.fetch(FetchDescriptor<UserProfile>()).first)
    XCTAssertEqual(profile.routineLibrary.map(\.id), [id])
    XCTAssertEqual(profile.routineLibrary.first?.day.exercises, routine.exercises)
    XCTAssertEqual(profile.routineLibrary.first?.day.name, "My routine")
    XCTAssertNil(profile.routineLibrary.first?.sourceName)
    XCTAssertNil(profile.weekPlan)
  }

  func testLoadPreviewDoesNotReuseAnIncompatibleEquipmentBaseline() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    profile.equipmentPassport = EquipmentPassport(instances: [
      EquipmentInstance(
        id: "new-bar", name: "Current bar", kind: .barbell, gymProfileID: nil,
        loadModel: .barbellTotalKG(id: "new-model", now: .now),
        createdAt: .now, updatedAt: .now),
    ])
    profile.bindEquipment(exerciseID: "barbell_bench", variant: nil, instanceID: "new-bar")
    let history = WorkoutSession(date: .now, dayName: "History", week: 1, completed: true)
    history.heartRateSeen = true
    context.insert(history)
    let descriptor = LoadDescriptor(
      originalValue: "80", originalUnit: "kg", domain: .externalMass,
      convention: .totalIncludingBar, equipmentInstanceID: "old-bar", loadModelRevision: 1,
      side: .bilateral, normalizationStatus: .verified)
    let set = LoggedSet(
      exerciseID: "barbell_bench", setIndex: 0, weightKg: 80, reps: 8,
      rpe: 7, targetRPE: 8, loggedAt: .now, loadDescriptor: descriptor, effortReported: true)
    set.session = history
    context.insert(set)
    try context.save()
    let estimate = RoutineAdaptationService.loadEstimate(
      for: routine.exercises[0], resolvedID: "barbell_bench", profile: profile, sessions: [history])
    XCTAssertNotEqual(estimate?.basis, .history)
    XCTAssertNotEqual(estimate?.basis, .heldNoEffort)
  }

  func testUnreportedEffortStaysUnknownAndDoesNotIncreaseLoad() throws {
    let container = try JourneyTestStore.inMemory()
    let context = ModelContext(container)
    let profile = try JourneyTestStore.profile(in: context)
    let history = WorkoutSession(date: .now, dayName: "History", week: 1, completed: true)
    history.heartRateSeen = true
    context.insert(history)
    let descriptor = profile.equipmentLoadDescriptor(
      exerciseID: "barbell_bench", variant: nil, displayValue: "60", displayUnit: "kg",
      weightKg: 60, side: .bilateral)
    let set = LoggedSet(
      exerciseID: "barbell_bench", setIndex: 0, weightKg: 60, reps: 10,
      rpe: 8, targetRPE: 8, loggedAt: .now, loadDescriptor: descriptor, effortReported: false)
    set.session = history
    context.insert(set)
    try context.save()
    XCTAssertEqual(history.sets.count, 1)
    XCTAssertTrue(history.verified)
    XCTAssertEqual(history.analysisSets(.progression).count, 1)
    XCTAssertEqual(lastSets("barbell_bench", in: [history], profile: profile).count, 1,
      "A compatible but effort-unknown set must remain an eligible load baseline")
    let estimate = try XCTUnwrap(RoutineAdaptationService.loadEstimate(
      for: routine.exercises[0], resolvedID: "barbell_bench", profile: profile, sessions: [history]))
    XCTAssertEqual(estimate.basis, .heldNoEffort)
    XCTAssertEqual(estimate.kg, 60)
    XCTAssertNil(set.reportedRPE)
  }

  func testRealReadOnlyStoreFailureLeavesLibraryAndProfileUntouched() throws {
    let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "read-only.store")
    do {
      let writable = try JourneyTestStore.onDisk(at: url)
      let context = ModelContext(writable)
      try JourneyTestStore.profile(in: context)
    }
    let readOnly = try JourneyTestStore.container(ModelConfiguration(url: url, allowsSave: false))
    let context = ModelContext(readOnly)
    context.autosaveEnabled = false
    let profile = try XCTUnwrap(context.fetch(FetchDescriptor<UserProfile>()).first)
    let originalJSON = profile.routineLibraryJSON
    let updatedAt = profile.updatedAt
    XCTAssertThrowsError(try save(profile, context))
    XCTAssertEqual(profile.routineLibraryJSON, originalJSON)
    XCTAssertEqual(profile.updatedAt, updatedAt)
    let observer = ModelContext(readOnly)
    XCTAssertEqual(
      try XCTUnwrap(observer.fetch(FetchDescriptor<UserProfile>()).first).routineLibraryJSON,
      originalJSON)
  }
}
