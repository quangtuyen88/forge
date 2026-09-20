import Foundation

// MARK: - Share cards
//
// A card is a snapshot of what was logged, not a live query and not a claim. Everything
// here is about refusing to overstate: a planned load is not a completed lift, an
// estimate is not a tested max, a missing RPE is absent rather than zero, and a subset of
// the session says so on its face.

public enum ShareCardTemplate: String, Sendable, CaseIterable {
  case topSets = "top_sets"
  case personalBest = "personal_best"
  case myWeek = "my_week"
}

public enum ShareCardFormat: String, Sendable, CaseIterable {
  case square
  case story

  /// Fixed export canvases. Never the phone safe area.
  public var pixelSize: (width: Int, height: Int) {
    switch self {
    case .square: return (1080, 1080)
    case .story: return (1080, 1920)
    }
  }

  /// How many exercise highlights fit without shrinking the mandatory labels.
  public var highlightLimit: Int { self == .square ? 3 : 4 }
}

public enum ShareCardLook: String, Sendable, CaseIterable {
  case clean
  case photo
}

/// One logged set, already resolved by the existing selectors. The composer never
/// recalculates a top set, a PR or a conversion — it is handed the answer.
public struct ShareHighlight: Sendable, Equatable {
  public let exerciseID: String
  public let exerciseName: String
  public let load: LoadValue?
  public let reps: Int
  /// Tenths of an RPE point, or nil when the lifter never reported effort.
  public let rpeTenths: Int?
  /// A qualifier the existing policy attached, e.g. an unverified log.
  public let qualifier: String?

  public init(
    exerciseID: String, exerciseName: String, load: LoadValue?, reps: Int,
    rpeTenths: Int? = nil, qualifier: String? = nil
  ) {
    self.exerciseID = exerciseID
    self.exerciseName = exerciseName
    self.load = load
    self.reps = reps
    self.rpeTenths = rpeTenths
    self.qualifier = qualifier
  }
}

/// A summary number plus the scope it actually covers. The label and the scope travel
/// together so a filtered total can never be presented as the whole workout.
public struct ShareAggregate: Sendable, Equatable {
  public let key: String
  public let value: String
  public let scopeLabel: String?

  public init(key: String, value: String, scopeLabel: String? = nil) {
    self.key = key
    self.value = value
    self.scopeLabel = scopeLabel
  }
}

/// What the lifter chose to reveal. Everything is off until they turn it on, and a hidden
/// field is hidden everywhere — image, caption, accessibility text and filename.
public struct ShareDisclosure: Sendable, Equatable {
  public var showsRPE: Bool
  public var showsComparison: Bool
  public var showsDate: Bool
  public var showsDisplayName: Bool
  public var showsNextTarget: Bool
  public var showsSessionTitle: Bool

  public init(
    showsRPE: Bool = false, showsComparison: Bool = false, showsDate: Bool = false,
    showsDisplayName: Bool = false, showsNextTarget: Bool = false,
    showsSessionTitle: Bool = true
  ) {
    self.showsRPE = showsRPE
    self.showsComparison = showsComparison
    self.showsDate = showsDate
    self.showsDisplayName = showsDisplayName
    self.showsNextTarget = showsNextTarget
    self.showsSessionTitle = showsSessionTitle
  }

  public static let safeDefaults = ShareDisclosure()
}

/// A next-session prescription, only ever shown with its mandatory label.
public struct ShareNextTarget: Sendable, Equatable {
  public let exerciseName: String
  public let load: LoadValue?
  public let minimumReps: Int
  public let maximumReps: Int

  public init(exerciseName: String, load: LoadValue?, minimumReps: Int, maximumReps: Int) {
    self.exerciseName = exerciseName
    self.load = load
    self.minimumReps = minimumReps
    self.maximumReps = maximumReps
  }
}

/// The renderable card. Only selected values, each with its qualifier already attached —
/// no notes, no health context, no database identifiers, no revisions.
public struct CardDocument: Sendable, Equatable {
  public let template: ShareCardTemplate
  public let format: ShareCardFormat
  public let look: ShareCardLook
  public let title: String
  public let subtitle: String?
  public let highlights: [ShareHighlight]
  public let aggregates: [ShareAggregate]
  public let nextTarget: ShareNextTarget?
  /// Non-nil when the card shows a subset, so it never implies the whole session.
  public let subsetLabel: String?
  public let mandatoryQualifiers: [String]

