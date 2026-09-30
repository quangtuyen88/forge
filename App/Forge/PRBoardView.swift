import ForgeCore
import SwiftData
import SwiftUI

struct LiftBest: Identifiable, Hashable {
  let exercise: Exercise
  let e1rm: Double
  let weightKg: Double
  let reps: Int
  let date: Date
  var id: String { exercise.id }
}

struct PRBoardView: View {
  let usesLb: Bool
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]

  private enum Sort: Hashable { case area, heaviest, newest }
  @State private var sort: Sort = .area
  @State private var selectedLift: LiftBest?

  private var events: [LogV3.RecordEvent] {
    LogV3.recordEvents(sessions: sessions)
  }

  private var lifts: [LiftBest] {
    var bests: [String: (e1rm: Double, date: Date, w: Double, r: Int)] = [:]
    for s in sessions where s.completed {
      for set in s.trustedSets {
        let e = Strength.epley(weightKg: set.weightKg, reps: set.reps)
        var v = bests[set.exerciseID] ?? (e1rm: 0, date: s.date, w: 0, r: 0)
        if e > v.e1rm { v.e1rm = e; v.date = s.date }
        if set.weightKg > v.w || (set.weightKg == v.w && set.reps > v.r) {
          v.w = set.weightKg
          v.r = set.reps
        }
        bests[set.exerciseID] = v
      }
    }
    return bests.compactMap { id, v in
      guard let exercise = ExerciseDB.find(id) else { return nil }
      return LiftBest(exercise: exercise, e1rm: v.e1rm, weightKg: v.w, reps: v.r, date: v.date)
    }
    .sorted { $0.e1rm > $1.e1rm }
  }

  private var sortedLifts: [LiftBest] {
    switch sort {
    case .heaviest: lifts
    case .newest: lifts.sorted { $0.date > $1.date }
    case .area: lifts
    }
  }

  private var freshCutoff: Date { Date.now.addingTimeInterval(-7 * 86400) }

  private var recordsByExercise: [String: Int] {
    var out: [String: Int] = [:]
    for event in events { out[event.exercise.id, default: 0] += 1 }
    return out
  }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        ProgressLargeTitle(
          title: "PR board",
          subtitle: String(localized: "Best estimated max for each lift", bundle: L10n.bundle),
          art: "art-goal")
          .padding(.horizontal, Theme.margin)
          .padding(.bottom, 8)

        if lifts.isEmpty {
          emptyState
        } else {
          summaryRow
          LogSegmented(
            choices: [
              LogSegmented.Choice(
                value: Sort.area, label: String(localized: "By area", bundle: L10n.bundle)),
              LogSegmented.Choice(
                value: Sort.heaviest, label: String(localized: "Heaviest", bundle: L10n.bundle)),
              LogSegmented.Choice(
                value: Sort.newest, label: String(localized: "Newest", bundle: L10n.bundle)),
            ],
            selection: $sort)
            .padding(.horizontal, Theme.margin)
            .padding(.top, 14)
          columnHeader
          if sort == .area {
            ForEach([BodyArea.legs, .push, .pull, .core], id: \.rawValue) { area in
              let rows = sortedLifts.filter { BodyArea($0.exercise.primary) == area }
              if !rows.isEmpty {
                groupHeader(area, count: rows.count)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, lift in
                  prRow(lift)
                  if index < rows.count - 1 {
                    rowDivider
                  }
                }
                .padding(.horizontal, Theme.margin)
              }
            }
          } else {
            ForEach(Array(sortedLifts.enumerated()), id: \.element.id) { index, lift in
              prRow(lift)
              if index < sortedLifts.count - 1 {
                rowDivider
              }
            }
            .padding(.horizontal, Theme.margin)
          }
          Text(
            String(
              localized: "Est. max = weight × (1 + reps ÷ 30), from your best set.",
              bundle: L10n.bundle)
          )
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Theme.margin)
          .padding(.top, 16)
          .padding(.bottom, 20)
        }
      }
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .progressTitleNavigation("PR board")
    .navigationDestination(item: $selectedLift) { lift in
      PRSheet(
        prs: events
          .filter { $0.exercise.id == lift.exercise.id }
          .sorted { $0.date > $1.date }
          .map {
            PRRecord(
              exercise: $0.exercise, e1rm: $0.e1rm, previous: $0.previousE1RM,
              weightKg: $0.weightKg, reps: $0.reps)
          },
        usesLb: usesLb,
        onClose: {},
        presentedAsSheet: false)
    }
  }

  private var rowDivider: some View {
    Rectangle().fill(Theme.ring).frame(height: 1)
  }

  private var summaryRow: some View {
    let fresh = lifts.filter { $0.date >= freshCutoff }.count
    let since = sessions.filter(\.completed).map(\.date).min()
    return HStack(spacing: 12) {
      LogIconBadge(symbol: "trophy.fill", tint: Theme.recordRing, round: true)
        .frame(width: 44, height: 44)
      VStack(alignment: .leading, spacing: 2) {
        Text(
          String(
            localized: "\(fresh) of \(lifts.count) bests set last week", bundle: L10n.bundle)
        )
        .forge(16, .semibold, tracking: -0.16)
        .monospacedDigit()
        if let since {
          Text(
            String(
              localized: "\(events.count) records since \(since.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))",
              bundle: L10n.bundle)
          )
          .forge(14)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
        }
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, Theme.margin)
    .padding(.top, 16)
    .accessibilityElement(children: .combine)
  }

  private var columnHeader: some View {
    HStack(spacing: 8) {
      Text("Lift")
        .forge(13, .medium)
        .foregroundStyle(Theme.textSecondary)
      Spacer(minLength: 0)
      Text("Best set")
        .forge(13, .medium)
        .foregroundStyle(Theme.textSecondary)
        .frame(width: 92, alignment: .trailing)
      HStack(spacing: 2) {
        if sort != .newest {
          Image(systemName: "arrow.up")
            .scaledSystemFont(13, weight: .semibold)
            .foregroundStyle(Theme.text)
            .accessibilityHidden(true)
        }
        Text("Est. max")
          .forge(13, .medium)
          .foregroundStyle(Theme.text)
      }
      .frame(width: 70, alignment: .trailing)
    }
    .padding(.horizontal, Theme.margin)
    .padding(.top, 18)
    .accessibilityElement(children: .combine)
  }

  private func groupHeader(_ area: BodyArea, count: Int) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(area.title)
        .forge(18, .semibold, tracking: -0.18)
      Spacer(minLength: 12)
      Text(String(localized: "\(count) lifts", bundle: L10n.bundle))
        .forge(14)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
    }
    .padding(.horizontal, Theme.margin)
    .padding(.top, 16)
    .padding(.bottom, 2)
  }

  private func prRow(_ lift: LiftBest) -> some View {
    let lb = usesLb
    let records = recordsByExercise[lift.exercise.id] ?? 0
    let fresh = lift.date >= freshCutoff
    let baseLabel = String(
      localized: "\(lift.exercise.localizedName), best set \(Fmt.num(UnitFormat.plain(lift.weightKg, usesLb: lb))) \(lb ? "lb" : "kg") for \(lift.reps) reps, estimated max \(Fmt.int(UnitFormat.plain(lift.e1rm, usesLb: lb))) \(lb ? "lb" : "kg")",
      bundle: L10n.bundle)
    let label =
      fresh
      ? baseLabel + String(localized: ", new record", bundle: L10n.bundle)
      : baseLabel
    return Button {
      selectedLift = lift
    } label: {
      HStack(spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(lift.exercise.localizedName)
            .forge(16, .semibold, tracking: -0.16)
            .foregroundStyle(Theme.text)
            .lineLimit(1)
          HStack(spacing: 4) {
            if fresh {
              Image(systemName: "trophy.fill")
                .scaledSystemFont(13, weight: .semibold)
                .foregroundStyle(Theme.recordRing)
                .accessibilityHidden(true)
            }
            Text(
              String(
                localized: "\(lift.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))) · \(records) record\(L10n.pluralSuffix(records))",
                bundle: L10n.bundle)
            )
            .forge(13)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
          }
        }
        Spacer(minLength: 0)
        Text(
          String(
            localized: "\(Fmt.num(UnitFormat.plain(lift.weightKg, usesLb: lb))) × \(lift.reps)",
            bundle: L10n.bundle)
        )
        .forge(15)
        .monospacedDigit()
        .foregroundStyle(Theme.textSecondary)
        .frame(width: 92, alignment: .trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        HStack(alignment: .firstTextBaseline, spacing: 2) {
          Text(Fmt.int(UnitFormat.plain(lift.e1rm, usesLb: lb)))
            .forge(18, .bold, tracking: -0.18)
            .monospacedDigit()
            .foregroundStyle(Theme.text)
          Text(lb ? "lb" : "kg")
            .forge(13, .medium)
            .foregroundStyle(Theme.textSecondary)
        }
        .frame(width: 70, alignment: .trailing)
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      }
      .frame(minHeight: 60)
      .contentShape(Rectangle())
      .accessibilityElement(children: .combine)
      .accessibilityLabel(label)
    }
    .buttonStyle(RowPressStyle())
  }

  private var emptyState: some View {
    VStack(spacing: 12) {
      Illustration(name: "art-empty-progress", height: 120)
      Text("No records yet")
        .forgeBodyStrong()
        .multilineTextAlignment(.center)
      Text("Every verified set feeds this board. Finish a workout and your bests land here.")
        .forgeLabel()
        .multilineTextAlignment(.center)
        .fixedSize(horizontal: false, vertical: true)
    }
    .frame(maxWidth: .infinity)
    .padding(Theme.margin)
    .padding(.vertical, 20)
  }
}
