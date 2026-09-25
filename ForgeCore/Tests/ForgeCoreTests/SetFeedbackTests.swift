import XCTest

@testable import ForgeCore

final class SetFeedbackTests: XCTestCase {
  private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

  private func identity(
    setID: String = "set-1", revision: SetRevision = SetRevision("r1"), setIndex: Int = 0
  ) -> SetIdentity {
    SetIdentity(
      setID: setID, sessionID: "session-1", exerciseID: "bench", setIndex: setIndex, revision: revision,
      loggedAt: t0)
  }

  private func provenance(at: Date? = nil) -> SetFeedbackProvenance {
    SetFeedbackProvenance(source: .lifter, actorID: "me", appVersion: "1.0", capturedAt: at ?? t0)
  }

  private func event(
    setID: String = "set-1", kind: SetLimiterKind = .limiter(.interrupted), note: String? = nil,
    revision: SetRevision = SetRevision("r1"), createdAt: Date? = nil
  ) -> SetLimiterEvent {
    SetLimiterEvent.record(
      identity: identity(setID: setID, revision: revision), kind: kind, note: note,
      provenance: provenance(), at: createdAt ?? t0)
  }

  // MARK: reasons

  func testReasonCodesAreClosedAndSelfDescribing() {
    XCTAssertEqual(
      SetLimiterReason.allCases.map(\.rawValue),
      ["targetMuscles", "grip", "breathing", "setup", "techniqueUncertainty", "interrupted", "other", "unsure"])
    for reason in SetLimiterReason.allCases {
      XCTAssertFalse(reason.label.isEmpty)
      XCTAssertFalse(reason.detail.isEmpty)
      XCTAssertFalse(reason.symbol.isEmpty)
    }
    // Discomfort is deliberately not an ordinary reason.
    XCTAssertFalse(SetLimiterReason.allCases.map(\.rawValue).contains("discomfort"))
    XCTAssertFalse(SetLimiterReason.allCases.map(\.rawValue).contains("pain"))
  }

  // MARK: set identity and revision

  func testRevisionIsDeterministicAndChangesWithRecordedContent() {
    let base = SetRevisionBuilder.revision(
      setID: "set-1", loadValue: "80", loadUnit: "kg", reps: 8, setIndex: 0, variant: "straight")
    let same = SetRevisionBuilder.revision(
      setID: "set-1", loadValue: "80", loadUnit: "kg", reps: 8, setIndex: 0, variant: "straight")
    XCTAssertEqual(base, same)

    let edits: [SetRevision] = [
      SetRevisionBuilder.revision(setID: "set-1", loadValue: "82.5", loadUnit: "kg", reps: 8, setIndex: 0, variant: "straight"),
      SetRevisionBuilder.revision(setID: "set-1", loadValue: "80", loadUnit: "kg", reps: 7, setIndex: 0, variant: "straight"),
      SetRevisionBuilder.revision(setID: "set-1", loadValue: "80", loadUnit: "kg", reps: 8, setIndex: 1, variant: "straight"),
      SetRevisionBuilder.revision(setID: "set-1", loadValue: "80", loadUnit: "kg", reps: 8, setIndex: 0, variant: "myoRep"),
      SetRevisionBuilder.revision(setID: "set-2", loadValue: "80", loadUnit: "kg", reps: 8, setIndex: 0, variant: "straight"),
      SetRevisionBuilder.revision(setID: "set-1", loadValue: "176", loadUnit: "lb", reps: 8, setIndex: 0, variant: "straight"),
    ]
    for edited in edits {
      XCTAssertNotEqual(base, edited)
    }
    XCTAssertEqual(Set(edits).count, edits.count, "revisions must not collide")
  }

  // MARK: record / edit / delete

  func testRecordBindsIdentityRevisionNoteAndProvenance() {
    let recorded = event(note: "  cut short by a phone call  ")
    XCTAssertEqual(recorded.id, SetLimiterEvent.id(forSet: "set-1"))
    XCTAssertEqual(recorded.identity.exerciseID, "bench")
    XCTAssertEqual(recorded.identity.revision, SetRevision("r1"))
    XCTAssertEqual(recorded.note, "cut short by a phone call")
    XCTAssertEqual(recorded.provenance.source, .lifter)
    XCTAssertEqual(recorded.createdAt, t0)
    XCTAssertEqual(recorded.updatedAt, t0)
    XCTAssertNil(recorded.deletedAt)
    XCTAssertFalse(recorded.isDeleted)
    XCTAssertFalse(recorded.isDurableMemory)
  }

