import ForgeCore
/// A description
import Foundation
import SwiftData

// MARK: - Device-local Journey models
//
// Everything in this file stays on **this device**. `SyncEngine` is an explicit allowlist:
// `localChanges(since:context:)` names each synced type by hand and `apply(_:context:)` switches
// on the type string, so a model that is not named there is never uploaded and never pulled.
// These three are deliberately not named. A reflection is private prose, a visibility override
// is a per-device display preference, and the private profile is a local identity card.
// Registering them in the container is what makes them persist; staying out of `SyncEngine` is
// what keeps them local.
//
// None of these models holds a foreign key back into the source records. A card links to its
// source through the canonical `JourneyEventID` (which embeds owner + kind + canonical source id),
// so hiding a card never touches — and can never delete — the workout, measurement, photo or
// decision behind it.

// MARK: - Reflection

/// One private note. `reflectionID` is the canonical source id for a note event:
/// `JourneyEventID.reflection(owner:reflectionID:)` is derived from it and nothing else, so
/// editing the text or changing the day never orphans a stored visibility override.
@Model
final class JourneyReflection {
  @Attribute(.unique) var reflectionID: UUID
  /// Canonical owner — `UserProfile.remoteID` folded through `JourneyEventID.canonicalOwner`.
  var ownerID: String
  /// Plain text, already normalized (trimmed) at write time.
  var text: String
  /// Local start-of-day. A note is a date-only entry; no midnight instant is implied.
  var day: Date
  /// Optional typed link to the canonical record the note is about. Stored as the raw
  /// `JourneySourceKind` value so an unknown future kind round-trips rather than crashing.
  var sourceKind: String?
  var sourceID: String?
  var createdAt: Date
  var updatedAt: Date
  /// Bumped on every successful edit, so the editor can reject a stale write.
  var revision: Int
  /// Idempotency key for a retried save. Never part of the event identity.
  var clientRequestID: String?
  /// Soft delete. The row stays so a retried create is not silently resurrected.
  @Attribute(originalName: "deleted") var tombstoned: Bool

  init(
    ownerID: String,
    reflectionID: UUID = UUID(),
    text: String,
    day: Date,
    source: JourneySourceReference? = nil,
    clientRequestID: String? = nil,
    createdAt: Date = .now,
    updatedAt: Date = .now,
    revision: Int = 1,
    deleted: Bool = false
  ) {
    self.reflectionID = reflectionID
    self.ownerID = ownerID
    self.text = text
    self.day = day
    self.sourceKind = source?.kind.rawValue
    self.sourceID = source?.sourceID
    self.createdAt = createdAt
    self.updatedAt = updatedAt
    self.revision = revision
    self.clientRequestID = clientRequestID
    self.tombstoned = deleted
  }

  /// The typed link, or `nil` when absent or naming a kind this build does not know.
  var sourceReference: JourneySourceReference? {
    guard let sourceKind,
      let kind = JourneySourceKind(rawValue: sourceKind),
      let sourceID,
      !sourceID.isEmpty
    else { return nil }
    return JourneySourceReference(kind: kind, sourceID: sourceID)
  }

  /// The stable event identity for this note. Derived only from the owner and the UUID.
  var eventID: JourneyEventID {
    JourneyEventID.reflection(owner: ownerID, reflectionID: reflectionID.uuidString)
  }
}

// MARK: - Visibility override

/// Devices-local "hide this card" record. Hiding is a display decision, never a data
/// decision: no source row is touched. `eventID` already embeds the owner, and is unique
/// so a second hide of the same card updates the existing row instead of duplicating it.
@Model
final class JourneyVisibilityOverride {
  @Attribute(.unique) var eventID: String
  /// Canonical owner, kept as its own column for an owner-scoped fetch.
  var ownerID: String
  /// True hides the card; false is a stored "restored" tombstone that keeps the history.
  var hidden: Bool
  /// Bumped on every change; mirrors the source of the write so a stale restore is visible.
  var revision: Int
  var updatedAt: Date

  init(
    eventID: String,
    ownerID: String,
    hidden: Bool,
    revision: Int = 1,
    updatedAt: Date = .now
  ) {
    self.eventID = eventID
    self.ownerID = ownerID
    self.hidden = hidden
    self.revision = revision
    self.updatedAt = updatedAt
  }

  convenience init(
    eventID: JourneyEventID,
    ownerID: String,
    hidden: Bool,
    revision: Int = 1,
    updatedAt: Date = .now
  ) {
    self.init(
      eventID: eventID.rawValue, ownerID: ownerID, hidden: hidden, revision: revision,
      updatedAt: updatedAt)
  }
}

// MARK: - Private profile

/// The local-only identity card the Journey timeline shows at the top of the month. It is
/// deliberately separate from `UserProfile`: nothing here is synced and nothing here is
/// inferred. `trainingStartDate` is only ever what the lifter explicitly set.
@Model
final class JourneyPrivateProfile {
  @Attribute(.unique) var ownerID: String
  var displayName: String
  /// Explicit training start. `nil` means the lifter never set one — the timeline must not
  /// invent a start date from the first workout.
  var trainingStartDate: Date?
  /// Bumped on every successful save; the editor passes the revision it read back so a
  /// concurrent edit on the same device is rejected rather than silently overwritten.
  var revision: Int
  var updatedAt: Date

  init(
    ownerID: String,
    displayName: String = "",
    trainingStartDate: Date? = nil,
    revision: Int = 1,
    updatedAt: Date = .now
  ) {
    self.ownerID = ownerID
    self.displayName = displayName
    self.trainingStartDate = trainingStartDate
    self.revision = revision
    self.updatedAt = updatedAt
  }
}

// MARK: - Capabilities

/// What the Journey surface does **not** do in this build, stated in one place so no screen
/// fabricates it. Each entry is a disabled capability, not a missing implementation detail.
enum JourneyCapabilities {
  /// Auto-detected milestones (first 100 kg bench, 10th session, …) are not derived. A
  /// milestone card would be a fabricated claim about the lifter's history, so none is shown.
  static let automaticMilestones = false
  /// Periodic "month in review" roll-ups are not generated. The timeline shows recorded
  /// events only; it never synthesises a summary the lifter did not write.
  static let automaticReviews = false
  /// Personal records are not inferred inside the timeline. PRs keep their existing,
  /// analysis-gated surfaces elsewhere in the app.
  static let inferredPRs = false
  /// Professional or public sharing of notes and body entries is not offered.
  static let publicSharing = false
  /// Result-reflecting advice / AI commentary is not generated on the timeline.
  static let generatedAdvice = false
}
