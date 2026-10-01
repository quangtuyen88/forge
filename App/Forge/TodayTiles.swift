import SwiftUI
import ForgeCore

/// Week summary card, Huawei Health home style (spec W2a §2): three concentric rings
/// (sessions / sets / minutes), a three-column stat row with dividers, and the protein pill.
struct WeekRingsCard: View {
  let sessionsDone: Int
  let sessionsTarget: Int
  let setsDone: Int
  let setsTarget: Int
  let minutesDone: Int
  let minutesTarget: Int
  let streakWeeks: Int
  let proteinToday: Double
  var proteinTarget: Int?
  let onLogFood: () -> Void

  private func fraction(_ done: Int, _ target: Int) -> Double {
    guard target > 0 else { return 0 }
    return min(1, max(0, Double(done) / Double(target)))
  }

  /// True when nothing at all is logged this week: the stat columns give way to one line.
  private var nothingLogged: Bool {
    sessionsDone == 0 && setsDone == 0 && minutesDone == 0
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 8) {
        Text(String(localized: "This week", bundle: L10n.bundle))
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
        Spacer(minLength: 8)
        if streakWeeks > 0 { streakBadge }
      }
      .frame(minHeight: 26)
      HStack(alignment: .center, spacing: 14) {
        ArcRings(
          rings: [
            ArcRingSpec(
              id: "sessions", progress: fraction(sessionsDone, sessionsTarget),
              colors: Theme.gradMove),
            ArcRingSpec(
              id: "sets", progress: fraction(setsDone, setsTarget),
              colors: Theme.gradExercise),
            ArcRingSpec(
              id: "time", progress: fraction(minutesDone, minutesTarget),
              colors: Theme.gradStand),
          ],
          size: 84)
          .frame(width: 84)
        if nothingLogged {
          VStack(alignment: .leading, spacing: 3) {
            Text(String(localized: "No sessions this week yet", bundle: L10n.bundle))
              .forge(15, .semibold)
              .foregroundStyle(Theme.text)
            Text(String(localized: "\(setsTarget) sets planned this week", bundle: L10n.bundle))
              .forge(13)
              .foregroundStyle(Theme.textSecondary)
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(ringsAndStatsA11y)
        } else {
          statsRow
        }
      }
      .padding(.top, 12)
      proteinPill
        .padding(.top, 14)
    }
    .padding(16)
    .todayCard(padding: 0)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("today.week")
  }

  private var streakBadge: some View {
    HStack(spacing: 3) {
      Image(systemName: "flame.fill")
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.mark(Theme.gradMove, startPoint: .bottom, endPoint: .top))
      Text(String(localized: "\(streakWeeks) wk", bundle: L10n.bundle))
        .forge(13, .semibold)
        .foregroundStyle(Theme.accentText)
    }
    .padding(.horizontal, 9)
    .frame(height: 26)
    .background(Capsule().fill(Theme.accent.opacity(0.10)))
  }

  private var ringsAndStatsA11y: String {
    String(
      localized:
        "This week: \(sessionsDone) of \(sessionsTarget) sessions, \(setsDone) of \(setsTarget) sets, \(minutesDone) of \(minutesTarget) minutes",
      bundle: L10n.bundle)
  }

  private var statsRow: some View {
    HStack(spacing: 0) {
      stat(colors: Theme.gradMove, label: String(localized: "Sessions", bundle: L10n.bundle),
        value: sessionsDone,
        target: "/\(sessionsTarget)")
        .frame(maxWidth: .infinity)
      statDivider
      stat(colors: Theme.gradExercise, label: String(localized: "Sets", bundle: L10n.bundle),
        value: setsDone,
        target: "/\(setsTarget)")
        .padding(.leading, 10)
        .frame(maxWidth: .infinity)
      statDivider
      stat(colors: Theme.gradStand, label: String(localized: "Duration", bundle: L10n.bundle),
        value: minutesDone,
        target: String(localized: "/\(minutesTarget) min", bundle: L10n.bundle))
        .padding(.leading, 10)
        .frame(maxWidth: .infinity)
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(ringsAndStatsA11y)
  }

  private var statDivider: some View {
    Rectangle()
      .fill(Theme.ring)
      .frame(width: 1)
      .frame(maxHeight: 44)
  }

  private func stat(colors: [Color], label: String, value: Int, target: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack(spacing: 5) {
        GradientDot(colors: colors)
        Text(label)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      HStack(alignment: .firstTextBaseline, spacing: 4) {
        Text(verbatim: "\(value)")
          .forge(24, .semibold)
          .monospacedDigit()
          .foregroundStyle(Theme.text)
        Text(target)
          .forge(12)
          .foregroundStyle(Theme.textSecondary)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
    }
  }

  private var proteinPill: some View {
    Button(action: onLogFood) {
      HStack(spacing: 6) {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(Theme.positive)
          .frame(width: 20, height: 20)
          .overlay(
            Image(systemName: "fork.knife")
              .font(.system(size: 11, weight: .semibold))
              .foregroundStyle(.white))
        if let proteinTarget {
          Text(String(localized: "Protein today", bundle: L10n.bundle))
            .forge(13)
            .foregroundStyle(Theme.textSecondary)
          Spacer(minLength: 0)
          Text(verbatim: Fmt.grouped(proteinToday))
            .forge(16, .bold)
            .monospacedDigit()
            .foregroundStyle(Theme.text)
          Text(String(localized: "/\(proteinTarget) g", bundle: L10n.bundle))
            .forge(13)
            .foregroundStyle(Theme.textSecondary)
        } else {
          Text(String(localized: "Log food", bundle: L10n.bundle))
            .forge(13, .medium)
            .foregroundStyle(Theme.text)
          Spacer(minLength: 0)
        }
        Image(systemName: "chevron.right")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(Theme.textTertiary)
      }
      .padding(.horizontal, 12)
      .frame(height: 34)
      .frame(maxWidth: .infinity)
      .background(Capsule().fill(Theme.innerSurface))
      .contentShape(Capsule())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityIdentifier("today.logFood")
    .accessibilityLabel(
      proteinTarget != nil
        ? String(
          localized: "Protein today: \(Fmt.grouped(proteinToday)) of \(proteinTarget!) grams",
          bundle: L10n.bundle)
        : String(localized: "Log food", bundle: L10n.bundle))
  }
}

/// Ask grid (spec W1-B §6): a 2×2 grid of illustrated questions asked to the coach directly.
struct TodayAskGrid: View {
  struct Item: Identifiable {
    let id: String
    let scene: CoachScene
    let title: String
    let launch: CoachLaunch
  }

  let coachName: String
  let items: [Item]
  let onAsk: (CoachLaunch) -> Void

  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(String(localized: "Ask \(coachName)", bundle: L10n.bundle))
        .forge(20, .semibold, tracking: -0.3)
        .padding(.horizontal, 4)
      LazyVGrid(
        columns: [
          GridItem(.flexible(), spacing: 12),
          GridItem(.flexible(), spacing: 12),
        ],
        spacing: 12
      ) {
        ForEach(items) { item in
          tile(item)
        }
      }
    }
  }

  private func tile(_ item: Item) -> some View {
    Button {
      onAsk(item.launch)
    } label: {
      VStack(spacing: 0) {
        Color.clear
          .frame(height: 118)
          .frame(maxWidth: .infinity)
          .overlay(alignment: .top) {
            Image(Coach.from(coachID).scene(item.scene))
              .resizable()
              .scaledToFill()
          }
          .clipped()
          .background(Theme.innerSurface)
          .allowsHitTesting(false)
        Text(item.title)
          .forge(15, .semibold)
          .multilineTextAlignment(.center)
          .lineLimit(2)
          .minimumScaleFactor(0.9)
          .frame(maxWidth: .infinity, minHeight: 54)
          .padding(.horizontal, 10)
      }
      .contentShape(RoundedRectangle(cornerRadius: Theme.radiusToday, style: .continuous))
    }
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusToday, style: .continuous))
    .todayCard(padding: 0)
    .buttonStyle(ControlPressStyle())
    .accessibilityLabel(item.title)
    .accessibilityIdentifier(item.id)
  }
}

