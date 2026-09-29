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
  @Environment(\.colorScheme) private var colorScheme
  @State private var approving: VolumeIncrease?
  @State private var showHow = false
  @Namespace private var zoom

  private var profile: UserProfile? { profiles.first }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 0) {
        if let profile {
          let model = AdjustmentsModel.build(
            profile: profile, sessions: sessions, decisions: decisions)
          let pending = VolumeApprovals.increases(
            profile: profile, sessions: sessions, checkIns: checkIns
          ).filter { $0.answer == nil }
          if let firstPending = pending.first {
            pendingCard(firstPending, pendingCount: pending.count)
              .padding(.top, 16)
          }
          if !model.lanes.isEmpty || !pending.isEmpty {
            canvasCard(model, pending: pending, profile: profile)
              .padding(.top, 16)
          }
          if !model.others.isEmpty {
            Text(String(localized: "Other changes", bundle: L10n.bundle))
              .forge(15, .semibold)
              .foregroundStyle(Theme.textSecondary)
              .padding(.top, 22)
              .padding(.bottom, 8)
            othersCard(model)
          }
          if model.isEmpty && pending.isEmpty {
            emptyCard
              .padding(.top, 16)
          }
        }
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 30)
    }
    .background(Theme.pageGrey)
    .navigationTitle("Adjustments")
    .navigationBarTitleDisplayMode(.large)
    .accessibilityIdentifier("adjustments.list")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showHow = true
        } label: {
          Image(systemName: "info.circle")
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

  // MARK: Needs your OK

  private func pendingCard(_ increase: VolumeIncrease, pendingCount: Int) -> some View {
    Button {
      approving = increase
    } label: {
      HStack(spacing: 14) {
        LiftToken(exercise: increase.exercise, size: 48)
        VStack(alignment: .leading, spacing: 1) {
          Text(
            pendingCount > 1
              ? String(
                localized: "Needs your OK · \(1) of \(pendingCount)", bundle: L10n.bundle)
              : String(localized: "Needs your OK", bundle: L10n.bundle))
            .forge(13, .semibold)
            .foregroundStyle(Theme.accentText)
          Text(increase.exercise.localizedName)
            .forge(17, .semibold)
            .foregroundStyle(Theme.text)
        }
        Spacer(minLength: 8)
        VStack(alignment: .trailing, spacing: 0) {
          HStack(spacing: 4) {
            Text("\(increase.fromSets)")
              .forge(26, .bold)
              .foregroundStyle(Theme.text)
              .monospacedDigit()
            Image(systemName: "arrow.right")
              .font(.system(size: 17, weight: .bold))
              .foregroundStyle(Theme.textSecondary)
            Text("\(increase.toSets)")
              .forge(26, .bold)
              .foregroundStyle(Theme.text)
              .monospacedDigit()
          }
          Text(
            increase.toSets == 1
              ? String(localized: "set", bundle: L10n.bundle)
              : String(localized: "sets", bundle: L10n.bundle)
          )
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
        }
        Image(systemName: "chevron.right")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(Theme.textSecondary)
      }
      .padding(.vertical, 14)
      .padding(.horizontal, 16)
      .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Theme.accentTint))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        Text(
          pendingCount > 1
            ? String(
              localized:
                "Needs your OK, \(increase.exercise.localizedName), \(increase.fromSets) to \(increase.toSets) sets, 1 of \(pendingCount)",
              bundle: L10n.bundle)
            : String(
              localized:
                "Needs your OK, \(increase.exercise.localizedName), \(increase.fromSets) to \(increase.toSets) sets",
              bundle: L10n.bundle)))
      .accessibilityHint(Text(String(localized: "Review", bundle: L10n.bundle)))
    }
    .buttonStyle(RowPressStyle())
    .accessibilityIdentifier("adjustments.pending")
  }

  // MARK: Block canvas

  private func canvasCard(_ model: AdjustmentsModel, pending: [VolumeIncrease], profile: UserProfile)
    -> some View
  {
    VStack(alignment: .leading, spacing: 0) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(String(localized: "Block \(model.blockNumber)", bundle: L10n.bundle))
          .forge(17, .semibold)
          .foregroundStyle(Theme.text)
        Text(
          String(
            localized: "week \(model.currentWeek) of \(Mesocycle.weeks)", bundle: L10n.bundle)
        )
        .forge(15)
        .foregroundStyle(Theme.textSecondary)
      }
      canvasGrid(model, pending: pending, profile: profile)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .todayCard(padding: 16)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("adjustments.canvas")
  }

  private func canvasGrid(_ model: AdjustmentsModel, pending: [VolumeIncrease], profile: UserProfile)
    -> some View
  {
    let visiblePending = pending.prefix(max(0, 6 - model.lanes.count))
    return VStack(spacing: 0) {
      columnHeader(model)
      ForEach(model.lanes) { lane in
        NavigationLink {
          AdjustmentDetailView(exerciseID: lane.exercise.id)
            .modifier(AdjustmentZoomDestination(id: lane.exercise.id, namespace: zoom))
        } label: {
          laneRow(lane, model: model, profile: profile)
            .modifier(AdjustmentZoomSource(id: lane.exercise.id, namespace: zoom))
        }
        .buttonStyle(RowPressStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
          Text(
            String(
              localized: "\(lane.exercise.localizedName), \(laneChange(lane.totalKg, profile: profile)) this block",
              bundle: L10n.bundle)))
        .accessibilityIdentifier("adjustments.lane.\(lane.exercise.id)")
      }
      ForEach(visiblePending) { increase in
        Button {
          approving = increase
        } label: {
          pendingLaneRow(increase, model: model)
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("adjustments.lane.pending.\(increase.exercise.id)")
      }
    }
    .background(
      currentWeekBand(lanes: model.lanes.count + visiblePending.count, columns: model.weeks.count)
    )
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
              Text(start.formatted(.dateTime.month(.abbreviated).day()))
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
      Color.clear.frame(width: 62)
    }
    .frame(height: 22)
    .padding(.top, 12)
  }

  /// Tinted band behind the current week's column, header labels included.
  private func currentWeekBand(lanes: Int, columns: Int) -> some View {
    GeometryReader { geo in
      let stripX: CGFloat = 46
      let stripW = geo.size.width - stripX - 72
      let colW = stripW / CGFloat(max(1, columns))
      let height: CGFloat = 30 + 52 * CGFloat(lanes)
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(Theme.accent.opacity(colorScheme == .dark ? 0.10 : 0.08))
        .frame(width: max(0, colW - 6), height: height)
        .position(x: stripX + colW * (CGFloat(columns) - 0.5), y: 8 + height / 2)
    }
  }

  private func laneRow(
    _ lane: AdjustmentsModel.Lane, model: AdjustmentsModel, profile: UserProfile
  ) -> some View {
    HStack(spacing: 10) {
      LiftToken(exercise: lane.exercise, size: 36)
      LoadLaneChart(
        lane: lane, weeks: model.weeks, currentWeek: model.currentWeek,
        rise: risePerKg(model))
      laneValue(lane.totalKg, profile: profile)
    }
    .frame(height: 52)
  }

  private func pendingLaneRow(_ increase: VolumeIncrease, model: AdjustmentsModel) -> some View {
    let n = increase.toSets - increase.fromSets
    return HStack(spacing: 10) {
      LiftToken(exercise: increase.exercise, size: 36)
      PendingLaneChart(exercise: increase.exercise, columns: model.weeks.count)
      Text(String(localized: "+\(n) set\(L10n.pluralSuffix(n))", bundle: L10n.bundle))
        .forge(15, .medium)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
        .padding(.top, 1)
        .frame(width: 62, alignment: .trailing)
        .frame(maxHeight: .infinity, alignment: .top)
    }
    .frame(height: 52)
  }

  /// Pt of rise per kg, so the widest lane swing (peak minus trough) stays inside
  /// the 36 pt above its base line.
  private func risePerKg(_ model: AdjustmentsModel) -> CGFloat {
    let maxSpan = model.lanes.map { laneSpan($0) }.max() ?? 0
    guard maxSpan > 0 else { return 5 }
    return CGFloat(min(5, 36 / maxSpan))
  }

  /// Difference between the highest and lowest cumulative level of a lane,
  /// counting the starting level of 0.
  private func laneSpan(_ lane: AdjustmentsModel.Lane) -> Double {
    var minLevel = 0.0
    var maxLevel = 0.0
    var level = 0.0
    for step in lane.steps {
      level += step.kg
      minLevel = min(minLevel, level)
      maxLevel = max(maxLevel, level)
    }
    return maxLevel - minLevel
  }

  private func laneValue(_ totalKg: Double, profile: UserProfile) -> some View {
    Text(verbatim: laneChange(totalKg, profile: profile))
      .forge(15, .medium)
      .foregroundStyle(totalKg > 0 ? Theme.positiveText : Theme.text)
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.7)
      .padding(.top, 1)
      .frame(width: 62, alignment: .trailing)
      .frame(maxHeight: .infinity, alignment: .top)
  }

  private func laneChange(_ totalKg: Double, profile: UserProfile) -> String {
    let isLb = profile.usesLb
    let display = isLb ? Plates.kgToLb(totalKg) : totalKg
    let sign = totalKg > 0 ? "+" : (totalKg < 0 ? "\u{2212}" : "")
    return "\(sign)\(Fmt.num(abs(display))) \(isLb ? "lb" : "kg")"
  }

  // MARK: Other changes

  private func othersCard(_ model: AdjustmentsModel) -> some View {
    VStack(spacing: 0) {
      ForEach(Array(model.others.enumerated()), id: \.element.id) { index, other in
        otherRow(other)
        if index < model.others.count - 1 {
          Divider().padding(.leading, 16)
        }
      }
    }
    .todayCard(padding: 0)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("adjustments.others")
  }

  private func otherRow(_ other: AdjustmentsModel.Other) -> some View {
    HStack {
      Text(other.title)
        .forge(16, .medium)
        .foregroundStyle(Theme.text)
        .lineLimit(2)
      Spacer(minLength: 8)
      otherTrailing(other)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 10)
    .frame(minHeight: 50)
    .accessibilityIdentifier("adjustments.other.\(other.id)")
  }

  @ViewBuilder
  private func otherTrailing(_ other: AdjustmentsModel.Other) -> some View {
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
        Text(other.date.formatted(.dateTime.month(.abbreviated).day()))
          .forge(15, .medium)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
    }
  }

  // MARK: Empty

  private var emptyCard: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(String(localized: "No changes yet", bundle: L10n.bundle))
        .forge(17, .semibold)
        .foregroundStyle(Theme.text)
      Text(
        String(
          localized: "Kai checks every lift after each session. Weight goes up when all sets hit the top of the range.",
          bundle: L10n.bundle)
      )
      .forge(15)
      .foregroundStyle(Theme.textSecondary)
      .padding(.top, 4)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .todayCard(padding: 16)
    .accessibilityIdentifier("adjustments.empty")
  }
}