  func testNoteSanitisingTreatsWhitespaceAsNoNoteAndCapsLength() {
    XCTAssertNil(SetLimiterEvent.sanitizedNote(nil))
    XCTAssertNil(SetLimiterEvent.sanitizedNote(""))
    XCTAssertNil(SetLimiterEvent.sanitizedNote("   \n\t "))
    XCTAssertEqual(SetLimiterEvent.sanitizedNote("ok"), "ok")
    let long = String(repeating: "x", count: SetLimiterEvent.maxNoteLength + 50)
    XCTAssertEqual(SetLimiterEvent.sanitizedNote(long)?.count, SetLimiterEvent.maxNoteLength)
    XCTAssertNil(event(note: "   ").note)
  }

  func testEditingKeepsCreationTimeAndReplacingKeepsOneEventPerSet() {
    var stored = event(kind: .limiter(.unsure), note: "unsure")
    let later = t0.addingTimeInterval(600)
    stored.edit(kind: .limiter(.grip), note: "grip gave out first", at: later)
    XCTAssertEqual(stored.createdAt, t0)
    XCTAssertEqual(stored.updatedAt, later)
    XCTAssertEqual(stored.kind.limiterReason, .grip)
    XCTAssertEqual(stored.note, "grip gave out first")

    let replaced = SetLimiterEvent.record(
      identity: identity(setID: "set-1", revision: SetRevision("r2")), kind: .limiter(.interrupted),
      provenance: provenance(at: later), at: later)
    XCTAssertEqual(replaced.id, stored.id, "one event per set")
    XCTAssertEqual(replaced.identity.revision, SetRevision("r2"))
  }

  func testRebindingKeepsTheStatementAndRefreshesTheRevision() {
    let original = event(kind: .limiter(.breathing), note: "tight")
    let rebound = original.rebinding(to: identity(setID: "set-1", revision: SetRevision("r2")), at: t0.addingTimeInterval(300))
    XCTAssertEqual(rebound.id, original.id)
    XCTAssertEqual(rebound.createdAt, t0)
    XCTAssertEqual(rebound.note, "tight")
    XCTAssertEqual(rebound.kind, original.kind)
    XCTAssertFalse(rebound.isStale(against: SetRevision("r2")))
    XCTAssertTrue(original.isStale(against: SetRevision("r2")))
  }

  // MARK: eligibility

  func testDiscomfortWithholdsEveryNamedAnalysis() {
    for signal in DiscomfortSignal.allCases {
      let discomfort = event(kind: .discomfort(DiscomfortFeedback(signal: signal, note: "left shoulder")))
      XCTAssertEqual(SetFeedbackAnalysisPolicy.excludedScopes(discomfort), Set(SetAnalysisScope.allCases))
      for scope in SetAnalysisScope.allCases {
        XCTAssertFalse(SetFeedbackAnalysisPolicy.isEligible(discomfort, for: scope))
      }
      XCTAssertFalse(discomfort.kind.isDiscomfort == false)
      XCTAssertEqual(discomfort.kind.limiterReason, nil)
      XCTAssertEqual(discomfort.kind.discomfort?.note, "left shoulder")
    }
  }

  func testNoFeedbackAndUnclassifiedFeedbackKeepTheSetEligible() {
    XCTAssertTrue(SetFeedbackAnalysisPolicy.isEligibleEverywhere(nil))
    XCTAssertTrue(SetFeedbackAnalysisPolicy.isEligible(nil, for: .achievements))
    XCTAssertNil(SetFeedbackAnalysisPolicy.scopeExplanation(for: nil))
    XCTAssertNil(SetFeedbackAnalysisPolicy.scopeExplanation([]))
    XCTAssertNil(SetFeedbackAnalysisPolicy.historyNote(for: nil))
    XCTAssertEqual(SetFeedbackAnalysisPolicy.excludedScopes(nil), [])

    let confirmed = event(kind: .limiter(.targetMuscles))
    XCTAssertTrue(SetFeedbackAnalysisPolicy.isEligibleEverywhere(confirmed))
    XCTAssertNil(SetFeedbackAnalysisPolicy.scopeExplanation(for: confirmed))
    XCTAssertNil(SetFeedbackAnalysisPolicy.historyNote(for: confirmed))
  }

