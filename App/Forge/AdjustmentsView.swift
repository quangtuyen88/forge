import ForgeCore
import SwiftData
import SwiftUI

// MARK: - List

struct AdjustmentsView: View {
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \CheckIn.date) private var checkIns: [CheckIn]
  @Query(sort: \DecisionLogEntry.date, order: .reverse) private var decisions: [DecisionLogEntry]
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var approving: VolumeIncrease?
  @State private var showHow = false
  @Namespace private var zoom
  @ScaledMetric(relativeTo: .body) private var trailingColumnWidth: CGFloat = 62
  /// Scales with Dynamic Type so lane rows can grow at accessibility sizes; 84 at the default.
  @ScaledMetric(relativeTo: .body) private var laneRowHeight: CGFloat = 84

  /// Space every lane row, the column header and the week band reserve to the right of the
  /// chart strip: outcome column (62) + two 10 gaps + chevron (13).
  private static let trailingReserve: CGFloat = 62 + 10 + 10 + 13

  private var profile: UserProfile? { profiles.first }

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        if let profile {
          let model = AdjustmentsModel.build(
            profile: profile, sessions: sessions, decisions: decisions)
          let pending = VolumeApprovals.increases(
            profile: profile, sessions: sessions, checkIns: checkIns
          ).filter { $0.answer == nil }
          FieldSection(bottom: 20) {
            fieldTop(model, pending: pending)
          }
          VStack(spacing: 0) {
            if !model.lanes.isEmpty {
              blockSection(model, pending: pending, profile: profile)
            }
            if !model.others.isEmpty {
              othersSection(model)
            }
            if model.isEmpty && pending.isEmpty {
              emptySection
            }
            if model.measuredCount > 0 {
              footer
            }
          }
          .background(Theme.page)
        }
      }
      .padding(.bottom, 30)
    }
    .progressFieldPage(String(localized: "Adjustments", bundle: L10n.bundle))
    .accessibilityIdentifier("adjustments.list")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showHow = true
        } label: {
          Image(systemName: "info.circle")
            .foregroundStyle(Theme.text)
        }
        .accessibilityLabel(Text(String(localized: "How adjustments work", bundle: L10n.bundle)))
        .accessibilityIdentifier("adjustments.info")
      }
    }
    .sheet(isPresented: $showHow) { AdjustmentsHowSheet() }
    .sheet(item: $approving) { increase in
      VolumeApprovalSheet(
        increase: increase,
        coachName: Coach.from(coachID).name,
        onApprove: {
          withAnimation(reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.3)) {
            VolumeApprovals.approve(increase)
          }
        },
        onKeep: {
          withAnimation(reduceMotion ? nil : .timingCurve(0.23, 1, 0.32, 1, duration: 0.3)) {
            VolumeApprovals.keep(increase)
          }
        })
    }
  }

  // MARK: Field

  /// The field: the measured-changes sentence, the dots, and the ask that waits.
  private func fieldTop(_ model: AdjustmentsModel, pending: [VolumeIncrease]) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .top, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
          Text(fieldTitle(model))
            .forge(30, .bold, tracking: -0.5)
            .foregroundStyle(Theme.text)
            .accessibilityAddTraits(.isHeader)
            .fixedSize(horizontal: false, vertical: true)
          if let date = model.earliestChangeDate {
            Text(
              String(
                localized: "You applied \(model.changes.count) changes since \(date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))).",
                bundle: L10n.bundle)
            )
            .forge(15)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
          }
        }
        Spacer(minLength: 8)
        Image("art-plan")
          .resizable()
          .scaledToFit()
          .frame(width: 64, height: 64)
          .accessibilityHidden(true)
      }
      if model.measuredCount > 0 {
        dotsRow(model)
        legendRow(model)
      }
      ForEach(pending) { increase in
        pendingAsk(increase)
      }
    }
  }

  /// The measured-changes sentence; measuring counts ride along instead of a legend dot.
  private func fieldTitle(_ model: AdjustmentsModel) -> String {
    guard model.measuredCount > 0 else {
      return String(localized: "No changes measured yet.", bundle: L10n.bundle)
    }
    if model.measuringCount > 0 {
      return String(
        localized: "\(model.betterCount) of \(model.measuredCount) changes measured better. \(model.measuringCount) still measuring.",
        bundle: L10n.bundle)
    }
    return String(
      localized: "\(model.betterCount) of \(model.measuredCount) changes measured better.",
      bundle: L10n.bundle)
  }

  /// One dot per measured change, oldest first; the legend is the accessible text.
  private func dotsRow(_ model: AdjustmentsModel) -> some View {
    LazyVGrid(
      columns: [GridItem(.adaptive(minimum: 16), spacing: 6)], alignment: .leading, spacing: 6
    ) {
      ForEach(model.changes.filter { $0.outcome != .measuring }) { change in
        outcomeDot(change.outcome, diameter: 10)
      }
    }
    .padding(.top, 16)
    .accessibilityHidden(true)
  }

  /// One measured change as a dot: filled green, filled grey, hollow for undone.
  private func outcomeDot(
    _ outcome: AdjustmentsModel.AppliedChange.Outcome, diameter: CGFloat
  ) -> some View {
    Group {
      switch outcome {
      case .better: Circle().fill(Theme.positive)
      case .noChange, .measuring: Circle().fill(Theme.textSecondary)
      case .undone: Circle().strokeBorder(Theme.textSecondary, lineWidth: 1.5)
      }
    }
    .frame(width: diameter, height: diameter)
  }

  @ViewBuilder
  private func legendRow(_ model: AdjustmentsModel) -> some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 14) { legendItems(model) }
      VStack(alignment: .leading, spacing: 4) { legendItems(model) }
    }
    .forge(13)
    .foregroundStyle(Theme.textSecondary)
    .padding(.top, 8)
  }

  @ViewBuilder
  private func legendItems(_ model: AdjustmentsModel) -> some View {
    if model.betterCount > 0 {
      legendItem(.better, String(localized: "\(model.betterCount) better", bundle: L10n.bundle))
    }
    if model.noChangeCount > 0 {
      legendItem(
        .noChange, String(localized: "\(model.noChangeCount) no change", bundle: L10n.bundle))
    }
    if model.undoneCount > 0 {
      legendItem(.undone, String(localized: "\(model.undoneCount) undone", bundle: L10n.bundle))
    }
  }

  private func legendItem(
    _ outcome: AdjustmentsModel.AppliedChange.Outcome, _ text: String
  ) -> some View {
    HStack(spacing: 6) {
      outcomeDot(outcome, diameter: 8)
      Text(text)
    }
  }

  /// One pending increase as a field row with a Review pill; the hairline separates asks.
  private func pendingAsk(_ increase: VolumeIncrease) -> some View {
    let added = increase.toSets - increase.fromSets
    let title = String(
      localized: "Add \(added) \(increase.exercise.localizedName) set\(L10n.pluralSuffix(added))",
      bundle: L10n.bundle)
    return VStack(spacing: 0) {
      Rectangle().fill(Theme.ring).frame(height: 1)
      HStack(spacing: 12) {
        LiftToken(exercise: increase.exercise, size: 40)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .forge(15, .semibold)
            .foregroundStyle(Theme.text)
          Text(
            String(
              localized: "Needs your OK · \(localizedDayName(increase.dayName))",
              bundle: L10n.bundle)
          )
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
        }
        Spacer(minLength: 8)
        Button {
          approving = increase
        } label: {
          Text(String(localized: "Review", bundle: L10n.bundle))
            .forge(15, .semibold)
            .foregroundStyle(Theme.onAccent)
            .padding(.horizontal, 16)
            .frame(height: 36)
            .background(Capsule().fill(Theme.accentStrong))
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowPressStyle())
        .accessibilityLabel(
          Text(String(localized: "Review \(title)", bundle: L10n.bundle)))
        .accessibilityIdentifier("adjustments.pending")
      }
      .padding(.top, 12)
    }
    .padding(.top, 18)
  }

  // MARK: Block canvas

  /// The "This block" section: flat lanes with hairlines, and the canvas legend.
  private func blockSection(
    _ model: AdjustmentsModel, pending: [VolumeIncrease], profile: UserProfile
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text(String(localized: "This block", bundle: L10n.bundle))
          .forge(20, .bold)
          .foregroundStyle(Theme.text)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 12)
        Text(
          String(
            localized: "Block \(model.blockNumber) · week \(model.currentWeek) of \(Mesocycle.weeks)",
            bundle: L10n.bundle)
        )
        .forge(13)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 24)
      .padding(.bottom, 4)
      canvasGrid(model, pending: pending, profile: profile)
        .padding(.horizontal, Theme.margin)
      canvasLegend
    }
  }

  private func canvasGrid(
    _ model: AdjustmentsModel, pending: [VolumeIncrease], profile: UserProfile
  ) -> some View {
    VStack(spacing: 0) {
      columnHeader(model)
      ForEach(Array(model.lanes.enumerated()), id: \.element.id) { index, lane in
        if index > 0 { laneHairline }
        NavigationLink {
          AdjustmentDetailView(exerciseID: lane.exercise.id)
            .modifier(AdjustmentZoomDestination(id: lane.exercise.id, namespace: zoom))
        } label: {
          laneRow(lane, model: model, profile: profile, pending: pending)
            .modifier(AdjustmentZoomSource(id: lane.exercise.id, namespace: zoom))
        }
        .buttonStyle(LanePressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          Text(laneLabel(lane, model: model, profile: profile, pending: pending)))
        .accessibilityValue(Text(laneValue(lane, profile: profile)))
        .accessibilityIdentifier("adjustments.lane.\(lane.exercise.id)")
      }
    }
    .background(
      currentWeekBand(
        lanes: model.lanes.count, columns: model.weeks.count)
    )
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("adjustments.canvas")
  }

  /// What a lane row reads as: the pending ask when one waits, else the block change and its
  /// measured outcome word.
  private func laneLabel(
    _ lane: AdjustmentsModel.Lane, model: AdjustmentsModel, profile: UserProfile,
    pending: [VolumeIncrease]
  ) -> String {
    if let increase = pending.first(where: { $0.exercise.id == lane.exercise.id }) {
      return String(
        localized: "\(lane.exercise.localizedName), add \(increase.toSets - increase.fromSets) sets, needs your OK",
        bundle: L10n.bundle)
    }
    var label = String(
      localized: "\(lane.exercise.localizedName), \(laneChangeText(lane, profile: profile)) this block",
      bundle: L10n.bundle)
    if let change = model.changes.last(where: { $0.exerciseID == lane.exercise.id }) {
      label += ", " + outcomeWord(change.outcome)
    }
    return label
  }

  private var laneHairline: some View {
    Rectangle()
      .fill(Theme.ring)
      .frame(height: 1)
      .padding(.leading, 46)
  }

  /// The week-by-week levels the lane chart draws, as the lane's spoken value.
  private func laneValue(_ lane: AdjustmentsModel.Lane, profile: UserProfile) -> String {
    let isLb = profile.usesLb
    var value = 0.0
    var parts: [String] = []
    for step in lane.steps {
      value += step.delta
      let level: String
      if lane.unit == .sets {
        let n = Int(value.rounded())
        level = "+\(n) set\(L10n.pluralSuffix(n))"
      } else {
        let shown = isLb ? Plates.kgToLb(value) : value
        level = (value > 0 ? "+" : "") + Fmt.num(shown, max: 1) + (isLb ? " lb" : " kg")
      }
      parts.append(String(localized: "Week \(step.week) \(level)", bundle: L10n.bundle))
    }
    return parts.joined(separator: ", ")
  }

  private func columnHeader(_ model: AdjustmentsModel) -> some View {
    HStack(spacing: 10) {
      Color.clear.frame(width: 36)
      HStack(spacing: 0) {
        ForEach(Array(model.weeks.enumerated()), id: \.element) { index, week in
          Group {
            if index == model.weeks.count - 1 {
              Text(String(localized: "Now", bundle: L10n.bundle))
                .forge(12, .bold)
                .foregroundStyle(Theme.accentText)
            } else if let start = model.weekStarts[week] {
              Text(start.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))
                .forge(12, .medium)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
            } else {
              Text(verbatim: "")
            }
          }
          .frame(maxWidth: .infinity)
        }
      }
      Color.clear.frame(width: Self.trailingReserve - 10)
    }
    .frame(height: 22)
    .padding(.top, 12)
  }

  /// Tinted band behind the current week's column, header labels included.
  private func currentWeekBand(lanes: Int, columns: Int) -> some View {
    GeometryReader { geo in
      let stripX: CGFloat = 46
      let stripW = geo.size.width - stripX - Self.trailingReserve
      let colW = stripW / CGFloat(max(1, columns))
      let height: CGFloat = 30 + laneRowHeight * CGFloat(lanes)
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Theme.accentTint)
        .frame(width: max(0, colW - 6), height: height)
        .position(x: stripX + colW * (CGFloat(columns) - 0.5), y: 8 + height / 2)
    }
  }

  private func laneRow(
    _ lane: AdjustmentsModel.Lane, model: AdjustmentsModel, profile: UserProfile,
    pending: [VolumeIncrease]
  ) -> some View {
    HStack(spacing: 10) {
      LiftToken(exercise: lane.exercise, size: 36)
      VStack(alignment: .leading, spacing: 2) {
        Text(lane.exercise.localizedName)
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
          .lineLimit(1)
        LoadLaneChart(
          lane: lane, weeks: model.weeks, currentWeek: model.currentWeek,
          rise: risePerUnit(lane), isLb: profile.usesLb,
          pending: pending.contains { $0.exercise.id == lane.exercise.id })
      }
      laneTrailing(lane, model: model, profile: profile)
      Image(systemName: "chevron.forward")
        .scaledSystemFont(13, weight: .semibold)
        .foregroundStyle(Theme.textSecondary)
        .frame(width: 13)
    }
    .frame(minHeight: laneRowHeight)
  }

  /// The lane's value and, under it, the outcome word of its latest change.
  @ViewBuilder
  private func laneTrailing(
    _ lane: AdjustmentsModel.Lane, model: AdjustmentsModel, profile: UserProfile
  ) -> some View {
    VStack(alignment: .trailing, spacing: 0) {
      Text(verbatim: laneChangeText(lane, profile: profile))
        .forge(15, .medium)
        .foregroundStyle(lane.total > 0 ? Theme.positiveText : Theme.text)
        .monospacedDigit()
        .lineLimit(1)
        .minimumScaleFactor(0.7)
      if let change = model.changes.last(where: { $0.exerciseID == lane.exercise.id }) {
        Text(outcomeWord(change.outcome))
          .forge(13, change.outcome == .better ? .semibold : .medium)
          .foregroundStyle(
            change.outcome == .better ? Theme.positiveText : Theme.textSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
    }
    .frame(width: trailingColumnWidth, alignment: .trailing)
    .padding(.top, 1)
    .frame(maxHeight: .infinity, alignment: .top)
  }

  /// Pt of rise per kg or per set, so the widest lane swing (peak minus trough) stays inside
  /// the 36 pt above its base line.
  private func risePerUnit(_ lane: AdjustmentsModel.Lane) -> CGFloat {
    let maxSpan = laneSpan(lane)
    let cap: CGFloat = lane.unit == .sets ? 14 : 5
    guard maxSpan > 0 else { return cap }
    return CGFloat(min(Double(cap), 36 / maxSpan))
  }

  /// Difference between the highest and lowest cumulative level of a lane,
  /// counting the starting level of 0.
  private func laneSpan(_ lane: AdjustmentsModel.Lane) -> Double {
    var minLevel = 0.0
    var maxLevel = 0.0
    var level = 0.0
    for step in lane.steps {
      level += step.delta
      minLevel = min(minLevel, level)
      maxLevel = max(maxLevel, level)
    }
    return maxLevel - minLevel
  }

  private func laneChangeText(_ lane: AdjustmentsModel.Lane, profile: UserProfile) -> String {
    if lane.unit == .sets {
      let n = Int(lane.total.rounded())
      return String(localized: "+\(n) set\(L10n.pluralSuffix(n))", bundle: L10n.bundle)
    }
    let isLb = profile.usesLb
    let display = isLb ? Plates.kgToLb(lane.total) : lane.total
    let sign = lane.total > 0 ? "+" : (lane.total < 0 ? "\u{2212}" : "")
    return "\(sign)\(Fmt.num(abs(display))) \(isLb ? "lb" : "kg")"
  }

  private func outcomeWord(_ outcome: AdjustmentsModel.AppliedChange.Outcome) -> String {
    switch outcome {
    case .better: return String(localized: "Better", bundle: L10n.bundle)
    case .noChange: return String(localized: "No change", bundle: L10n.bundle)
    case .measuring: return String(localized: "Measuring", bundle: L10n.bundle)
    case .undone: return String(localized: "Undone", bundle: L10n.bundle)
    }
  }

  /// Canvas legend: applied dot, planned-or-waiting ring, current-week band.
  private var canvasLegend: some View {
    ViewThatFits(in: .horizontal) {
      HStack(spacing: 16) { legendBody }
      VStack(alignment: .leading, spacing: 4) { legendBody }
    }
    .forge(12)
    .foregroundStyle(Theme.textSecondary)
    .padding(.horizontal, Theme.margin)
    .padding(.top, 12)
    .accessibilityHidden(true)
  }

  @ViewBuilder
  private var legendBody: some View {
    HStack(spacing: 6) {
      Circle().fill(Theme.accent).frame(width: 9, height: 9)
      Text(String(localized: "Applied", bundle: L10n.bundle))
    }
    HStack(spacing: 6) {
      Circle().strokeBorder(Theme.accent, lineWidth: 2).frame(width: 9, height: 9)
      Text(String(localized: "Planned or waiting", bundle: L10n.bundle))
    }
    HStack(spacing: 6) {
      RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
        .fill(Theme.accentTint)
        .frame(width: 12, height: 12)
      Text(String(localized: "This week", bundle: L10n.bundle))
    }
  }

  // MARK: Other changes

  /// The "Other changes" section: hairline rows, outcome word for measurable ones.
  private func othersSection(_ model: AdjustmentsModel) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(String(localized: "Other changes", bundle: L10n.bundle))
        .forge(20, .bold)
        .foregroundStyle(Theme.text)
        .accessibilityAddTraits(.isHeader)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 24)
        .padding(.bottom, 4)
      VStack(spacing: 0) {
        ForEach(Array(model.others.enumerated()), id: \.element.id) { index, other in
          otherRow(other, model: model)
          if index < model.others.count - 1 {
            Divider().padding(.leading, Theme.margin)
          }
        }
      }
      .accessibilityElement(children: .contain)
      .accessibilityIdentifier("adjustments.others")
    }
  }

  private func otherRow(_ other: AdjustmentsModel.Other, model: AdjustmentsModel) -> some View {
    HStack {
      Text(other.title)
        .forge(15, .semibold)
        .foregroundStyle(Theme.text)
        .lineLimit(2)
      Spacer(minLength: 8)
      otherTrailing(other, model: model)
    }
    .padding(.horizontal, Theme.margin)
    .padding(.vertical, 10)
    .frame(minHeight: 50)
    .accessibilityIdentifier("adjustments.other.\(other.id)")
  }

  @ViewBuilder
  private func otherTrailing(_ other: AdjustmentsModel.Other, model: AdjustmentsModel) -> some View {
    if other.status == .applied, let id = other.exerciseID,
      let change = model.changes.first(where: {
        $0.exerciseID == id && Calendar.current.isDate($0.date, inSameDayAs: other.date)
      })
    {
      Text(outcomeWord(change.outcome))
        .forge(15, change.outcome == .better ? .semibold : .medium)
        .foregroundStyle(
          change.outcome == .better ? Theme.positiveText : Theme.textSecondary)
    } else {
      switch other.status {
      case .undone:
        Text(String(localized: "Undone", bundle: L10n.bundle))
          .forge(15, .medium)
          .foregroundStyle(Theme.textSecondary)
      case .notApplied:
        Text(String(localized: "Not applied", bundle: L10n.bundle))
          .forge(15, .medium)
          .foregroundStyle(Theme.textSecondary)
      case .applied:
        if let n = other.fewerSets {
          Text(String(localized: "\(n) fewer set\(L10n.pluralSuffix(n))", bundle: L10n.bundle))
            .forge(15, .semibold)
            .foregroundStyle(Theme.text)
            .monospacedDigit()
        } else {
          Text(other.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))
            .forge(15, .medium)
            .foregroundStyle(Theme.textSecondary)
            .monospacedDigit()
        }
      }
    }
  }

  // MARK: Empty and footer

  private var emptySection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(String(localized: "No changes yet", bundle: L10n.bundle))
        .forge(17, .semibold)
        .foregroundStyle(Theme.text)
      Text(
        String(
          localized: "\(Coach.from(coachID).name) checks every lift after each session. Weight goes up when all sets hit the top of the range.",
          bundle: L10n.bundle)
      )
      .forge(15)
      .foregroundStyle(Theme.textSecondary)
      .padding(.top, 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Theme.margin)
    .padding(.top, 24)
    .accessibilityIdentifier("adjustments.empty")
  }

  private var footer: some View {
    Text(
      String(
        localized: "Better means the lift beat its best estimated max after the change.",
        bundle: L10n.bundle)
    )
    .forge(13)
    .foregroundStyle(Theme.textSecondary)
    .fixedSize(horizontal: false, vertical: true)
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(.horizontal, Theme.margin)
    .padding(.top, 20)
  }
}