// MARK: - Lane charts

private struct LoadLaneChart: View {
  let lane: AdjustmentsModel.Lane
  let weeks: [Int]
  let currentWeek: Int
  let rise: CGFloat

  var body: some View {
    GeometryReader { geo in
      Canvas { context, _ in
        let colW = geo.size.width / CGFloat(max(1, weeks.count))
        let end = colW * (CGFloat(weeks.count) - 0.5)
        let base: CGFloat = 46
        var minLevel = 0.0
        var level0 = 0.0
        for step in lane.steps {
          level0 += step.kg
          minLevel = min(minLevel, level0)
        }
        // minLevel ≤ 0, so a lane that drops starts higher and its lowest point sits at 46.
        let start = base + CGFloat(minLevel) * rise
        func cx(_ column: Int) -> CGFloat { colW * (CGFloat(column) + 0.5) }

        var path = Path()
        path.move(to: CGPoint(x: 0, y: start))
        var y = start
        for step in lane.steps {
          guard let column = weeks.firstIndex(of: step.week) else { continue }
          let x = cx(column)
          path.addLine(to: CGPoint(x: x, y: y))
          y -= CGFloat(step.kg) * rise
          path.addLine(to: CGPoint(x: x, y: y))
        }
        path.addLine(to: CGPoint(x: end, y: y))
        context.stroke(
          path,
          with: .color(Theme.accent),
          style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        var level = start
        for step in lane.steps {
          guard let column = weeks.firstIndex(of: step.week) else { continue }
          level -= CGFloat(step.kg) * rise
          let center = CGPoint(x: cx(column), y: level)
          let ring = Path(
            ellipseIn: CGRect(x: center.x - 5.5, y: center.y - 5.5, width: 11, height: 11))
          if step.week == currentWeek {
            context.fill(ring, with: .color(Theme.card))
            context.stroke(ring, with: .color(Theme.accent), lineWidth: 2.5)
          } else {
            context.fill(ring, with: .color(Theme.accent))
            context.stroke(ring, with: .color(Theme.card), lineWidth: 2.5)
          }
        }
      }
    }
    .overlay(alignment: .topLeading) {
      Text(lane.exercise.localizedName)
        .forge(12, .medium)
        .foregroundStyle(Theme.textSecondary)
        .padding(.top, 2)
    }
  }
}

private struct PendingLaneChart: View {
  let exercise: Exercise
  let columns: Int