  func testScopeExplanationNamesTheScopeAndSaysTheWorkIsKept() {
    let grip = event(kind: .limiter(.grip))
    let explanation = try? XCTUnwrap(SetFeedbackAnalysisPolicy.scopeExplanation(for: grip))
    XCTAssertEqual(explanation, "Left out of load progression. Your logged set stays in History exactly as recorded.")

    let interrupted = event(kind: .limiter(.interrupted))
    let note = try? XCTUnwrap(SetFeedbackAnalysisPolicy.historyNote(for: interrupted))
    XCTAssertTrue(note?.contains("load progression") == true)
    XCTAssertTrue(note?.contains("Progress trends") == true)
    XCTAssertTrue(note?.contains("records and awards") == true)
    XCTAssertFalse(note?.contains("Crew") == true)
    XCTAssertTrue(note?.contains("Set cut short") == true)
    XCTAssertTrue(note?.contains("History") == true)

    let discomfort = event(kind: .discomfort(DiscomfortFeedback(signal: .stoppedTheSet)))
    let discomfortNote = SetFeedbackAnalysisPolicy.historyNote(for: discomfort)
    XCTAssertTrue(discomfortNote?.contains("you reported discomfort") == true)
    XCTAssertTrue(discomfortNote?.contains("Crew") == true)
  }

  // MARK: safety copy

  func testDiscomfortCopyIsNonDiagnosticAndNeverPushesThrough() {
    XCTAssertTrue(DiscomfortSafetyCopy.neverPrescribesRehabilitation)
    XCTAssertTrue(DiscomfortSafetyCopy.neverEncouragesContinuation)
    let all = [
      DiscomfortSafetyCopy.headline, DiscomfortSafetyCopy.guidance, DiscomfortSafetyCopy.nextSteps,
    ].joined(separator: " ").lowercased()
    for banned in ["tendinitis", "tendonitis", "rehab", "prescribe", "push through", "ignore the pain", "you have a", "no pain no gain"] {
      XCTAssertFalse(all.contains(banned), "safety copy must not contain \(banned)")
    }
    XCTAssertTrue(all.contains("not a diagnosis"))
    XCTAssertTrue(all.contains("logged set") || all.contains("kept"))
  }

  // MARK: codec

  func testCodecRoundTripsAndRefusesToGuess() {
    let original = event(kind: .discomfort(DiscomfortFeedback(signal: .changedTheSet, note: "left knee")), note: "  adjusted angle ")
    let json = SetLimiterEventCodec.encode(original)
    XCTAssertFalse(json.isEmpty)
    let restored = SetLimiterEventCodec.decode(json)
    XCTAssertEqual(restored, original)
    XCTAssertEqual(restored?.kind.discomfort?.note, "left knee")

    XCTAssertNil(SetLimiterEventCodec.decode(""))
    XCTAssertNil(SetLimiterEventCodec.decode("   "))
    XCTAssertNil(SetLimiterEventCodec.decode("not json"))
    XCTAssertNil(SetLimiterEventCodec.decode("{\"kind\":\"unknown\"}"))

    // An unknown reason code is not coerced into a known one.
    let future = json.replacingOccurrences(of: "changedTheSet", with: "somethingNew")
    XCTAssertNil(SetLimiterEventCodec.decode(future))
  }

  func testCodecKeepsTheStatementReadableAfterAnEditAndDelete() {
    var stored = event(kind: .limiter(.setup), note: "misloaded the bar")
    stored.edit(kind: .limiter(.setup), note: "bar was on the wrong pins", at: t0.addingTimeInterval(30))
    let edited = SetLimiterEventCodec.decode(SetLimiterEventCodec.encode(stored))
    XCTAssertEqual(edited?.note, "bar was on the wrong pins")
    XCTAssertEqual(edited?.createdAt, t0)
    XCTAssertEqual(edited?.updatedAt, t0.addingTimeInterval(30))
    XCTAssertEqual(SetFeedbackAnalysisPolicy.excludedScopes(edited), [.progression, .achievements])

    stored.delete(at: t0.addingTimeInterval(90))
    let deleted = SetLimiterEventCodec.decode(SetLimiterEventCodec.encode(stored))
    XCTAssertEqual(deleted?.deletedAt, t0.addingTimeInterval(90))
    XCTAssertTrue(SetFeedbackAnalysisPolicy.isEligibleEverywhere(deleted))
    XCTAssertNil(SetFeedbackAnalysisPolicy.historyNote(for: deleted))
  }
}
