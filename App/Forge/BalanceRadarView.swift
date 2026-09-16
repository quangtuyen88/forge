import SwiftUI
import SwiftData
import ForgeCore

struct BalanceRadarView: View {
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]

  private var counts: [Double] {
    let cutoff = Date.now.addingTimeInterval(-4 * 7 * 86400)
    var push = 0.0, pull = 0.0, legs = 0.0, core = 0.0, delts = 0.0, arms = 0.0
    for s in sessions where s.completed && s.date > cutoff {
      for set in s.sets where set.rpe >= 6 {
        guard let ex = ExerciseDB.find(set.exerciseID) else { continue }
        switch ex.primary {
        case .chest, .frontDelts, .triceps: push += 1
        case .back, .rearDelts, .biceps: pull += 1
        case .quads, .hamstrings, .glutes, .calves: legs += 1
        case .abs: core += 1
        case .sideDelts: delts += 1
        case .forearms: break
        }
        if ex.primary == .biceps || ex.primary == .triceps { arms += 1 }
      }
    }
    return [push, pull, legs, core, delts, arms]
  }

  private var pushPullRatio: Double {
    counts[0] / max(counts[1], 1)
  }

  private var upperLowerRatio: Double {
    (counts[0] + counts[1] + counts[3] + counts[4]) / max(counts[2], 1)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.groupGap) {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .firstTextBaseline) {
            Text("Balance").forgeSection()
            Spacer()
            Text("last 4 weeks").forgeCaption()
          }
          RadarChart(values: counts, labels: ["Push", "Pull", "Legs", "Core", "Delts", "Arms"])
            .frame(maxWidth: .infinity)
            .frame(height: 230)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()

        VStack(alignment: .leading, spacing: 8) {
          Text(String(format: "Push : Pull %.1f", pushPullRatio))
            .forgeLabel()
            .monospacedDigit()
          if pushPullRatio > 1.25 {
            Text("Pull is lagging. Add a row.").forgeCaption()
          } else if pushPullRatio < 0.8 {
            Text("Push is lagging. Add a pressing set.").forgeCaption()
          }
          Text(String(format: "Upper : Lower %.1f", upperLowerRatio))
            .forgeLabel()
            .monospacedDigit()
          if upperLowerRatio > 1.25 {
            Text("Legs are lagging. Add a leg day.").forgeCaption()
          } else if upperLowerRatio < 0.8 {
            Text("Upper body is lagging. Add an upper day.").forgeCaption()
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Balance")
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
        return CGPoint(x: center.x + radius * fraction * CGFloat(cos(angle)),
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
        context.stroke(Path { $0.move(to: center); $0.addLine(to: point(axis: a, fraction: 1)) },
                       with: .color(Theme.track), lineWidth: 1)
      }

      var poly = Path()
      for a in 0...5 {
        let p = point(axis: a, fraction: CGFloat(values[a] / maxV))
        a == 0 ? poly.move(to: p) : poly.addLine(to: p)
      }
      poly.closeSubpath()
      context.fill(poly, with: .color(Theme.accentValue.opacity(0.22)))
      context.stroke(poly, with: .color(Theme.accentValue), style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
      for a in 0..<6 {
        let p = point(axis: a, fraction: CGFloat(values[a] / maxV))
        context.fill(Path(ellipseIn: CGRect(x: p.x - 3, y: p.y - 3, width: 6, height: 6)), with: .color(Theme.accentValue))
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