  var body: some View {
    GeometryReader { geo in
      Canvas { context, _ in
        let colW = geo.size.width / CGFloat(max(1, columns))
        let end = colW * (CGFloat(columns) - 0.5)
        let base: CGFloat = 46
        var line = Path()
        line.move(to: CGPoint(x: 0, y: base))
        line.addLine(to: CGPoint(x: end, y: base))
        context.stroke(
          line, with: .color(Theme.track), style: StrokeStyle(lineWidth: 3, lineCap: .round))
        let ring = Path(
          ellipseIn: CGRect(x: end - 6, y: base - 6, width: 12, height: 12))
        context.fill(ring, with: .color(Theme.card))
        context.stroke(ring, with: .color(Theme.accent), lineWidth: 2.5)
      }
    }
    .overlay(alignment: .topLeading) {
      Text(exercise.localizedName)
        .forge(12, .medium)
        .foregroundStyle(Theme.textSecondary)
        .padding(.top, 2)
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
  @Query(sort: \CheckIn.date) private var checkIns: [CheckIn]
  @Query(sort: \DecisionLogEntry.date, order: .reverse) private var decisions: [DecisionLogEntry]

  private var profile: UserProfile? { profiles.first }
  private var detail: AdjustmentDetail? {
    profile.flatMap {
      AdjustmentDetail.build(
        exerciseID: exerciseID, profile: $0, sessions: sessions, decisions: decisions)
    }
  }

  var body: some View {
    if let detail {
      ScrollView {
        VStack(spacing: 0) {
          hero(detail)
          beforeAfterCard(detail)
            .padding(.horizontal, 16)
            .padding(.top, 16)
        }
        .padding(.bottom, 30)
      }
      .background(Theme.pageGrey)
      .navigationTitle("")
      .navigationBarTitleDisplayMode(.inline)
      .accessibilityIdentifier("adjustments.detail")
    } else {
      ContentUnavailableView {
        Text(String(localized: "This change is no longer in the current block.", bundle: L10n.bundle))
      }
    }
  }

  // MARK: Hero

  private func hero(_ d: AdjustmentDetail) -> some View {
    let isLb = profile?.usesLb ?? false
    let from = Fmt.num(isLb ? Plates.kgToLb(d.fromKg) : d.fromKg)
    let to = Fmt.num(isLb ? Plates.kgToLb(d.toKg) : d.toKg)
    let unit = isLb ? "lb" : "kg"
    return VStack(spacing: 0) {
      LiftToken(exercise: d.exercise, size: 96)
      Text(d.exercise.localizedName)
        .forge(22, .semibold)
        .foregroundStyle(Theme.text)
        .padding(.top, 12)
      Text(verbatim: heroMeta(d))
        .forge(15)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
        .padding(.top, 2)
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(verbatim: from)
          .forge(34, .semibold)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
        Image(systemName: "arrow.right")
          .font(.system(size: 24, weight: .bold))
          .foregroundStyle(Theme.textSecondary)
        Text(verbatim: to)
          .forge(48, .bold)
          .foregroundStyle(Theme.text)
          .monospacedDigit()
        Text(verbatim: unit)
          .forge(22, .medium)
          .foregroundStyle(Theme.textSecondary)
      }
      .padding(.top, 10)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        Text(String(localized: "\(from) to \(to) \(unit)", bundle: L10n.bundle)))
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 8)
    .padding(.bottom, 22)
    .background(Theme.accentTint.ignoresSafeArea(edges: .top))
  }

