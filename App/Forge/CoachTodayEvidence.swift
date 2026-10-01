import SwiftUI
import SwiftData
import ForgeCore

/// Today's planned session under the coach's answer: one row per lift and Start.
struct TodayPlanEvidence: View {
  let day: PlannedDay
  /// Exercise id -> suggested kg, resolved by CoachView.
  let loads: [String: Double]
  let usesLb: Bool
  let startTitle: String
  let onStart: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      ForEach(day.exercises, id: \.exercise.id) { planned in
        HStack(spacing: 12) {
          CoachSceneTile(scene: .forExercise(planned.exercise), size: 44)
          VStack(alignment: .leading, spacing: 2) {
            Text(planned.exercise.localizedName).forge(15, .medium).lineLimit(2)
            Text(detail(planned)).forge(13).foregroundStyle(Theme.textSecondary).monospacedDigit()
          }
          Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
      }
      Button { onStart() } label: {
        Text(startTitle)
          .frame(maxWidth: .infinity)
      }
      .buttonStyle(PillButtonStyle(minHeight: 50))
      .accessibilityIdentifier("coach.todayPlan.start")
    }
    .padding(14)
    .background(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.innerSurface))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("coach.todayPlan")
  }

  /// "<sets> × <low>–<high> · <load>"; bodyweight when no load is suggested.
  private func detail(_ planned: PlannedExercise) -> String {
    let range = "\(planned.repRange.lowerBound)–\(planned.repRange.upperBound)"
    if let kg = loads[planned.exercise.id] {
      return String(
        localized: "\(planned.sets) × \(range) · \(Fmt.kg(usesLb ? Plates.kgToLb(kg) : kg, lb: usesLb))",
        bundle: L10n.bundle)
    }
    return String(localized: "\(planned.sets) × \(range) · Bodyweight", bundle: L10n.bundle)
  }
}

/// The last completed workout under the coach's answer: duration, sets, load, the record if
/// one landed, and each lift.
struct LastWorkoutEvidence: View {
  let session: WorkoutSession
  let usesLb: Bool
  let onOpen: () -> Void
  /// The history the record baseline needs; the card reads it itself so callers pass one session.
  @Query(sort: \WorkoutSession.date) private var allSessions: [WorkoutSession]

  /// The records this session set: the same walk History's record chips use.
  private var records: [LogV3.RecordEvent] {
    LogV3.recordEvents(sessions: allSessions).filter { $0.session == session }
  }

  /// One lift of the session, in training order: set count, best reps, heaviest load.
  private struct LiftRow: Identifiable {
    let id: String
    let exercise: Exercise?
    let name: String
    let sets: Int
    let reps: Int
    let load: Double?
  }

  private var liftRows: [LiftRow] {
    var order: [String] = []
    var stats: [String: (sets: Int, reps: Int, load: Double?)] = [:]
    // Training order across exercises comes from loggedAt; setIndex only orders sets within one exercise.
    for set in session.sets.sorted(by: {
      $0.loggedAt != $1.loggedAt ? $0.loggedAt < $1.loggedAt : $0.setIndex < $1.setIndex
    }) {
      if stats[set.exerciseID] == nil { order.append(set.exerciseID) }
      var s = stats[set.exerciseID] ?? (sets: 0, reps: 0, load: nil)
      s.sets += 1
      s.reps = max(s.reps, set.reps)
      if set.weightKg > (s.load ?? 0) { s.load = set.weightKg }
      stats[set.exerciseID] = s
    }
    return order.map {
      let s = stats[$0] ?? (sets: 0, reps: 0, load: nil)
      return LiftRow(
        id: $0, exercise: ExerciseDB.find($0), name: ExerciseDB.find($0)?.localizedName ?? $0,
        sets: s.sets, reps: s.reps, load: s.load)
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(spacing: 12) {
        stat(value: SessionMath.durationText([session]), label: String(localized: "Duration", bundle: L10n.bundle))
        stat(value: "\(session.sets.count)", label: String(localized: "Sets", bundle: L10n.bundle))
        stat(
          value: SessionMath.tonnageText([session], usesLb: usesLb), unit: usesLb ? "lb" : "kg",
          label: String(localized: "Load", bundle: L10n.bundle))
      }
      if let record = records.first {
        HStack(spacing: 12) {
          CoachSceneTile(scene: .record, size: 44)
          VStack(alignment: .leading, spacing: 2) {
            Text(String(localized: "New record", bundle: L10n.bundle))
              .forge(12, .semibold)
              .foregroundStyle(Theme.recordInk)
              .padding(.horizontal, 8)
              .padding(.vertical, 3)
              .background(Capsule().fill(Theme.recordTint))
            Text(
              String(
                localized: "\(record.exercise.localizedName) · \(record.reps) × \(Fmt.kg(usesLb ? Plates.kgToLb(record.weightKg) : record.weightKg, lb: usesLb))",
                bundle: L10n.bundle)
            )
            .forge(13)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
          }
        }
        .accessibilityElement(children: .combine)
      }
      VStack(alignment: .leading, spacing: 8) {
        ForEach(liftRows) { row in
          HStack(spacing: 12) {
            CoachSceneTile(scene: row.exercise.map(CoachScene.forExercise) ?? .why, size: 44)
            VStack(alignment: .leading, spacing: 2) {
              Text(row.name).forge(15, .medium).lineLimit(2)
              Text(
                String(
                  localized: "\(row.sets) × \(row.reps) · \(row.load.flatMap { $0 > 0 ? $0 : nil }.map { Fmt.kg(usesLb ? Plates.kgToLb($0) : $0, lb: usesLb) } ?? String(localized: "Bodyweight", bundle: L10n.bundle))",
                  bundle: L10n.bundle)
              )
              .forge(13)
              .foregroundStyle(Theme.textSecondary)
              .monospacedDigit()
            }
            Spacer(minLength: 0)
          }
          .accessibilityElement(children: .combine)
        }
      }
      .padding(.top, 2)
      Button { onOpen() } label: {
        HStack(spacing: 4) {
          Text(String(localized: "Open workout", bundle: L10n.bundle))
            .forge(15, .semibold)
            .foregroundStyle(Theme.accentText)
          Image(systemName: "chevron.forward")
            .scaledSystemFont(13, weight: .semibold)
            .foregroundStyle(Theme.accentText)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
      }
      .accessibilityIdentifier("coach.lastWorkout.open")
    }
    .padding(14)
    .background(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous).fill(Theme.innerSurface))
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("coach.lastWorkout")
  }

  /// One big numeral with its small label and unit, as the session summary lays stats out.
  private func stat(value: String, unit: String? = nil, label: String) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(value).forge(20, .semibold).foregroundStyle(Theme.text).monospacedDigit()
        if let unit { Text(unit).forge(12).foregroundStyle(Theme.textSecondary) }
      }
      Text(label).forge(12).foregroundStyle(Theme.textSecondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}
