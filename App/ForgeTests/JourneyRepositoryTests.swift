import ForgeCore
import Foundation
import SwiftData
import XCTest

@testable import Forge

/// Native, in-memory integration tests for the Journey projection.
///
/// Every assertion here is about **records**, not about view code: which row the repository
/// creates, which row it must not touch, and which identity survives an edit. The store is
/// in-memory so a failure is never a leftover on disk, and the calendar is fixed so month
/// boundaries do not move with the machine.
@MainActor
final class JourneyRepositoryTests: XCTestCase {

  // MARK: 1 — a completed workout projects once, and keeps its identity when it is edited

  func testCompletedWorkoutProjectsOnceAndKeepsIdentityWhenEdited() throws {
    // The container is bound to a local on purpose: `ModelContext` does not keep its store alive,
    // so an unretained container would let every later fetch trap inside SwiftData.
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let repository = JourneyTestStore.repository(
      context: context, profile: try JourneyTestStore.profile(in: context))

    let session = WorkoutSession(
      date: JourneyTestStore.date(2025, 6, 10), dayName: "Push A", week: 3, completed: true)
    context.insert(session)
    try context.save()

    let june = JourneyMonth(year: 2025, month: 6)
    let firstPage = try repository.page(month: june)
    XCTAssertEqual(firstPage.events.count, 1, "one session must project exactly one card")
    let original = try XCTUnwrap(firstPage.events.first)
    XCTAssertEqual(original.kind, .workout)
    XCTAssertEqual(original.title, "Push A")
    XCTAssertEqual(original.detail, "Week 3")

    // `workoutEvents` mints the canonical id on first read and saves once; re-reading the month
    // must not mint a second one, or the card would change identity on every refresh.
    XCTAssertFalse(session.remoteID.isEmpty)
    XCTAssertEqual(original.sourceID, session.remoteID)
    XCTAssertEqual(
      original.id, JourneyEventID.workout(owner: repository.ownerID, sessionID: session.remoteID))
    XCTAssertEqual(try repository.page(month: june).events.count, 1)

    // Editing in place: the id is derived from `ownerID + remoteID` only, so the title and the
    // day may change while the card stays the same card.
    session.dayName = "Push B"
    session.week = 4
    session.date = JourneyTestStore.date(2025, 6, 18)
    try context.save()

    let editedPage = try repository.page(month: june)
    XCTAssertEqual(editedPage.events.count, 1, "an edit must update the card, not add a second")
    let edited = try XCTUnwrap(editedPage.events.first)
    XCTAssertEqual(edited.id, original.id)
    XCTAssertEqual(edited.title, "Push B")
    XCTAssertEqual(edited.detail, "Week 4")
    XCTAssertEqual(edited.day, JourneyTestStore.calendar.startOfDay(for: session.date))

    // Moving across a month boundary moves the one card; the old month goes empty.
    session.date = JourneyTestStore.date(2025, 7, 2)
    try context.save()

    XCTAssertTrue(try repository.page(month: june).isEmpty)
    let julyPage = try repository.page(month: JourneyMonth(year: 2025, month: 7))
    XCTAssertEqual(julyPage.events.count, 1)
    XCTAssertEqual(try XCTUnwrap(julyPage.events.first).id, original.id)
    XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
  }

  // MARK: 2 — hiding, hiding again and restoring never mutate the source

