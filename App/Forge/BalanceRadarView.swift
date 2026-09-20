import Charts
import ForgeCore
import SwiftData
import SwiftUI


private enum BalanceAxis: String, CaseIterable, Identifiable {
  case push, pull, legs
  var id: String { rawValue }

  var name: String {
    switch self {
    case .push: return "Push"
    case .pull: return "Pull"
    case .legs: return "Legs"
    }
  }

  var color: Color {
    switch self {
    case .push: return Theme.metricLoad
    case .pull: return Theme.metricTime
    case .legs: return Theme.metricSets
    }
  }
}
struct BalanceRadarView: View {
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]

  private var recentSessions: [WorkoutSession] {
    sessions.filter { $0.completed && $0.date > Date.now.addingTimeInterval(-28 * 86400) }
  }

  private var sets: [LoggedSet] { recentSessions.flatMap(\.trustedSets) }

  private var counts: [BalanceAxis: Double] {
    var out: [BalanceAxis: Double] = [:]
    for set in sets {
      guard let exercise = ExerciseDB.find(set.exerciseID) else { continue }
      switch exercise.pattern {
      case .horizontalPush, .verticalPush: out[.push, default: 0] += 1
      case .horizontalPull, .verticalPull: out[.pull, default: 0] += 1
      case .squat, .hinge: out[.legs, default: 0] += 1
      default: break
      }
    }
    return out
  }

  private var presentation: BalancePresentation {
    let push = counts[.push, default: 0]
    let pull = counts[.pull, default: 0]
    let legs = counts[.legs, default: 0]
    return BalancePresentationPolicy.presentation(
      push: push,
      pull: pull,
      upper: push + pull,
      lower: legs,
      sessionCount: recentSessions.count,
      setCount: sets.count)
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        coverageCard
        switch presentation {
        case .collecting:
          collectingCard
        case .assessed(let pushPull, let upperLower, _, _):
          chartCard
          HStack(spacing: 10) {
            ratioCard("Push : pull", value: pushPull)
            ratioCard("Upper : lower", value: upperLower)
          }
          adviceCard(pushPull: pushPull, upperLower: upperLower)
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Balance")
  }

  private var coverageCard: some View {
    HStack(spacing: 12) {
      Image(systemName: "checklist.checked")
        .foregroundStyle(Theme.metricTime)
        .frame(width: 40, height: 40)
        .background(Circle().fill(Theme.metricTime.opacity(0.12)))
      VStack(alignment: .leading, spacing: 3) {
        Text("Recorded coverage").forgeBodyStrong()
        Text(
          "\(recentSessions.count) eligible sessions · \(sets.count) eligible sets · last 28 days"
        )
        .forgeCaption().monospacedDigit()
      }
      Spacer()
    }
    .card()
    .accessibilityElement(children: .combine)
  }

  private var collectingCard: some View {
    VStack(spacing: 12) {
      Image(systemName: "circle.dashed")
        .font(.system(size: 36, weight: .semibold))
        .foregroundStyle(Theme.textTertiary)
      Text("Collecting balance evidence").forgeTitle()
      Text(
        "Record at least \(BalancePresentationPolicy.minimumSessions) eligible sessions and \(BalancePresentationPolicy.minimumSets) eligible sets before ReguLift calculates ratios or recommends a change."
      )
      .forgeLabel().multilineTextAlignment(.center)
    }
    .card()
  }

  private var chartCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Eligible sets by movement").forgeSection()
      Chart(BalanceAxis.allCases) { axis in
        BarMark(
          x: .value("Sets", counts[axis, default: 0]),
          y: .value("Movement", axis.name)
        )
        .foregroundStyle(axis.color)
        .cornerRadius(3)
      }
      .chartXAxis {
        AxisMarks(position: .bottom) {
          AxisGridLine().foregroundStyle(Theme.track)
          AxisValueLabel().font(.forge(11, .medium)).foregroundStyle(Theme.textTertiary)
        }
      }
      .frame(height: 180)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(
        "Movement balance: \(BalanceAxis.allCases.map { "\($0.name) \(Int(counts[$0, default: 0])) sets" }.joined(separator: ", "))"
      )
    }
    .card()
  }

  private func ratioCard(_ title: String, value: Double?) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      MetricValue(
        value: value.map { Fmt.num($0) } ?? "—", unit: value == nil ? nil : "×", size: 26,
        color: Theme.metricSets)
      Text(title).forgeCaption().fixedSize(horizontal: false, vertical: true)
      if value == nil { Text("Not assessable").forgeCaption().foregroundStyle(Theme.textTertiary) }
    }
    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
    .card()
  }

  private func adviceCard(pushPull: Double?, upperLower: Double?) -> some View {
    let message: String
    if let ratio = pushPull, ratio < 0.75 {
      message = String(
        localized:
          "Eligible pulling work exceeds pressing work. Review the contributing sessions before changing the plan.",
        bundle: L10n.bundle)
    } else if let ratio = pushPull, ratio > 1.35 {
      message = String(
        localized:
          "Eligible pressing work exceeds pulling work. Review the contributing sessions before changing the plan.",
        bundle: L10n.bundle)
    } else if upperLower == nil || pushPull == nil {
      message = String(
        localized:
          "A ratio is unavailable because one side has no eligible sets. No plan change is recommended.",
        bundle: L10n.bundle)
    } else {
      message = String(
        localized:
          "Recorded movement balance is within the review range. No extra set is prescribed from this view.",
        bundle: L10n.bundle)
    }
    return HStack(alignment: .top, spacing: 10) {
      Image(systemName: "info.circle.fill").foregroundStyle(Theme.metricTime)
      Text(message).forgeBody()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }
}

