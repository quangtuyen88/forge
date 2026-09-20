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

  func testAllowedResponsesAreBoundedAndNeverMutateTheProgram() {
    for reason in SetLimiterReason.allCases {
      XCTAssertFalse(reason.allowedResponse.mutatesProgram, "\(reason.rawValue) must not mutate the program")
    }
    XCTAssertEqual(SetLimiterReason.targetMuscles.allowedResponse, .recordOnly)
    XCTAssertEqual(SetLimiterReason.unsure.allowedResponse, .recordOnly)
    XCTAssertEqual(SetLimiterReason.breathing.allowedResponse, .offerSupportedRestAdjustment)
    XCTAssertEqual(SetLimiterReason.setup.allowedResponse, .offerSetupReview)
    XCTAssertEqual(SetLimiterReason.techniqueUncertainty.allowedResponse, .showCuratedGuidance)
    XCTAssertEqual(SetLimiterReason.interrupted.allowedResponse, .offerScopeExclusion)
    XCTAssertTrue(SetLimiterReason.grip.requiresVersionedEvidenceBeforeReview)
    XCTAssertFalse(SetLimiterReason.interrupted.requiresVersionedEvidenceBeforeReview)
    XCTAssertEqual(SetLimiterResponse.allCases.filter(\.mutatesProgram), [])
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

  func testIdentityKnowsWhenTheSetChangedUnderIt() {
    let id = identity(revision: SetRevision("r1"))
    XCTAssertFalse(id.isStale(against: SetRevision("r1")))
    XCTAssertTrue(id.isStale(against: SetRevision("r2")))
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

  func testDeleteIsATombstoneAndRestoreBringsTheStatementBack() {
    var stored = event(kind: .limiter(.unsure))
    XCTAssertTrue(SetFeedbackAnalysisPolicy.excludes(stored, from: .progression))
    let later = t0.addingTimeInterval(60)
    stored.delete(at: later)
    XCTAssertTrue(stored.isDeleted)
    XCTAssertNil(SetFeedbackAnalysisPolicy.historyNote(for: stored))
    XCTAssertTrue(SetFeedbackAnalysisPolicy.isEligible(stored, for: .progression))
    XCTAssertTrue(SetFeedbackAnalysisPolicy.isEligible(stored, for: .achievements))
    XCTAssertTrue(SetFeedbackAnalysisPolicy.isEligibleEverywhere(stored))
    stored.restore(at: later.addingTimeInterval(60))
    XCTAssertFalse(stored.isDeleted)
    XCTAssertTrue(SetFeedbackAnalysisPolicy.excludes(stored, from: .progression))
    XCTAssertEqual(stored.createdAt, t0, "the statement's own history is untouched")
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

  func testExclusionTableIsPinnedPerReason() {
    let expected: [SetLimiterReason: Set<SetAnalysisScope>] = [
      .targetMuscles: [],
      .grip: [.progression],
      .breathing: [.progression],
      .other: [.progression],
      .techniqueUncertainty: [.progression, .achievements],
      .setup: [.progression, .achievements],
      .interrupted: [.progression, .trends, .achievements],
      .unsure: Set(SetAnalysisScope.allCases),
    ]
    for (reason, scopes) in expected {
      XCTAssertEqual(SetFeedbackAnalysisPolicy.excludedScopes(forReason: reason), scopes, reason.rawValue)
      XCTAssertEqual(SetFeedbackAnalysisPolicy.excludedScopes(forKind: .limiter(reason)), scopes, reason.rawValue)
      XCTAssertEqual(reason.withholdsAnalysis, !scopes.isEmpty)
    }
  }

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

  func testExclusionNeverPenalisesReadinessAdherenceOrTheProgram() {
    XCTAssertFalse(SetFeedbackAnalysisPolicy.affectsAdherence)
    XCTAssertFalse(SetFeedbackAnalysisPolicy.affectsReadiness)
    XCTAssertFalse(SetFeedbackAnalysisPolicy.mutatesProgram)
    XCTAssertFalse(SetFeedbackAnalysisPolicy.createsCoachMemory)
    XCTAssertFalse(SetFeedbackAnalysisPolicy.deletesRecordedWork)
    XCTAssertEqual(SetAnalysisScope.allCases.count, 4)
    for scope in SetAnalysisScope.allCases {
      XCTAssertFalse(scope.label.isEmpty)
      XCTAssertFalse(scope.shortExplanation.isEmpty)
    }
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

  func testDiscomfortSignalIsNeverTreatedAsAMissedSet() {
    for signal in DiscomfortSignal.allCases {
      XCTAssertFalse(signal.isUnfinished)
      XCTAssertFalse(signal.label.isEmpty)
      XCTAssertEqual(DiscomfortSafetyCopy.response(for: signal), .safetyGuidance)
      XCTAssertFalse(DiscomfortSafetyCopy.response(for: signal).mutatesProgram)
    }
  }

  // MARK: prompts

  func testAtMostOneUnsolicitedPromptAndZeroIsAlwaysFine() {
    let reason = SetLimiterReason.unsure
    XCTAssertEqual(
      SetFeedbackPromptRule.verdict(reason: reason, unsolicitedPromptsAlreadyShown: 0), .allowed)
    XCTAssertEqual(
      SetFeedbackPromptRule.verdict(reason: reason, unsolicitedPromptsAlreadyShown: 1), .notAllowed)
    XCTAssertEqual(
      SetFeedbackPromptRule.verdict(reason: reason, unsolicitedPromptsAlreadyShown: 5), .notAllowed)
    XCTAssertEqual(
      SetFeedbackPromptRule.verdict(reason: reason, unsolicitedPromptsAlreadyShown: -1), .notAllowed)
    XCTAssertEqual(
      SetFeedbackPromptRule.verdict(reason: nil, unsolicitedPromptsAlreadyShown: 0), .notAllowed)
    XCTAssertEqual(SetFeedbackPromptRule.maximumUnsolicitedPromptsPerWorkout, 1)
    XCTAssertFalse(SetFeedbackPromptRule.promptsAreRequired)
    XCTAssertFalse(SetFeedbackPromptRule.skippedPromptAffectsAdherence)
    XCTAssertFalse(SetFeedbackPromptRule.skippedPromptAffectsReadiness)
    XCTAssertFalse(SetFeedbackPromptRule.skippedPromptAffectsAwards)
  }

  func testOnlyARuleDefinedUnusualResultSuggestsAReason() {
    XCTAssertNil(
      SetFeedbackPromptRule.UnusualResult(repsBelowRange: false, effortNotReported: false, loadJumped: false)
        .suggestsReason)
    XCTAssertEqual(
      SetFeedbackPromptRule.UnusualResult(repsBelowRange: true, effortNotReported: false, loadJumped: false)
        .suggestsReason, .interrupted)
    XCTAssertEqual(
      SetFeedbackPromptRule.UnusualResult(repsBelowRange: false, effortNotReported: false, loadJumped: true)
        .suggestsReason, .setup)
    XCTAssertEqual(
      SetFeedbackPromptRule.UnusualResult(repsBelowRange: false, effortNotReported: true, loadJumped: false)
        .suggestsReason, .unsure)
  }

  // MARK: summaries

  func testSummaryNeedsARepeatPatternAndInvalidatesWhenSourcesChange() {
    let one = [event(setID: "set-1", kind: .limiter(.grip))]
    let singles = SetLimiterSummaryBuilder.summary(exerciseID: "bench", events: one)
    if let singles {
      XCTAssertFalse(singles.describesARepeatPattern)
      XCTAssertNil(SetLimiterSummaryBuilder.headline(singles), "one set is not a pattern")
    }
    XCTAssertEqual(singles?.sourceEventIDs, ["setfeedback.set-1"])
    XCTAssertEqual(singles?.reasonCounts, ["grip": 1])

    var second = event(setID: "set-2", kind: .limiter(.grip))
    let pair = [one[0], second]
    let summary = SetLimiterSummaryBuilder.summary(exerciseID: "bench", events: pair)
    XCTAssertEqual(summary?.reasonCounts, ["grip": 2])
    XCTAssertTrue(summary?.describesARepeatPattern == true)
    XCTAssertEqual(SetLimiterSummaryBuilder.headline(summary!), "Grip reported on 2 sets of this exercise. This is context, not a cause.")
    XCTAssertFalse(SetLimiterSummaryBuilder.headline(summary!)!.contains("because"))

    // Editing a source invalidates the summary; deleting one drops it from the derivation.
    second.edit(kind: .limiter(.grip), note: "same grip issue", at: t0.addingTimeInterval(60))
    XCTAssertTrue(summary!.isStale(against: [one[0], second]))
    var third = event(setID: "set-3", kind: .limiter(.grip))
    let afterDelete = SetLimiterSummaryBuilder.summary(exerciseID: "bench", events: [one[0], second, third])
    XCTAssertEqual(afterDelete?.sourceEventIDs.count, 3)
    third.delete(at: t0.addingTimeInterval(120))
    let rebuilt = SetLimiterSummaryBuilder.summary(exerciseID: "bench", events: [one[0], second, third])
    XCTAssertEqual(rebuilt?.sourceEventIDs.count, 2)
    XCTAssertTrue(afterDelete!.isStale(against: [one[0], second, third]))
  }

  func testSummaryReportsDiscomfortWithoutInferringACause() {
    let a = event(setID: "set-1", kind: .discomfort(DiscomfortFeedback(signal: .noticed)))
    let b = event(setID: "set-2", kind: .discomfort(DiscomfortFeedback(signal: .stoppedTheSet)))
    let summary = SetLimiterSummaryBuilder.summary(exerciseID: "bench", events: [a, b])
    XCTAssertEqual(summary?.discomfortCount, 2)
    XCTAssertEqual(summary?.reasonCounts, [:])
    let headline = SetLimiterSummaryBuilder.headline(summary!)
    XCTAssertEqual(headline, "Discomfort reported on 2 sets of this exercise. Progression for those sets stays paused.")
    XCTAssertFalse(headline!.lowercased().contains("hypertrophy"))
    XCTAssertNil(SetLimiterSummaryBuilder.summary(exerciseID: "squat", events: [a, b]))
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

  func testKindAccessorsAreMutuallyExclusive() {
    let limiter = SetLimiterKind.limiter(.interrupted)
    XCTAssertEqual(limiter.limiterReason, .interrupted)
    XCTAssertNil(limiter.discomfort)
    XCTAssertFalse(limiter.isDiscomfort)
    XCTAssertEqual(limiter.allowedResponse, .offerScopeExclusion)

    let discomfort = SetLimiterKind.discomfort(DiscomfortFeedback(signal: .noticed))
    XCTAssertNil(discomfort.limiterReason)
    XCTAssertTrue(discomfort.isDiscomfort)
    XCTAssertEqual(discomfort.allowedResponse, .safetyGuidance)
    XCTAssertEqual(discomfort.symbol, "exclamationmark.triangle")
  }
}