  func testHidingAndRestoringNeverMutatesOrDeletesTheWorkoutSession() throws {
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let repository = JourneyTestStore.repository(
      context: context, profile: try JourneyTestStore.profile(in: context))

    let session = WorkoutSession(
      date: JourneyTestStore.date(2025, 6, 10), dayName: "Lower A", week: 2, completed: true)
    context.insert(session)
    try context.save()

    let june = JourneyMonth(year: 2025, month: 6)
    let card = try XCTUnwrap(try repository.page(month: june).events.first)

    // Snapshot taken *after* the first projection, so the repository's own one-time id minting
    // cannot be mistaken for a mutation caused by hiding.
    let before = (
      date: session.date, dayName: session.dayName, week: session.week,
      completed: session.completed,
      tombstoned: session.tombstoned, updatedAt: session.updatedAt, remoteID: session.remoteID,
      sets: session.sets.count
    )

    try repository.hide(card.id)

    XCTAssertTrue(try repository.page(month: june).isEmpty, "a hidden card leaves the page")
    let afterHide = try XCTUnwrap(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
    XCTAssertEqual(afterHide.date, before.date)
    XCTAssertEqual(afterHide.dayName, before.dayName)
    XCTAssertEqual(afterHide.week, before.week)
    XCTAssertEqual(afterHide.completed, before.completed)
    XCTAssertEqual(afterHide.tombstoned, before.tombstoned)
    XCTAssertEqual(afterHide.updatedAt, before.updatedAt, "hiding is not a source write")
    XCTAssertEqual(afterHide.remoteID, before.remoteID)
    XCTAssertEqual(afterHide.sets.count, before.sets)
    XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)

    // The override resolves back to the live source, so the Hidden-items sheet can show it.
    let hidden = repository.hiddenItems()
    XCTAssertEqual(hidden.map(\.id), [card.id])
    XCTAssertTrue(try XCTUnwrap(hidden.first).isHidden)

    // A second hide updates the single override row (revision 1 -> 2) instead of inserting another.
    try repository.hide(card.id)
    var overrides = try context.fetch(FetchDescriptor<JourneyVisibilityOverride>())
    XCTAssertEqual(overrides.count, 1, "the unique eventID column is what prevents duplicates")
    XCTAssertEqual(try XCTUnwrap(overrides.first).revision, 2)
    XCTAssertTrue(try XCTUnwrap(overrides.first).hidden)

    // Restoring keeps a `hidden == false` tombstone rather than deleting the row.
    try repository.restore(card.id)
    overrides = try context.fetch(FetchDescriptor<JourneyVisibilityOverride>())
    XCTAssertEqual(overrides.count, 1)
    XCTAssertFalse(try XCTUnwrap(overrides.first).hidden)
    XCTAssertEqual(try XCTUnwrap(overrides.first).revision, 3)

    XCTAssertEqual(try repository.page(month: june).events.count, 1)
    XCTAssertTrue(repository.hiddenItems().isEmpty)

    let afterRestore = try XCTUnwrap(try context.fetch(FetchDescriptor<WorkoutSession>()).first)
    XCTAssertEqual(afterRestore.date, before.date)
    XCTAssertEqual(afterRestore.dayName, before.dayName)
    XCTAssertEqual(afterRestore.tombstoned, false)
    XCTAssertEqual(afterRestore.updatedAt, before.updatedAt)
    XCTAssertEqual(try context.fetch(FetchDescriptor<WorkoutSession>()).count, 1)
  }

  // MARK: 3 — foreign-owner and unresolvable ids are refused

  func testForeignOwnerEventIDsAreRejectedByHideAndRestore() throws {
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let repository = JourneyTestStore.repository(
      context: context, profile: try JourneyTestStore.profile(in: context))

    let session = WorkoutSession(
      date: JourneyTestStore.date(2025, 6, 10), dayName: "Pull A", week: 1, completed: true)
    context.insert(session)
    try context.save()

    let card = try XCTUnwrap(
      try repository.page(month: JourneyMonth(year: 2025, month: 6)).events.first)

    // Same source record, different owner: `setHidden` checks the owner before it resolves the
    // source, so even a live workout cannot be hidden under someone else's id.
    let foreign = JourneyEventID.make(
      owner: "00000000-0000-0000-0000-0000000000ZZ", kind: .workout, sourceID: card.sourceID)
    XCTAssertThrowsError(try repository.hide(foreign)) { error in
      XCTAssertEqual(error as? JourneyRepositoryError, .foreignOwner)
    }
    XCTAssertThrowsError(try repository.restore(foreign)) { error in
      XCTAssertEqual(error as? JourneyRepositoryError, .foreignOwner)
    }
    XCTAssertTrue(try context.fetch(FetchDescriptor<JourneyVisibilityOverride>()).isEmpty)
    XCTAssertTrue(session.tombstoned == false && session.completed)

    // Right owner, no such source: nothing to hide.
    let ghost = JourneyEventID.make(
      owner: repository.ownerID, kind: .workout, sourceID: "no-such-session")
    XCTAssertThrowsError(try repository.hide(ghost)) { error in
      XCTAssertEqual(error as? JourneyRepositoryError, .notFound)
    }

    // A raw value with no parseable components is refused rather than stored as an opaque string.
    XCTAssertThrowsError(try repository.hide(JourneyEventID(rawValue: "not-a-journey-id"))) {
      error in
      XCTAssertEqual(error as? JourneyRepositoryError, .notFound)
    }
    XCTAssertTrue(try context.fetch(FetchDescriptor<JourneyVisibilityOverride>()).isEmpty)
  }