/// The data the coach call tile shows for its featured decision (spec W2a §6a).
struct CoachCallTileData {
  let coachName: String
  /// New load text, e.g. "102.5"; nil when no decision is featured.
  var loadText: String?
  let unit: String
  var exerciseName: String?
  /// Change without sign, e.g. "2.5"; the arrow carries the direction.
  var changeText: String?
  var changeUp: Bool
  /// Previous load text for the "Last" bar; nil hides both bars.
  var previousLoadText: String?
  /// Width of the Last bar relative to the Today bar (0…1).
  var lastFraction: Double = 1
  /// Short reason line shown when there are no bars (fix 1C): the decision's badge or
  /// short value, e.g. "New variant", "+2.5 kg". (a first-time lift no longer uses `reasonLine`).
  var reasonLine: String? = nil
  /// The reason line is a pending volume increase asking for the lifter's OK.
  var asksOK = false
  /// Footer link text: "6 changes", "1 change", "No changes", "First session".
  var changesText: String
}

/// Coach call tile (spec W2a §6a): the featured load decision as a Last/Today comparison.
struct CoachCallTile: View {
  let data: CoachCallTileData
  let onChanges: () -> Void
  let onWhy: () -> Void

  var body: some View {
    VStack(spacing: 0) {
      Button(action: onWhy) {
        VStack(alignment: .leading, spacing: 0) {
          Text(String(localized: "\(data.coachName)'s call", bundle: L10n.bundle))
            .forge(15, .semibold)
            .foregroundStyle(Theme.text)
            .lineLimit(1)
            .padding(.trailing, 38)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .trailing) { CoachAvatar(size: 30) }
          if let loadText = data.loadText {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
              Text(loadText)
                .forge(26, .semibold)
                .monospacedDigit()
                .foregroundStyle(Theme.text)
              Text(data.unit)
                .forge(13)
                .foregroundStyle(Theme.textSecondary)
            }
            .padding(.top, 4)
          }
          subRow
            .padding(.top, 2)
          if data.previousLoadText != nil {
            comparison
              .frame(maxHeight: .infinity)
              .padding(.top, 6)
          } else if let reasonLine = data.reasonLine {
            reasonView(reasonLine)
              .lineLimit(2)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
              .padding(.top, 4)
          }
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
      }
      .buttonStyle(RowPressStyle())
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(bodyA11yLabel)
      footerLink
    }
    .frame(height: 180)
    .todayCard(padding: 0)
  }

  private func reasonView(_ reasonLine: String) -> some View {
    Group {
      if data.asksOK {
        HStack(spacing: 5) {
          Circle().fill(Theme.accent).frame(width: 6, height: 6)
          Text(reasonLine)
        }
        .forge(13, .semibold)
        .foregroundStyle(Theme.accentText)
      } else {
        Text(reasonLine)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
      }
    }
  }

  private var subRow: some View {
    HStack(spacing: 6) {
      if let exerciseName = data.exerciseName {
        Text(exerciseName)
          .forge(13)
          .foregroundStyle(Theme.textSecondary)
          .lineLimit(2)
      }
      if let changeText = data.changeText {
        HStack(spacing: 2) {
          Image(systemName: data.changeUp ? "arrow.up" : "arrow.down")
            .font(.system(size: 9, weight: .bold))
          Text(changeText)
            .forge(12, .semibold)
            .monospacedDigit()
        }
        .foregroundStyle(data.changeUp ? Theme.positiveText : Theme.textSecondary)
        .padding(.horizontal, 6)
        .frame(height: 20)
        .background(Capsule().fill(data.changeUp ? Theme.positiveTint : Color.clear))
      }
    }
  }

  private var comparison: some View {
    VStack(spacing: 7) {
      if let previous = data.previousLoadText, let today = data.loadText {
        row(
          label: String(localized: "Last", bundle: L10n.bundle), value: previous,
          fraction: data.lastFraction, fill: AnyShapeStyle(Theme.track))
        row(
          label: String(localized: "Today", bundle: L10n.bundle), value: today,
          fraction: 1, fill: AnyShapeStyle(.mark(Theme.gradBrand)))
      }
    }
  }

  private func row(label: String, value: String, fraction: Double, fill: AnyShapeStyle) -> some View {
    HStack(spacing: 6) {
      Text(label)
        .forge(12)
        .foregroundStyle(Theme.textSecondary)
        .frame(width: 38, alignment: .leading)
      GeometryReader { geo in
        ZStack(alignment: .leading) {
          if fraction > 0 {
            Capsule().fill(fill)
              .frame(width: max(8, geo.size.width * fraction))
          } else {
            Capsule().strokeBorder(Theme.track, lineWidth: 1.5)
          }
        }
      }
      .frame(height: 8)
      Text(value)
        .forge(12, fraction > 0 ? .semibold : .regular)
        .monospacedDigit()
        .foregroundStyle(fraction > 0 ? Theme.text : Theme.textSecondary)
        .frame(width: 40, alignment: .trailing)
    }
    .accessibilityHidden(true)
  }

  private var footerLink: some View {
    Button(action: onChanges) {
      HStack(spacing: 4) {
        Text(data.changesText)
          .forge(13, .medium)
          .foregroundStyle(Theme.accentText)
        Image(systemName: "chevron.right")
          .font(.system(size: 11, weight: .semibold))
          .foregroundStyle(Theme.accentText)
      }
      .padding(.bottom, 12)
      .frame(minHeight: 44, alignment: .bottom)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, 14)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityLabel(data.changesText)
  }

  private var bodyA11yLabel: String {
    var parts = [String(localized: "\(data.coachName)'s call", bundle: L10n.bundle)]
    if let loadText = data.loadText { parts.append("\(loadText) \(data.unit)") }
    if let exerciseName = data.exerciseName { parts.append(exerciseName) }
    if let changeText = data.changeText {
      parts.append(
        data.changeUp
          ? String(localized: "up \(changeText) \(data.unit)", bundle: L10n.bundle)
          : String(localized: "down \(changeText) \(data.unit)", bundle: L10n.bundle))
    }
    if let reasonLine = data.reasonLine { parts.append(reasonLine) }
    return parts.joined(separator: ", ")
  }
}