private struct RadarChart: View {
  let values: [Double]
  let labels: [String]

  var body: some View {
    Canvas { context, size in
      let center = CGPoint(x: size.width / 2, y: size.height / 2)
      let radius = min(size.width, size.height) / 2 - 22
      let maxV = max(values.max() ?? 0, 1)

      func point(axis: Int, fraction: CGFloat) -> CGPoint {
        let angle = Double(axis) * .pi / 3 - .pi / 2
        return CGPoint(
          x: center.x + radius * fraction * CGFloat(cos(angle)),
          y: center.y + radius * fraction * CGFloat(sin(angle)))
      }

      for step in [0.25, 0.5, 0.75, 1.0] {
        var web = Path()
        for a in 0...5 {
          let p = point(axis: a, fraction: step)
          a == 0 ? web.move(to: p) : web.addLine(to: p)
        }
        web.closeSubpath()
        context.stroke(web, with: .color(Theme.track), lineWidth: 1)
      }
      for a in 0..<6 {
        context.stroke(
          Path {
            $0.move(to: center)
            $0.addLine(to: point(axis: a, fraction: 1))
          },
          with: .color(Theme.track), lineWidth: 1)
      }

      var poly = Path()
      for a in 0...5 {
        let p = point(axis: a, fraction: CGFloat(values[a] / maxV))
        a == 0 ? poly.move(to: p) : poly.addLine(to: p)
      }
      poly.closeSubpath()
      context.fill(poly, with: .color(Theme.accentValue.opacity(0.22)))
      context.stroke(
        poly, with: .color(Theme.accentValue),
        style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
      for a in 0..<6 {
        let p = point(axis: a, fraction: CGFloat(values[a] / maxV))
        context.fill(
          Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)),
          with: .color(Theme.accentValue))
      }

      for (a, label) in labels.enumerated() {
        context.draw(
          Text(label).forge(11, .medium).foregroundStyle(Theme.textTertiary),
          at: point(axis: a, fraction: 1.24))
      }
    }
    .aspectRatio(1, contentMode: .fit)
    .frame(maxWidth: .infinity)
  }
}