// MARK: - Lane charts

private struct LoadLaneChart: View {
  let lane: AdjustmentsModel.Lane
  let weeks: [Int]
  let currentWeek: Int
  let rise: CGFloat
  let isLb: Bool
  var pending = false
  /// Scales with Dynamic Type alongside the row height it is drawn in; 56 at the default.
  @ScaledMetric(relativeTo: .body) private var base: CGFloat = 56

  var body: some View {
    GeometryReader { geo in
      Canvas { context, _ in
        let colW = geo.size.width / CGFloat(max(1, weeks.count))
        let end = colW * (CGFloat(weeks.count) - 0.5)
        var minLevel = 0.0
        var level0 = 0.0
        for step in lane.steps {
          level0 += step.delta
          minLevel = min(minLevel, level0)
        }
        // minLevel ≤ 0, so a lane that drops starts higher and its lowest point sits at the base.
        let start = base + CGFloat(minLevel) * rise
        func cx(_ column: Int) -> CGFloat { colW * (CGFloat(column) + 0.5) }

        var path = Path()
        path.move(to: CGPoint(x: 0, y: start))
        var y = start
        var lastX: CGFloat = 0
        for step in lane.steps {
          guard let column = weeks.firstIndex(of: step.week) else { continue }
          let x = cx(column)
          path.addLine(to: CGPoint(x: x, y: y))
          y -= CGFloat(step.delta) * rise
          path.addLine(to: CGPoint(x: x, y: y))
          lastX = x
        }
        if pending {
          var dash = Path()
          dash.move(to: CGPoint(x: lastX, y: y))
          dash.addLine(to: CGPoint(x: end, y: y))
          context.stroke(
            dash, with: .color(Theme.accent),
            style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [3, 3]))
        } else {
          path.addLine(to: CGPoint(x: end, y: y))
        }
        context.stroke(
          path,
          with: .color(Theme.accent),
          style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        var level = start
        var value = 0.0
        for step in lane.steps {
          guard let column = weeks.firstIndex(of: step.week) else { continue }
          level -= CGFloat(step.delta) * rise
          value += step.delta
          let center = CGPoint(x: cx(column), y: level)
          let ring = Path(
            ellipseIn: CGRect(x: center.x - 5.5, y: center.y - 5.5, width: 11, height: 11))
          if step.week == currentWeek {
            context.fill(ring, with: .color(Theme.page))
            context.stroke(ring, with: .color(Theme.accent), lineWidth: 2.5)
          } else {
            context.fill(ring, with: .color(Theme.accent))
            context.stroke(ring, with: .color(Theme.page), lineWidth: 2.5)
          }
          // The change since the block started rides above its ring, signed; load lanes speak the profile's unit.
          let shown = lane.unit == .sets ? value : (isLb ? Plates.kgToLb(value) : value)
          context.draw(
            Text((shown > 0 ? "+" : "") + Fmt.num(shown))
              .font(.forge(12, .medium))
              .monospacedDigit()
              .foregroundStyle(Theme.textSecondary),
            at: CGPoint(x: center.x, y: center.y - 13))
        }
        if pending {
          let ring = Path(ellipseIn: CGRect(x: end - 6, y: y - 6, width: 12, height: 12))
          context.fill(ring, with: .color(Theme.page))
          context.stroke(ring, with: .color(Theme.accent), lineWidth: 2.5)
        }
      }
    }
  }
}