/// Chart tile frame (spec W2a §6): title, big value + unit, flexible chart, footnote. 180 pt
/// tall, two per row. A filled SF Symbol in the tile's metric color sits top right, where the
/// coach tile has its avatar; a tile that needs the lifter gets its wash and a clay object
/// cropped into the bottom-right corner (DESIGN.md, tiles).
struct TodayTile<Chart: View>: View {
  let title: String
  let value: String
  var unit: String? = nil
  var valueColor: Color = Theme.text
  var chart: Chart
  /// Footnote as concatenated Text so parts can carry their own color.
  var footnote: Text? = nil
  var symbol: String? = nil
  var symbolColor: Color = Theme.textSecondary
  var fill: Color = Theme.card
  var art: String? = nil
  var a11yLabel: String = ""
  var action: (() -> Void)? = nil

  var body: some View {
    Group {
      if let action {
        Button(action: action) { content }
          .buttonStyle(RowPressStyle())
      } else {
        content
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(a11yLabel.isEmpty ? title : a11yLabel)
  }

  private var content: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title)
        .forge(15, .semibold)
        .foregroundStyle(Theme.text)
        .lineLimit(1)
        .padding(.trailing, symbol == nil ? 0 : 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .trailing) {
          if let symbol {
            Image(systemName: symbol)
              .font(.system(size: 15, weight: .semibold))
              .foregroundStyle(symbolColor)
          }
        }
      HStack(alignment: .firstTextBaseline, spacing: 3) {
        Text(value)
          .forge(26, .semibold)
          .monospacedDigit()
          .foregroundStyle(valueColor)
        if let unit {
          Text(unit)
            .forge(13)
            .foregroundStyle(Theme.textSecondary)
        }
      }
      .padding(.top, 4)
      chart
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.top, 6)
        .accessibilityHidden(true)
      if let footnote {
        footnote
          .forge(12)
          .foregroundStyle(Theme.textSecondary)
          .padding(.top, 2)
          .lineLimit(art == nil ? 1 : 2)
          .padding(.trailing, art == nil ? 0 : 70)  // a long localized link stays clear of the art
      }
    }
    .padding(.horizontal, 14)
    .padding(.top, 14)
    .padding(.bottom, 12)
    .frame(height: 180, alignment: .top)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(alignment: .bottomTrailing) {
      if let art {
        Image(art)
          .resizable()
          .scaledToFit()
          .frame(width: 104, height: 104)
          .offset(x: 12, y: 8)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusToday, style: .continuous))
    .todayCard(padding: 0, fill: fill)
    .overlay {
      if art != nil {
        RoundedRectangle(cornerRadius: Theme.radiusToday, style: .continuous)
          .strokeBorder(symbolColor.opacity(0.18), lineWidth: 1)
      }
    }
    .contentShape(Rectangle())
  }
}