  private func heroMeta(_ d: AdjustmentDetail) -> String {
    let dateText = d.date.formatted(.dateTime.month(.abbreviated).day())
    guard let dayName = d.dayName else { return dateText }
    return "\(localizedDayName(dayName)) · \(dateText)"
  }

  // MARK: Before and after

  private func beforeAfterCard(_ d: AdjustmentDetail) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(String(localized: "Before and after", bundle: L10n.bundle))
        .forge(17, .semibold)
        .foregroundStyle(Theme.text)
      HStack(alignment: .bottom) {
        side(d.before, current: false, repTop: d.repTop)
        Image(systemName: "arrow.right")
          .font(.system(size: 22, weight: .semibold))
          .foregroundStyle(Theme.textSecondary)
        side(d.after, current: true, repTop: d.repTop)
      }
      .padding(.top, 18)
      Divider()
        .padding(.top, 20)
      Text(String(localized: "Next step", bundle: L10n.bundle))
        .forge(17, .semibold)
        .foregroundStyle(Theme.text)
        .padding(.top, 12)
      Text(
        String(
          localized: "Hit \(repsList(d)) at \(toWeightText(d)) to go up", bundle: L10n.bundle)
      )
      .forge(15)
      .foregroundStyle(Theme.textSecondary)
      .monospacedDigit()
      .padding(.top, 2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .todayCard(padding: 18)
  }