  // MARK: 4 — reflection write path: idempotent create, guarded update, tombstone delete

  func testReflectionCreateIsIdempotentByRequestID() throws {
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let repository = JourneyTestStore.repository(
      context: context, profile: try JourneyTestStore.profile(in: context))

    let session = WorkoutSession(
      date: JourneyTestStore.date(2025, 6, 5), dayName: "Push A", week: 1, completed: true)
    context.insert(session)
    try context.save()
    let sessionID = try XCTUnwrap(
      try repository.page(month: JourneyMonth(year: 2025, month: 6)).events.first
    ).sourceID

    let day = JourneyTestStore.date(2025, 6, 5)
    let draft = JourneyReflectionDraft(
      text: "  Felt strong today  ",
      day: day,
      source: JourneySourceReference(kind: .workout, sourceID: sessionID),
      clientRequestID: "req-1")

    let first = try repository.createReflection(draft)
    XCTAssertEqual(first.kind, .reflection)
    XCTAssertEqual(first.title, "Note")
    XCTAssertEqual(first.detail, "Felt strong today", "text is trimmed at write time")
    XCTAssertEqual(first.day, JourneyTestStore.calendar.startOfDay(for: day))
    XCTAssertEqual(
      first.sourceID, try XCTUnwrap(repository.reflection(for: first.id)).reflectionID.uuidString)

    let stored = try context.fetch(FetchDescriptor<JourneyReflection>())
    XCTAssertEqual(stored.count, 1)
    XCTAssertEqual(try XCTUnwrap(stored.first).revision, 1)
    XCTAssertEqual(try XCTUnwrap(stored.first).clientRequestID, "req-1")
    XCTAssertEqual(try XCTUnwrap(stored.first).ownerID, repository.ownerID)

    // A retried save (same request id, different text) returns the first record unchanged: the
    // idempotency key is never part of the event identity, so it cannot mint a second note.
    let retry = try repository.createReflection(
      JourneyReflectionDraft(text: "second attempt", day: day, clientRequestID: "req-1"))
    XCTAssertEqual(retry.id, first.id)
    XCTAssertEqual(try context.fetch(FetchDescriptor<JourneyReflection>()).count, 1)
    XCTAssertEqual(try XCTUnwrap(repository.reflection(for: first.id)).text, "Felt strong today")

    XCTAssertEqual(
      try repository.page(month: JourneyMonth(year: 2025, month: 6)).events.filter {
        $0.kind == .reflection
      }.count,
      1)
  }