/// e1RM trend line (spec W2a §6b): gradient route stroke, hollow start dot, filled end dot.
/// Y span is floored at max(data range, 10 % of the first value, 4) centered on the data's
/// midpoint so small changes don't zig-zag the whole tile (fix 1B); the plot keeps 4 pt top
/// and 6 pt bottom insets so the dots never touch the footnote.
struct TrendLineChart: View {
  let values: [Double]
  var colors: [Color] = Theme.gradRoute
  var minSpan: Double? = nil

  private static let topInset: CGFloat = 4
  private static let bottomInset: CGFloat = 6

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height - Self.topInset - Self.bottomInset
      if values.count >= 2, let minV = values.min(), let maxV = values.max() {
        let mid = (minV + maxV) / 2
        let span = max(maxV - minV, minSpan ?? max(abs(values[0]) * 0.1, 4))
        let yMin = mid - span / 2
        let yMax = mid + span / 2
        let pts = values.enumerated().map { i, v in
          CGPoint(
            x: w * CGFloat(i) / CGFloat(values.count - 1),
            y: Self.topInset + h - h * CGFloat((v - yMin) / (yMax - yMin)))
        }
        ZStack {
          Path { p in
            p.move(to: pts[0])
            for pt in pts.dropFirst() { p.addLine(to: pt) }
          }
          .stroke(
            .mark(colors),
            style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
          Circle()
            .fill(Theme.card)
            .frame(width: 7, height: 7)
            .overlay(Circle().strokeBorder(colors[0], lineWidth: 2))
            .position(pts[0])
          Circle()
            .fill(colors.last ?? Theme.accent)
            .frame(width: 8, height: 8)
            .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
            .position(pts[pts.count - 1])
        }
      }
    }
  }
}

