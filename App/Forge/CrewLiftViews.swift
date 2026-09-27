import SwiftUI
import ForgeCore

/// "Crew on <lift>" card for the lift page (mock 06, DESIGN.md §8 and §12): one row per
/// lifter who shares the lift, each line drawn on that lifter's own scale, with a kudos
/// footer when someone else set a record on the lift this week.
struct CrewLiftCard: View {
  let exercise: Exercise
  let trend: LiftTrend?
  let isLb: Bool
  private var crew = CrewStore.shared

  private var unit: String { isLb ? "lb" : "kg" }

  /// The lifter's own row needs two workouts of their own to draw a line.
  private var showsYou: Bool { (trend?.workouts.count ?? 0) >= 2 }

  /// Others with at least two shared workouts of this lift, in snapshot member order.
  /// The card renders nothing without at least one of them.
  private var qualifiedLines: [(member: CrewMember, line: CrewLiftLine)] {
    guard let snapshot = crew.snapshot else { return [] }
    let lines = snapshot.lines(for: exercise.id)
    return snapshot.others.compactMap { member in
      lines.first { $0.userId == member.userId && $0.deltas.count >= 2 }
        .map { (member: member, line: $0) }
    }
  }

  private struct CrewRowModel: Identifiable {
    let id: String
    let name: String
    let initial: String
    let isYou: Bool
    let subline: String
    let valuesKg: [Double]
    let endIsRecord: Bool
    let changeKg: Double?
  }

  private var rowModels: [CrewRowModel] {
    var models: [CrewRowModel] = []
    guard let snapshot = crew.snapshot else { return models }
    if showsYou, let trend {
      let workouts = Array(trend.workouts.suffix(12))
      var subline = "\(Fmt.num(display(trend.latest.e1rmKg).rounded())) \(unit)"
      if trend.latestIsRecord {
        let day = trend.latest.date.formatted(
          .dateTime.month(.abbreviated).day().locale(L10n.locale))
        subline += " · " + String(localized: "Record \(day)", bundle: L10n.bundle)
      }
      models.append(
        CrewRowModel(
          id: "you",
          name: String(localized: "You", bundle: L10n.bundle),
          initial: snapshot.members.first(where: \.isSelf)?.initial ?? "Y",
          isYou: true,
          subline: subline,
          valuesKg: workouts.map(\.e1rmKg),
          endIsRecord: trend.latestIsRecord,
          changeKg: workouts.count >= 2 ? workouts.last!.e1rmKg - workouts.first!.e1rmKg : nil))
    }
    for (member, line) in qualifiedLines {
      models.append(
        CrewRowModel(
          id: member.userId,
          name: member.name,
          initial: member.initial,
          isYou: false,
          subline: subline(for: line, snapshot: snapshot),
          valuesKg: line.deltas,
          endIsRecord: line.record,
          changeKg: line.changeKg))
    }
    return models
  }

  var body: some View {
    if !qualifiedLines.isEmpty {
      VStack(spacing: 12) {
        HStack(alignment: .firstTextBaseline) {
          Text("Crew on \(exercise.localizedName)")
            .forgeSection()
            .lineLimit(2)
          Spacer(minLength: 8)
          Text("Last 12 workouts")
            .forge(15)
            .foregroundStyle(Theme.textSecondary)
        }
        SkyCard {
          rows
        } footer: {
          kudosFooter
        }
        Text("Each line uses that lifter's own scale.")
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .frame(maxWidth: .infinity)
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("lift.crew")
    }
  }

  private var rows: some View {
    let models = rowModels
    return VStack(spacing: 0) {
      ForEach(Array(models.enumerated()), id: \.element.id) { index, model in
        if index > 0 {
          hairline
        }
        row(model)
      }
    }
  }

  /// One lifter's line: avatar, name and last-workout subline, then the trend and its change.
  private func row(_ model: CrewRowModel) -> some View {
    HStack(spacing: 12) {
      CrewAvatar(initial: model.initial, isYou: model.isYou, size: 40)
      VStack(alignment: .leading, spacing: 2) {
        Text(model.name)
          .forge(17, .semibold)
          .foregroundStyle(Theme.text)
          .lineLimit(1)
        Text(model.subline)
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 8)
      LiftSparkline(valuesKg: model.valuesKg, endIsRecord: model.endIsRecord)
        .frame(width: 60, height: 28)
      TrendChangeText(changeKg: model.changeKg, isLb: isLb)
    }
    .frame(minHeight: 64)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(rowLabel(model))
    .accessibilityIdentifier("lift.crew.\(model.id)")
  }

  private func rowLabel(_ model: CrewRowModel) -> String {
    let change = TrendChangeText.label(changeKg: model.changeKg, isLb: isLb)
    return "\(model.name), \(change), \(model.subline)"
  }

  /// Kudos footer for the newest record on this lift this week by someone else.
  @ViewBuilder private var kudosFooter: some View {
    if let snapshot = crew.snapshot,
      let record = snapshot.records.first(where: {
        !$0.isSelf && $0.exerciseId == exercise.id && isInsideWeek($0.date, snapshot: snapshot)
      }),
      let current = snapshot.records.first(where: { $0.postId == record.postId })
    {
      let name = current.displayName ?? current.handle ?? "—"
      Button {
        Task { await crew.toggleKudos(current) }
      } label: {
        FooterStrip(
          symbol: current.kudoed ? "hands.clap.fill" : "hands.clap",
          title: current.kudoed ? "Kudos sent to \(name)" : "Kudos for \(name)'s record",
          showsChevron: false)
      }
      .buttonStyle(RowPressStyle())
      .sensoryFeedback(.impact(weight: .light), trigger: current.kudoed)
      .accessibilityIdentifier("lift.crew.kudos")
    }
  }

  private var hairline: some View {
    Divider().overlay(Theme.ring).padding(.leading, 52)
  }

  /// "Record Mon" for a record this week, "Last workout Tue" this week, else "Last workout Sep 21".
  private func subline(for line: CrewLiftLine, snapshot: CrewSnapshot) -> String {
    guard let date = CrewWeek.date(from: line.lastDate) else { return "" }
    let thisWeek = isInsideWeek(line.lastDate, snapshot: snapshot)
    if thisWeek {
      let weekday = date.formatted(.dateTime.weekday(.abbreviated).locale(L10n.locale))
      if line.record {
        return String(localized: "Record \(weekday)", bundle: L10n.bundle)
      }
      return String(localized: "Last workout \(weekday)", bundle: L10n.bundle)
    }
    let day = date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
    return String(localized: "Last workout \(day)", bundle: L10n.bundle)
  }

  private func isInsideWeek(_ day: String, snapshot: CrewSnapshot) -> Bool {
    guard
      let start = CrewWeek.date(from: snapshot.weekStart),
      let end = CrewWeek.calendar.date(byAdding: .day, value: 7, to: start),
      let date = CrewWeek.date(from: day)
    else { return false }
    return date >= start && date < end
  }

  private func display(_ kg: Double) -> Double {
    isLb ? Plates.kgToLb(kg) : kg
  }
}