/// Opacity-only press for lane rows: a pressed ring must never slide off the band.
private struct LanePressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    PressFeedback(isPressed: configuration.isPressed, scale: 1, pressedOpacity: 0.72) {
      configuration.label
    }
  }
}

// MARK: - Zoom transition (iOS 18; plain push on Reduce Motion)

private struct AdjustmentZoomSource: ViewModifier {
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

private struct AdjustmentZoomDestination: ViewModifier {
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

// MARK: - Detail

struct AdjustmentDetailView: View {
  let exerciseID: String
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \DecisionLogEntry.date, order: .reverse) private var decisions: [DecisionLogEntry]
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue

  private var profile: UserProfile? { profiles.first }
  private var detail: AdjustmentDetail? {
    profile.flatMap {
      AdjustmentDetail.build(
        exerciseID: exerciseID, profile: $0, sessions: sessions, decisions: decisions)
    }
  }

  var body: some View {
    if let detail, let profile {
      let measurement = InsightsV3.measurement(
        exerciseID: exerciseID, since: detail.date, sessions: sessions)
      ScrollView {
        VStack(spacing: 0) {
          FieldSection(bottom: 24) {
            detailField(detail, profile: profile, measurement: measurement)
          }
          VStack(spacing: 0) {
            whySection(detail, profile: profile)
            whatHappenedSection(detail, profile: profile, measurement: measurement)
          }
          .background(Theme.page)
        }
        .padding(.bottom, 30)
      }
      .progressFieldPage(detail.exercise.localizedName)
      .accessibilityIdentifier("adjustments.detail")
    } else {
      ContentUnavailableView {
        Text(String(localized: "This change is no longer in the current block.", bundle: L10n.bundle))
      }
    }
  }