/// Last 8 nights of sleep as rounded bars (spec W2a §6c) on a 0–9 h scale, taller when a night
/// ran longer: vertical sleep gradient, older nights at 55 % opacity, the latest full. growIn:
/// the bars rise one after another as the chart appears, for the check-in that just filled it.
struct SleepBarChart: View {
  let hours: [Double]
  var growIn = false
  @State private var grown = false

  var body: some View {
    GeometryReader { geo in
      let h = geo.size.height
      let maxV = max(hours.max() ?? 0, 9)
      let n = hours.count
      if n >= 1 {
        let gap = n > 1 ? max(3, (geo.size.width - 10 * CGFloat(n)) / CGFloat(n - 1)) : 0
        HStack(alignment: .bottom, spacing: gap) {
          ForEach(Array(hours.enumerated()), id: \.offset) { i, v in
            let hidden = growIn && !grown
            Capsule()
              .fill(.mark(Theme.gradSleep, startPoint: .top, endPoint: .bottom))
              .frame(width: 10, height: max(6, h * CGFloat(v / maxV)))
              .scaleEffect(x: 1, y: hidden ? 0.08 : 1, anchor: .bottom)
              .opacity(hidden ? 0 : (i == n - 1 ? 1 : 0.55))
              // Starts as the check-in sheet finishes closing.
              .animation(.spring(response: 0.36, dampingFraction: 1).delay(0.3 + Double(i) * 0.028), value: grown)
          }
        }
        .frame(width: geo.size.width, height: geo.size.height, alignment: .bottomLeading)
      }
    }
    .onAppear { if growIn { grown = true } }
  }
}

/// Resting heart rate line with an area fill (spec W2a §6d).
struct HeartLineChart: View {
  let bpm: [Double]

  var body: some View {
    GeometryReader { geo in
      let w = geo.size.width
      let h = geo.size.height
      if bpm.count >= 2, let minV = bpm.min(), let maxV = bpm.max() {
        let span = max(maxV - minV, 0.001)
        let pts = bpm.enumerated().map { i, v in
          CGPoint(
            x: w * CGFloat(i) / CGFloat(bpm.count - 1),
            y: h - h * CGFloat((v - minV) / span))
        }
        ZStack {
          Path { p in
            p.move(to: CGPoint(x: pts[0].x, y: h))
            for pt in pts { p.addLine(to: pt) }
            p.addLine(to: CGPoint(x: pts[pts.count - 1].x, y: h))
            p.closeSubpath()
          }
          .fill(.fade(Theme.gradHeart[0], opacity: 0.28))
          Path { p in
            p.move(to: pts[0])
            for pt in pts.dropFirst() { p.addLine(to: pt) }
          }
          .stroke(Theme.gradHeart[0], style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
          Circle()
            .fill(Theme.gradHeart[1])
            .frame(width: 7, height: 7)
            .overlay(Circle().strokeBorder(Theme.card, lineWidth: 2))
            .position(pts[pts.count - 1])
        }
      }
    }
  }
}