  @ViewBuilder
  private func side(_ s: AdjustmentDetail.Side?, current: Bool, repTop: Int) -> some View {
    if let s {
      VStack(spacing: 0) {
        Text(s.date.formatted(.dateTime.month(.abbreviated).day()))
          .forge(13, current ? .semibold : .medium)
          .foregroundStyle(current ? Theme.text : Theme.textSecondary)
          .monospacedDigit()
        HStack(alignment: .bottom, spacing: 8) {
          ForEach(Array(s.reps.enumerated()), id: \.offset) { _, rep in
            VStack(spacing: 3) {
              Text("\(rep)")
                .forge(13, .bold)
                .foregroundStyle(Theme.text)
                .monospacedDigit()
              Capsule()
                .fill(current ? Theme.gradExercise[0] : Theme.track)
                .frame(
                  width: 24,
                  height: max(12, 64 * CGFloat(rep) / CGFloat(max(1, repTop))))
            }
          }
        }
        .padding(.top, 10)
        if let effort = s.effort {
          HStack(spacing: 6) {
            Circle()
              .fill(Theme.zone(rpe: effort)[0])
              .frame(width: 9, height: 9)
            Text(String(localized: "effort \(Fmt.num(effort))", bundle: L10n.bundle))
              .forge(14, .medium)
              .foregroundStyle(Theme.textSecondary)
              .monospacedDigit()
          }
          .padding(.top, 12)
        }
      }
      .frame(maxWidth: .infinity)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(sideLabel(s, effort: s.effort)))
    } else {
      VStack(spacing: 0) {
        Spacer(minLength: 0)
          .frame(height: 83)
        Text(String(localized: "Not lifted yet", bundle: L10n.bundle))
          .forge(15)
          .foregroundStyle(Theme.textSecondary)
      }
      .frame(maxWidth: .infinity)
    }
  }

  private func sideLabel(_ s: AdjustmentDetail.Side, effort: Double?) -> String {
    let dateText = s.date.formatted(.dateTime.month(.abbreviated).day())
    let reps = s.reps.map(String.init).joined(separator: ", ")
    guard let effort else { return "\(dateText): \(reps)" }
    return String(
      localized: "\(dateText): \(reps), effort \(Fmt.num(effort))", bundle: L10n.bundle)
  }

  private func repsList(_ d: AdjustmentDetail) -> String {
    Array(repeating: "\(d.repTop)", count: max(1, d.setCount)).joined(separator: ", ")
  }

  private func toWeightText(_ d: AdjustmentDetail) -> String {
    let isLb = profile?.usesLb ?? false
    return Fmt.num(isLb ? Plates.kgToLb(d.toKg) : d.toKg) + " " + (isLb ? "lb" : "kg")
  }
}

// MARK: - How sheet

struct AdjustmentsHowSheet: View {
  @Environment(\.dismiss) private var dismiss

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
        title: String(localized: "Kai checks each lift", bundle: L10n.bundle),
        body: String(
          localized: "Top of the range with effort to spare: more weight. Stuck for 3 sessions: a new variant. Short sleep: a lighter day.",
          bundle: L10n.bundle)),
      Step(
        title: String(localized: "Your next session changes", bundle: L10n.bundle),
        body: String(
          localized: "More weekly sets wait for your OK. Ask Kai in Coach to undo a change.",
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
          }
          VStack(alignment: .leading, spacing: 0) {
            Text(String(localized: "What this screen never claims", bundle: L10n.bundle))
              .forge(15, .semibold)
              .foregroundStyle(Theme.text)
            Text(
              String(
                localized: "A change is not a result. Kai shows what you lifted after it, never a success score.",
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
        ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
      }
      .accessibilityIdentifier("adjustments.how")
    }
    .presentationDetents([.large])
  }
}