  // MARK: Field

  /// The detail field: who changed the load, the new numbers, the before/after sets.
  private func detailField(
    _ d: AdjustmentDetail, profile: UserProfile, measurement: InsightsV3.Measurement?
  ) -> some View {
    let isLb = profile.usesLb
    let from = Fmt.num(isLb ? Plates.kgToLb(d.fromKg) : d.fromKg)
    let to = Fmt.num(isLb ? Plates.kgToLb(d.toKg) : d.toKg)
    let unit = isLb ? "lb" : "kg"
    let dateText = d.date.formatted(
      .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
    return VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        LiftToken(exercise: d.exercise, size: 52)
        VStack(alignment: .leading, spacing: 2) {
          Text(
            d.dayName.map {
              String(localized: "Planned load, \(localizedDayName($0))", bundle: L10n.bundle)
            } ?? String(localized: "Planned load", bundle: L10n.bundle))
            .forge(20, .bold)
            .foregroundStyle(Theme.text)
            .fixedSize(horizontal: false, vertical: true)
          Text(
            d.byLifter
              ? String(localized: "You changed it \(dateText)", bundle: L10n.bundle)
              : String(
                localized: "\(Coach.from(coachID).name) changed it \(dateText)",
                bundle: L10n.bundle))
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
        }
      }
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(verbatim: from)
          .forge(28, .semibold)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
        Image(systemName: "arrow.forward")
          .scaledSystemFont(20, weight: .bold)
          .foregroundStyle(Theme.textSecondary)
        HStack(alignment: .firstTextBaseline, spacing: 4) {
          Text(verbatim: to)
            .forge(44, .bold)
            .foregroundStyle(Theme.text)
            .monospacedDigit()
          Text(verbatim: unit)
            .forge(17, .medium)
            .foregroundStyle(Theme.textSecondary)
        }
      }
      .padding(.top, 16)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        Text(String(localized: "\(from) to \(to) \(unit)", bundle: L10n.bundle)))
      Text(String(localized: "Before and after", bundle: L10n.bundle))
        .forge(13, .semibold)
        .foregroundStyle(Theme.textSecondary)
        .padding(.top, 22)
      // Two rows: the labels top-aligned, the bars bottom-aligned, the arrow centred between them.
      Grid(alignment: .top, horizontalSpacing: 8, verticalSpacing: 10) {
        GridRow {
          sideHeading(d.before, current: false)
          Color.clear.frame(width: 20, height: 1)
          sideHeading(d.after, current: true)
        }
        GridRow {
          sideBars(
            d.before, current: false, better: measurement?.outcome == .better,
            repTop: d.repTop, isLb: isLb)
            .gridCellAnchor(.bottom)
          Image(systemName: "arrow.forward")
            .scaledSystemFont(20, weight: .semibold)
            .foregroundStyle(Theme.textSecondary)
            .gridCellAnchor(.center)
            .accessibilityHidden(true)
          sideBars(
            d.after, current: true, better: measurement?.outcome == .better,
            repTop: d.repTop, isLb: isLb)
            .gridCellAnchor(.bottom)
        }
      }
      .padding(.top, 12)
      Text(String(localized: "Reps in each working set.", bundle: L10n.bundle))
        .forge(13)
        .foregroundStyle(Theme.textSecondary)
        .padding(.top, 12)
    }
  }

  /// The "Before ·" / "After ·" label that caps one side of the bars.
  @ViewBuilder
  private func sideHeading(_ s: AdjustmentDetail.Side?, current: Bool) -> some View {
    if let s {
      Text(
        current
          ? String(
            localized: "After · \(s.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale)))",
            bundle: L10n.bundle)
          : String(
            localized: "Before · \(s.date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale)))",
            bundle: L10n.bundle))
        .forge(13, current ? .semibold : .medium)
        .foregroundStyle(current ? Theme.text : Theme.textSecondary)
        .monospacedDigit()
    } else {
      Color.clear.frame(height: 1)
    }
  }

  /// One side's rep bars over its weight.
  @ViewBuilder
  private func sideBars(
    _ s: AdjustmentDetail.Side?, current: Bool, better: Bool, repTop: Int, isLb: Bool
  ) -> some View {
    if let s {
      VStack(spacing: 0) {
        HStack(alignment: .bottom, spacing: 8) {
          ForEach(Array(s.reps.enumerated()), id: \.offset) { _, rep in
            VStack(spacing: 3) {
              Text("\(rep)")
                .forge(13, .bold)
                .foregroundStyle(Theme.text)
                .monospacedDigit()
              Capsule()
                .fill(current ? (better ? Theme.recordRing : Theme.accent) : Theme.track)
                .frame(
                  width: 24,
                  height: max(12, 64 * CGFloat(rep) / CGFloat(max(1, repTop))))
            }
          }
        }
        Text(verbatim: "\(Fmt.num(isLb ? Plates.kgToLb(s.weightKg) : s.weightKg)) \(isLb ? "lb" : "kg")")
          .forge(15, .semibold)
          .foregroundStyle(current ? Theme.text : Theme.textSecondary)
          .monospacedDigit()
          .padding(.top, 8)
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(sideLabel(s)))
    } else {
      VStack(spacing: 0) {
        Spacer(minLength: 0)
          .frame(height: 90)
        Text(String(localized: "Not lifted yet", bundle: L10n.bundle))
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private func sideLabel(_ s: AdjustmentDetail.Side) -> String {
    let dateText = s.date.formatted(
      .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
    let reps = s.reps.map(String.init).joined(separator: ", ")
    return String(
      localized: "\(dateText): \(reps)", bundle: L10n.bundle)
  }

  // MARK: Why

  /// The change's own record: who made it, in their words, with their evidence.
  /// Without an evidence line the row would only restate the hero's from → to numbers.
  @ViewBuilder
  private func whySection(_ d: AdjustmentDetail, profile: UserProfile) -> some View {
    if d.evidenceLine != nil {
      let isLb = profile.usesLb
      let unit = isLb ? "lb" : "kg"
      let from = Fmt.num(isLb ? Plates.kgToLb(d.fromKg) : d.fromKg)
      let to = Fmt.num(isLb ? Plates.kgToLb(d.toKg) : d.toKg)
      section(
        d.byLifter
          ? String(localized: "You changed it", bundle: L10n.bundle)
          : String(localized: "Why \(Coach.from(coachID).name) changed it", bundle: L10n.bundle)
      ) {
        HStack(alignment: .top, spacing: 12) {
          if d.byLifter {
            Image(systemName: "chart.line.uptrend.xyaxis")
              .scaledSystemFont(17, weight: .semibold)
              .foregroundStyle(Theme.positive)
              .frame(width: 32)
          } else {
            CoachAvatar(size: 32)
          }
          VStack(alignment: .leading, spacing: 2) {
            Text(verbatim: "\(from) \(unit) → \(to) \(unit)")
              .forge(15, .semibold)
              .foregroundStyle(Theme.text)
              .monospacedDigit()
              .fixedSize(horizontal: false, vertical: true)
            if let evidence = d.evidenceLine {
              Text(verbatim: evidence)
                .forge(13)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            }
          }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 4)
      }
    }
  }

  // MARK: What happened

  /// The measured aftermath: estimated max, the best after-set, the next check.
  private func whatHappenedSection(
    _ d: AdjustmentDetail, profile: UserProfile, measurement: InsightsV3.Measurement?
  ) -> some View {
    let isLb = profile.usesLb
    let cal = Calendar.current
    let trend = ProgressData(sessions: sessions, profile: profile).liftTrends.first {
      $0.exercise.id == exerciseID
    }
    let bestWorkout: LiftWorkout?
    if let date = measurement?.bestAfterDate {
      bestWorkout = trend?.workouts.first { cal.isDate($0.date, inSameDayAs: date) }
    } else if let after = d.after {
      bestWorkout = trend?.workouts.first { cal.isDate($0.date, inSameDayAs: after.date) }
    } else {
      bestWorkout = nil
    }
    var rows: [AnyView] = []
    if let m = measurement {
      rows.append(
        AnyView(
          estimatedMaxRow(m, isLb: isLb)
        ))
    }
    if let workout = bestWorkout {
      rows.append(AnyView(bestSetRow(workout, d: d, isLb: isLb)))
    }
    return section(
      String(localized: "What happened", bundle: L10n.bundle),
      trailing: measuredWord(measurement)
    ) {
      VStack(spacing: 0) {
        ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
          row
          if index < rows.count - 1 { rowDivider }
        }
      }
      if let dayName = d.dayName {
        Text(
          String(
            localized: "\(Coach.from(coachID).name) checks this again after your next \(localizedDayName(dayName)).",
            bundle: L10n.bundle)
        )
        .forge(13)
        .foregroundStyle(Theme.textSecondary)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Theme.margin)
        .padding(.top, 12)
      }
    }
  }

  private var rowDivider: some View {
    Divider().padding(.leading, Theme.margin)
  }

  /// "Measured better" in the gain color, everything else in secondary.
  private func measuredWord(_ measurement: InsightsV3.Measurement?) -> (text: String, positive: Bool) {
    switch measurement?.outcome {
    case .better: return (String(localized: "Measured better", bundle: L10n.bundle), true)
    case .noChange: return (String(localized: "No change", bundle: L10n.bundle), false)
    case .measuring, nil: return (String(localized: "Measuring", bundle: L10n.bundle), false)
    }
  }

  private func estimatedMaxRow(_ m: InsightsV3.Measurement, isLb: Bool) -> some View {
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: "chart.bar.fill")
        .scaledSystemFont(17, weight: .semibold)
        .foregroundStyle(Theme.metricLoad)
        .frame(width: 32)
      VStack(alignment: .leading, spacing: 2) {
        Text(String(localized: "Estimated max", bundle: L10n.bundle))
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
        if let before = m.bestBefore {
          Text(
            String(
              localized: "\(Fmt.num(isLb ? Plates.kgToLb(before) : before)) \(isLb ? "lb" : "kg") before the change",
              bundle: L10n.bundle)
          )
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
        }
      }
      Spacer(minLength: 8)
      if let after = m.bestAfter {
        VStack(alignment: .trailing, spacing: 0) {
          Text(verbatim: "\(Fmt.num(isLb ? Plates.kgToLb(after) : after)) \(isLb ? "lb" : "kg")")
            .forge(17, .semibold)
            .foregroundStyle(Theme.text)
            .monospacedDigit()
          if let before = m.bestBefore, after - before > 0.05 {
            Text(
              verbatim: "+\(Fmt.num(isLb ? Plates.kgToLb(after - before) : after - before)) \(isLb ? "lb" : "kg")"
            )
            .forge(13, .semibold)
            .foregroundStyle(Theme.positiveText)
            .monospacedDigit()
          }
        }
      }
    }
    .padding(.horizontal, Theme.margin)
    .padding(.vertical, 10)
    .frame(minHeight: 50)
  }

  /// The best set after the change: "Record on …" when it was a record, else "Best on …".
  private func bestSetRow(_ workout: LiftWorkout, d: AdjustmentDetail, isLb: Bool) -> some View {
    let dateText = workout.date.formatted(
      .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
    let weight = Fmt.num(isLb ? Plates.kgToLb(workout.weightKg) : workout.weightKg)
    var line = "\(weight) \(isLb ? "lb" : "kg") × \(workout.reps)"
    if let after = d.after, Calendar.current.isDate(workout.date, inSameDayAs: after.date) {
      line += ", \(after.reps.count) \(String(localized: "sets", bundle: L10n.bundle))"
    }
    return HStack(alignment: .top, spacing: 12) {
      Image(systemName: workout.isRecord ? "trophy.fill" : "calendar")
        .scaledSystemFont(17, weight: .semibold)
        .foregroundStyle(workout.isRecord ? Theme.recordRing : Theme.metricTime)
        .frame(width: 32)
      VStack(alignment: .leading, spacing: 2) {
        Text(
          workout.isRecord
            ? String(localized: "Record on \(dateText)", bundle: L10n.bundle)
            : String(localized: "Best on \(dateText)", bundle: L10n.bundle))
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
        Text(verbatim: line)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
      Spacer(minLength: 8)
    }
    .padding(.horizontal, Theme.margin)
    .padding(.vertical, 10)
    .frame(minHeight: 50)
  }

  /// A white section: bold header, quiet trailing word, body rows.
  private func section<Content: View>(
    _ title: String, trailing: (text: String, positive: Bool)? = nil,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline) {
        Text(title)
          .forge(20, .bold)
          .foregroundStyle(Theme.text)
          .accessibilityAddTraits(.isHeader)
        Spacer(minLength: 12)
        if let trailing {
          Text(trailing.text)
            .forge(15, trailing.positive ? .semibold : .medium)
            .foregroundStyle(trailing.positive ? Theme.positiveText : Theme.textSecondary)
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.top, 24)
      .padding(.bottom, 8)
      content()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

// MARK: - How sheet

struct AdjustmentsHowSheet: View {
  @Environment(\.dismiss) private var dismiss
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue

  private struct Step: Identifiable {
    let title: String
    let body: String
    var id: String { title }
  }

  private var steps: [Step] {
    [
      Step(
        title: String(localized: "You log a session", bundle: L10n.bundle),
        body: String(localized: "Weight, reps and effort.", bundle: L10n.bundle)),
      Step(
        title: String(
          localized: "\(Coach.from(coachID).name) checks each lift", bundle: L10n.bundle),
        body: String(
          localized: "Top of the range with effort to spare: more weight. Stuck for 3 sessions: a new variant. Short sleep: a lighter day.",
          bundle: L10n.bundle)),
      Step(
        title: String(localized: "Your next session changes", bundle: L10n.bundle),
        body: String(
          localized: "More weekly sets wait for your OK. Ask \(Coach.from(coachID).name) in Coach to undo a change.",
          bundle: L10n.bundle)),
    ]
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          ForEach(Array(steps.enumerated()), id: \.element.id) { index, step in
            HStack(alignment: .top, spacing: 14) {
              Circle()
                .fill(Theme.innerSurface)
                .frame(width: 32, height: 32)
                .overlay(
                  Text(verbatim: "\(index + 1)")
                    .forge(15, .bold)
                    .foregroundStyle(Theme.text))
              VStack(alignment: .leading, spacing: 3) {
                Text(step.title)
                  .forge(17, .semibold)
                  .foregroundStyle(Theme.text)
                Text(step.body)
                  .forge(15)
                  .foregroundStyle(Theme.textSecondary)
              }
            }
            .padding(.vertical, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
              Text("\(index + 1). \(step.title). \(step.body)", bundle: L10n.bundle))
          }
          VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "What this screen never claims", bundle: L10n.bundle))
              .forge(15, .semibold)
              .foregroundStyle(Theme.text)
            Text(
              String(
                localized: "A change is not a result. \(Coach.from(coachID).name) shows what you lifted after it, never a success score.",
                bundle: L10n.bundle)
            )
            .forge(15)
            .foregroundStyle(Theme.textSecondary)
            .padding(.top, 6)
          }
          .padding(16)
          .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.innerSurface))
          .padding(.top, 14)
        }
        .padding(.horizontal, 22)
        .padding(.top, 18)
        .padding(.bottom, 30)
      }
      .navigationTitle(Text(String(localized: "How adjustments work", bundle: L10n.bundle)))
      .toolbar {
        ToolbarItem(placement: .confirmationAction) {
          Button(String(localized: "Done", bundle: L10n.bundle)) { dismiss() }
        }
      }
      .accessibilityIdentifier("adjustments.how")
    }
    .presentationDetents([.large])
  }
}