  public init(
    template: ShareCardTemplate, format: ShareCardFormat, look: ShareCardLook,
    title: String, subtitle: String?, highlights: [ShareHighlight],
    aggregates: [ShareAggregate], nextTarget: ShareNextTarget?, subsetLabel: String?,
    mandatoryQualifiers: [String]
  ) {
    self.template = template
    self.format = format
    self.look = look
    self.title = title
    self.subtitle = subtitle
    self.highlights = highlights
    self.aggregates = aggregates
    self.nextTarget = nextTarget
    self.subsetLabel = subsetLabel
    self.mandatoryQualifiers = mandatoryQualifiers
  }
}

/// Why a card cannot be built. Each one is a state the UI shows, never a silent downgrade
/// to a different achievement.
public enum ShareCardUnavailable: String, Sendable, Equatable {
  case noEligibleContent = "no_eligible_content"
  case recordRevoked = "record_revoked"
  case targetNotCommitted = "target_not_committed"
  case sourceChanged = "source_changed"
}

public enum ShareCardResult: Sendable, Equatable {
  case ready(CardDocument)
  case unavailable(ShareCardUnavailable)
}

/// The labels that may never be dropped to make something fit.
///
/// Each one has a producer in this release: `unverified` comes from the existing
/// plausibility guard, `selectedSubset` from a card showing fewer highlights than the
/// session had, `planned` from an opted-in next-session target. `estimated_1rm` belongs to
/// the Personal Best template and is added with it — an unreachable case invites an
/// exhaustive switch that makes it load-bearing before anything produces it.
public enum ShareCardQualifier {
  public static let planned = "planned_not_completed"
  public static let unverified = "unverified"
  public static let selectedSubset = "selected_top_sets"
}

public enum ShareCardBuilder {
  /// Build a Top Sets card from content the existing selectors already approved.
  ///
  /// `totalExerciseCount` is what the session really contained: when fewer highlights are
  /// shown, the card says so rather than implying the whole workout is on it.
  public static func topSets(
    title: String,
    date: Date?,
    highlights: [ShareHighlight],
    totalExerciseCount: Int,
    aggregates: [ShareAggregate],
    nextTarget: ShareNextTarget?,
    disclosure: ShareDisclosure,
    format: ShareCardFormat,
    look: ShareCardLook,
    dateText: (Date) -> String = { _ in "" }
  ) -> ShareCardResult {
    let selected = Array(highlights.prefix(format.highlightLimit))
    guard !selected.isEmpty else { return .unavailable(.noEligibleContent) }

    // Effort the lifter never reported stays absent; it is not the target in disguise.
    let disclosed = selected.map { highlight in
      ShareHighlight(
        exerciseID: highlight.exerciseID, exerciseName: highlight.exerciseName,
        load: highlight.load, reps: highlight.reps,
        rpeTenths: disclosure.showsRPE ? highlight.rpeTenths : nil,
        qualifier: highlight.qualifier)
    }

    var qualifiers: [String] = []
    if disclosed.contains(where: { $0.qualifier == ShareCardQualifier.unverified }) {
      qualifiers.append(ShareCardQualifier.unverified)
    }
    let subset = disclosed.count < totalExerciseCount ? ShareCardQualifier.selectedSubset : nil

    // A target is only shown when the lifter asked for it, and only with its label.
    var target: ShareNextTarget?
    if disclosure.showsNextTarget, let nextTarget {
      target = nextTarget
      qualifiers.append(ShareCardQualifier.planned)
    }

    let subtitle = disclosure.showsDate ? date.map(dateText) : nil
    return .ready(
      CardDocument(
        template: .topSets, format: format, look: look,
        title: disclosure.showsSessionTitle ? title : "",
        subtitle: (subtitle?.isEmpty ?? true) ? nil : subtitle,
        highlights: disclosed,
        aggregates: Array(aggregates.prefix(2)),
        nextTarget: target, subsetLabel: subset, mandatoryQualifiers: qualifiers))
  }

  /// The caption is built from the SAME document, so a hidden field cannot reappear in
  /// text after being removed from the image.
  public static func caption(
    for document: CardDocument,
    line: (ShareHighlight) -> String,
    qualifierText: (String) -> String
  ) -> String {
    var parts: [String] = []
    if !document.title.isEmpty { parts.append(document.title) }
    if let subsetLabel = document.subsetLabel { parts.append(qualifierText(subsetLabel)) }
    parts.append(contentsOf: document.highlights.map(line))
    for aggregate in document.aggregates {
      parts.append([aggregate.value, aggregate.scopeLabel].compactMap { $0 }.joined(separator: " "))
    }
    if document.nextTarget != nil {
      parts.append(qualifierText(ShareCardQualifier.planned))
    }
    return parts.joined(separator: "\n")
  }
}