  func testReflectionUpdateRejectsStaleRevisionAndDeleteLeavesATombstone() throws {
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let repository = JourneyTestStore.repository(
      context: context, profile: try JourneyTestStore.profile(in: context))

    let day = JourneyTestStore.date(2025, 6, 5)
    let created = try repository.createReflection(
      JourneyReflectionDraft(text: "first", day: day, clientRequestID: "req-1"))
    let reflection = try XCTUnwrap(repository.reflection(for: created.id))
    let id = reflection.reflectionID
    XCTAssertEqual(reflection.revision, 1)

    // A write built on a stale read is refused, and the row is left exactly as it was.
    XCTAssertThrowsError(
      try repository.updateReflection(
        id: id, draft: JourneyReflectionDraft(text: "clobbered", day: day), expectedRevision: 7)
    ) { error in
      XCTAssertEqual(error as? JourneyRepositoryError, .revisionConflict(expected: 7, actual: 1))
    }
    XCTAssertEqual(try XCTUnwrap(repository.reflection(id: id)).text, "first")
    XCTAssertEqual(try XCTUnwrap(repository.reflection(id: id)).revision, 1)

    // A matching revision succeeds and the identity does not move, even though the day changes.
    let moved = JourneyTestStore.date(2025, 6, 9)
    let updated = try repository.updateReflection(
      id: id, draft: JourneyReflectionDraft(text: "second", day: moved), expectedRevision: 1)
    XCTAssertEqual(updated.id, created.id)
    XCTAssertEqual(updated.day, JourneyTestStore.calendar.startOfDay(for: moved))
    let afterUpdate = try XCTUnwrap(repository.reflection(id: id))
    XCTAssertEqual(afterUpdate.text, "second")
    XCTAssertEqual(afterUpdate.revision, 2)
    XCTAssertFalse(updated.isHidden)

    // Delete is a tombstone: the active lookup stops resolving it, while a fresh context proves
    // the persisted row remains flagged for idempotency checks.
    try repository.deleteReflection(id: id, expectedRevision: 2)
    XCTAssertNil(repository.reflection(id: id))
    let verificationContext = ModelContext(container)
    let tombstoneCount = try verificationContext.fetchCount(
      FetchDescriptor<JourneyReflection>(
        predicate: #Predicate { $0.reflectionID == id && $0.tombstoned == true }))
    XCTAssertEqual(tombstoneCount, 1)
    let tombstone = try verificationContext.fetch(
      FetchDescriptor<JourneyReflection>(
        predicate: #Predicate { $0.reflectionID == id && $0.tombstoned == true }))
    XCTAssertTrue(try XCTUnwrap(tombstone.first).tombstoned)
    XCTAssertTrue(try XCTUnwrap(tombstone.first).text.isEmpty)
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<JourneyReflection>()).count, 1,
      "the row is flagged, not removed")

    XCTAssertTrue(
      try repository.page(month: JourneyMonth(year: 2025, month: 6)).events
        .filter { $0.kind == .reflection }.isEmpty)
    XCTAssertNil(repository.reflection(for: created.id), "a deleted note resolves to no event")

    // The retry that would otherwise resurrect it is refused by the same request id.
    XCTAssertThrowsError(
      try repository.createReflection(
        JourneyReflectionDraft(text: "third", day: day, clientRequestID: "req-1"))
    ) { error in
      XCTAssertEqual(error as? JourneyRepositoryError, .requestAlreadyDeleted)
    }
    XCTAssertEqual(try context.fetch(FetchDescriptor<JourneyReflection>()).count, 1)

    XCTAssertThrowsError(try repository.deleteReflection(id: id)) { error in
      XCTAssertEqual(error as? JourneyRepositoryError, .notFound)
    }
  }

  // MARK: 5 — the card is derived, so deleting the source removes it

  func testDeletingTheSourceRemovesTheDerivedCard() throws {
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let repository = JourneyTestStore.repository(
      context: context, profile: try JourneyTestStore.profile(in: context))

    let session = WorkoutSession(
      date: JourneyTestStore.date(2025, 6, 10), dayName: "Push A", week: 1, completed: true)
    context.insert(session)
    try context.save()

    let june = JourneyMonth(year: 2025, month: 6)
    let card = try XCTUnwrap(try repository.page(month: june).events.first)
    let sourceID = card.sourceID
    let reference = card.sourceReference
    XCTAssertTrue(repository.sourceExists(reference))

    // Hide it first, so the override outlives the source and the tombstone can be checked.
    try repository.hide(card.id)
    XCTAssertEqual(repository.hiddenItems().count, 1)

    // Soft delete: the card disappears even though the row is still there.
    session.tombstoned = true
    try context.save()
    XCTAssertTrue(session.tombstoned)
    XCTAssertTrue(try repository.page(month: june).isEmpty)
    XCTAssertNil(repository.resolveEvent(kind: .workout, sourceID: sourceID))
    XCTAssertFalse(repository.sourceExists(reference))

    // Hard delete: same outcome, and the stored override is now unresolvable rather than dangling.
    session.tombstoned = false
    try context.save()
    try repository.restore(card.id)
    XCTAssertEqual(try repository.page(month: june).events.count, 1)

    context.delete(session)
    try context.save()
    XCTAssertTrue(try repository.page(month: june).events.isEmpty)
    XCTAssertNil(repository.resolveEvent(kind: .workout, sourceID: sourceID))
    XCTAssertFalse(repository.sourceExists(reference))
    XCTAssertTrue(
      repository.hiddenItems().isEmpty,
      "a hidden card whose source is gone is dropped from the sheet")
    XCTAssertEqual(
      try context.fetch(FetchDescriptor<JourneyVisibilityOverride>()).count, 1,
      "the override row itself is left alone")
  }

  // MARK: 6 — an unsupported decision type must not determine coverage

  func testUnsupportedDecisionTypesDoNotDetermineEarliestOrLatestCoverage() throws {
    // The policy is default-deny, so an unmapped type added by a future build is absent rather
    // than mis-labelled as a program change.
    XCTAssertTrue(JourneyProgramChangePolicy.accepts("load_change"))
    XCTAssertTrue(JourneyProgramChangePolicy.accepts("  LOAD_CHANGE  "))
    XCTAssertFalse(JourneyProgramChangePolicy.accepts(""))
    XCTAssertFalse(JourneyProgramChangePolicy.accepts("   "))
    for excluded in [
      "experiment", "experiment_result", "constraints", "equipmentPassport",
      "goal_milestone", "goal_record", "ai_suggestion",
    ] {
      XCTAssertFalse(
        JourneyProgramChangePolicy.accepts(excluded), "\(excluded) is not a program change")
    }

    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let repository = JourneyTestStore.repository(
      context: context, profile: try JourneyTestStore.profile(in: context))

    func decision(_ type: String, at date: Date) -> DecisionLogEntry {
      DecisionLogEntry(
        DecisionRecord(
          id: "\(type)-\(Int(date.timeIntervalSince1970))",
          date: date,
          type: type,
          exerciseID: "bench",
          muscle: nil,
          fromValue: 80,
          toValue: 82.5,
          reasonCodes: ["completed_all_sets"],
          evidence: ["80 kg x 8 @ 7.5"],
          humanSummary: "Load up"))
    }

    // Two unsupported rows bracket the store in time; one supported row sits in June 2025.
    let oldest = decision("experiment", at: JourneyTestStore.date(2020, 1, 15))
    let newest = decision("goal_milestone", at: JourneyTestStore.date(2030, 12, 1))
    let supported = decision("load_change", at: JourneyTestStore.date(2025, 6, 3))
    for entry in [oldest, newest, supported] { context.insert(entry) }
    try context.save()

    XCTAssertEqual(repository.earliestMonth, JourneyMonth(year: 2025, month: 6))
    XCTAssertEqual(repository.latestMonth, JourneyMonth(year: 2025, month: 6))

    XCTAssertFalse(repository.hasContent(in: JourneyMonth(year: 2020, month: 1)))
    XCTAssertFalse(repository.hasContent(in: JourneyMonth(year: 2030, month: 12)))
    XCTAssertTrue(repository.hasContent(in: JourneyMonth(year: 2025, month: 6)))
    XCTAssertEqual(repository.coveredMonths(), [JourneyMonth(year: 2025, month: 6)])

    // The unsupported rows produce no cards either.
    XCTAssertTrue(try repository.page(month: JourneyMonth(year: 2020, month: 1)).isEmpty)
    XCTAssertTrue(try repository.page(month: JourneyMonth(year: 2030, month: 12)).isEmpty)
    let juneEvents = try repository.page(month: JourneyMonth(year: 2025, month: 6)).events
    XCTAssertEqual(juneEvents.map(\.kind), [.programChange])
    XCTAssertEqual(try XCTUnwrap(juneEvents.first).title, "Load changed")

    // A store whose only rows are unsupported decisions has no coverage at all.
    let lonelyContainer = try JourneyTestStore.inMemory()
    let lonelyContext = lonelyContainer.mainContext
    let lonely = JourneyTestStore.repository(
      context: lonelyContext, profile: try JourneyTestStore.profile(in: lonelyContext))
    lonelyContext.insert(decision("experiment_result", at: JourneyTestStore.date(2021, 3, 4)))
    try lonelyContext.save()
    XCTAssertNil(lonely.earliestMonth)
    XCTAssertNil(lonely.latestMonth)
    XCTAssertEqual(lonely.coveredMonths(), [])
    XCTAssertFalse(lonely.hasContent(in: JourneyMonth(year: 2021, month: 3)))
  }

  // MARK: 7 — local persistence records, and a reopened container still has them

  func testJourneyModelsAreLocalRecordsAndSurviveAContainerReopen() throws {
    // `SyncEngine` is an explicit allowlist of `SyncModel` conformers (`App/Forge/SyncEngine.swift:111-135`
    // names each type by hand) and `SyncModel` requires a canonical `remoteID`. Read the schema to
    // prove the Journey records cannot satisfy it: every synced model carries `remoteID`,
    // no Journey model does.
    let journeyLocalTypes: [any PersistentModel.Type] = [
      JourneyReflection.self, JourneyVisibilityOverride.self, JourneyPrivateProfile.self,
    ]
    for type in journeyLocalTypes {
      let names = JourneyTestStore.attributeNames(of: type)
      XCTAssertFalse(names.contains("remoteID"), "\(type) must stay device-local")
      XCTAssertFalse(names.contains("syncData"), "\(type) must not carry a sync payload")
      XCTAssertTrue(names.contains("updatedAt"))
    }
    XCTAssertTrue(JourneyTestStore.attributeNames(of: WorkoutSession.self).contains("remoteID"))
    XCTAssertTrue(JourneyTestStore.attributeNames(of: BodyMeasurement.self).contains("remoteID"))

    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("forge-journey-\(UUID().uuidString).store")
    defer { try? FileManager.default.removeItem(at: url) }

    let day = JourneyTestStore.date(2025, 6, 5)
    let reflectionID: UUID
    let sessionID = "session-1"
    let trainingStart = JourneyTestStore.date(2025, 1, 6)

    // Scope 1 — write, then drop every reference so the store is closed.
    do {
      let container = try JourneyTestStore.onDisk(at: url)
      let context = container.mainContext
      let repository = JourneyTestStore.repository(
        context: context, profile: try JourneyTestStore.profile(in: context))

      let session = WorkoutSession(date: day, dayName: "Push A", week: 1, completed: true)
      session.remoteID = sessionID
      context.insert(session)

      let created = try repository.createReflection(
        JourneyReflectionDraft(
          text: "Squat depth feels better",
          day: day,
          source: JourneySourceReference(kind: .workout, sourceID: sessionID),
          clientRequestID: "req-persist"))
      reflectionID = try XCTUnwrap(repository.reflection(for: created.id)).reflectionID
      try repository.hide(created.id)

      let card = try XCTUnwrap(
        try repository.page(month: JourneyMonth(year: 2025, month: 6)).events
          .first { $0.kind == .workout })
      try repository.hide(card.id)

      try repository.savePrivateProfile(displayName: "Tuyen", trainingStartDate: trainingStart)

      // Nothing here is synced, so a round trip through JSON must be impossible by construction:
      // the synced type strings used by `SyncEngine.apply` are the only ones it knows.
      XCTAssertEqual(try context.fetch(FetchDescriptor<JourneyReflection>()).count, 1)
      XCTAssertEqual(try context.fetch(FetchDescriptor<JourneyVisibilityOverride>()).count, 2)
      XCTAssertEqual(try context.fetch(FetchDescriptor<JourneyPrivateProfile>()).count, 1)
      try context.save()
    }

    // Scope 2 — reopen the same file. Registration in the container is what makes them persist.
    let reopened = try JourneyTestStore.onDisk(at: url)
    let context = reopened.mainContext
    let profile = try XCTUnwrap(try context.fetch(FetchDescriptor<UserProfile>()).first)

    let notes = try context.fetch(FetchDescriptor<JourneyReflection>())
    XCTAssertEqual(notes.count, 1)
    let note = try XCTUnwrap(notes.first)
    XCTAssertEqual(note.reflectionID, reflectionID)
    XCTAssertEqual(note.text, "Squat depth feels better")
    XCTAssertEqual(note.day, JourneyTestStore.calendar.startOfDay(for: day))
    XCTAssertEqual(note.sourceKind, JourneySourceKind.workout.rawValue)
    XCTAssertEqual(note.sourceID, sessionID)
    XCTAssertEqual(note.clientRequestID, "req-persist")
    XCTAssertEqual(note.revision, 1)
    XCTAssertFalse(note.tombstoned)

    let overrides = try context.fetch(FetchDescriptor<JourneyVisibilityOverride>())
    XCTAssertEqual(overrides.count, 2)
    XCTAssertTrue(overrides.allSatisfy(\.hidden))
    XCTAssertTrue(overrides.allSatisfy { $0.ownerID == note.ownerID })

    let privateProfile = try XCTUnwrap(
      try context.fetch(FetchDescriptor<JourneyPrivateProfile>()).first)
    XCTAssertEqual(privateProfile.displayName, "Tuyen")
    XCTAssertEqual(
      privateProfile.trainingStartDate, JourneyTestStore.calendar.startOfDay(for: trainingStart))
    XCTAssertEqual(privateProfile.revision, 1)

    // The reopened repository resolves the same owner and the same two hidden cards.
    let repository = JourneyTestStore.repository(context: context, profile: profile)
    XCTAssertEqual(repository.ownerID, note.ownerID)
    XCTAssertEqual(Set(repository.hiddenItems().map(\.id.rawValue)), Set(overrides.map(\.eventID)))
    XCTAssertTrue(try repository.page(month: JourneyMonth(year: 2025, month: 6)).isEmpty)
  }

  func testDeletedRequestRemainsATombstoneAfterDiskReopen() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("forge-journey-tombstone-(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("journey.store")
    let day = JourneyTestStore.date(2025, 6, 5)

    do {
      let container = try JourneyTestStore.onDisk(at: url)
      let context = container.mainContext
      let repository = JourneyTestStore.repository(
        context: context, profile: try JourneyTestStore.profile(in: context))
      let event = try repository.createReflection(
        JourneyReflectionDraft(text: "original", day: day, clientRequestID: "reopen-request"))
      let id = try XCTUnwrap(repository.reflection(for: event.id)).reflectionID
      try repository.deleteReflection(id: id, expectedRevision: 1)
      XCTAssertNil(repository.reflection(id: id))
    }

    do {
      let container = try JourneyTestStore.onDisk(at: url)
      let context = container.mainContext
      let profile = try XCTUnwrap(try context.fetch(FetchDescriptor<UserProfile>()).first)
      let repository = JourneyTestStore.repository(context: context, profile: profile)

      XCTAssertThrowsError(
        try repository.createReflection(
          JourneyReflectionDraft(
            text: "changed retry", day: day, clientRequestID: "reopen-request"))
      ) { error in
        XCTAssertEqual(error as? JourneyRepositoryError, .requestAlreadyDeleted)
      }

      let owner = repository.ownerID
      let active = try context.fetchCount(
        FetchDescriptor<JourneyReflection>(
          predicate: #Predicate { $0.ownerID == owner && $0.tombstoned == false }))
      let deleted = try context.fetch(
        FetchDescriptor<JourneyReflection>(
          predicate: #Predicate { $0.ownerID == owner && $0.tombstoned == true }))
      XCTAssertEqual(active, 0)
      XCTAssertEqual(deleted.count, 1)
      XCTAssertTrue(try XCTUnwrap(deleted.first).text.isEmpty)
      XCTAssertTrue(try XCTUnwrap(deleted.first).tombstoned)
      XCTAssertTrue(
        try repository.page(month: JourneyMonth(year: 2025, month: 6)).events
          .filter { $0.kind == .reflection }.isEmpty)
    }
  }
}
