import SwiftUI
import ForgeCore

/// Next-session load for one exercise of a finished workout.
struct WorkoutNextLoad: Equatable {
  let exerciseID: String
  let kg: Double
  let deltaKg: Double
}

/// Everything the workout chat may know: one finished session, its debrief and the questions the card offers.
struct WorkoutCoachScope: Identifiable {
  let id = UUID()
  let session: WorkoutSession
  /// Localized workout name, e.g. "Full A" (localizedDayName(session.dayName)).
  let title: String
  /// "Mon, Sep 28 · 58 min · 24 sets" (localized).
  let meta: String
  /// Short date for the voice scope line, e.g. "Mon, Sep 28".
  let dateText: String
  /// The debrief lines joined into one paragraph; the chat's first message.
  let intro: String
  /// Up to three starter questions built from this session's data.
  let questions: [String]
  /// Next loads keyed by exercise id.
  let nextLoads: [String: WorkoutNextLoad]
  /// A question tapped on the card; the chat sends it once it has appeared.
  var firstQuestion: String? = nil

  static func make(session: WorkoutSession, sessions: [WorkoutSession], profile: UserProfile?,
                   debrief: [DebriefLine], usesLb: Bool) -> WorkoutCoachScope {
    let title = localizedDayName(session.dayName)
    let dateText = session.date.formatted(
      .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
    let loads = sessionNextLoads(session: session, sessions: sessions, profile: profile)
    // Training order across exercises comes from loggedAt; setIndex only orders sets within
    // one exercise, and SwiftData relationship arrays have no order.
    let trained = session.sets.sorted {
      $0.loggedAt != $1.loggedAt ? $0.loggedAt < $1.loggedAt : $0.setIndex < $1.setIndex
    }

    var questions: [String] = []
    if let first = trained.first {
      questions.append(String(
        localized: "How did my \(Self.name(first.exerciseID)) go?", bundle: L10n.bundle))
    }
    if let hard = trained.first(where: { $0.effortReported && $0.rpe - $0.targetRPE >= 0.5 }) {
      questions.append(String(
        localized: "Why was \(Self.name(hard.exerciseID)) hard?", bundle: L10n.bundle))
    } else if let up = loads.first(where: { $0.deltaKg > 0.05 }) {
      questions.append(String(
        localized: "Why does \(Self.name(up.exerciseID)) go up next time?", bundle: L10n.bundle))
    }

    return WorkoutCoachScope(
      session: session,
      title: title,
      meta: String(
        localized: "\(dateText) · \(SessionMath.durationText([session])) · \(session.sets.count) sets",
        bundle: L10n.bundle),
      dateText: dateText,
      intro: debrief.map(\.text).joined(separator: " "),
      questions: questions,
      nextLoads: Dictionary(uniqueKeysWithValues: loads.map { ($0.exerciseID, $0) }))
  }

  private static func name(_ exerciseID: String) -> String {
    ExerciseDB.find(exerciseID)?.localizedName ?? exerciseID
  }
}

// MARK: - Zoom transition (iOS 18; plain cover on Reduce Motion)

struct WorkoutChatZoomSource: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let id: String
  let namespace: Namespace.ID

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 18.0, *), !reduceMotion {
      content.matchedTransitionSource(id: id, in: namespace)
    } else {
      content
    }
  }
}

struct WorkoutChatZoomDestination: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  let id: String
  let namespace: Namespace.ID

  @ViewBuilder
  func body(content: Content) -> some View {
    if #available(iOS 18.0, *), !reduceMotion {
      content.navigationTransition(.zoom(sourceID: id, in: namespace))
    } else {
      content
    }
  }
}
