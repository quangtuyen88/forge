import ForgeCore
import SwiftUI

/// "Muscles this week" card body: the écorché figures tint as the top-muscle bars count up.
/// The appear animation plays only when the week's numbers changed since the last visit.
struct MusclesWeekCard: View {
  let weekSets: [Muscle: Double]
  let top: [(muscle: Muscle, sets: Double)]

  @State private var barsShown = 0
  @State private var countsShown = 0
  @State private var shown: Set<Muscle> = []
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @AppStorage("progress.musclesSeen") private var seen = ""

  private var maxSets: Double { top.map(\.sets).max() ?? 1 }

  /// What counts as "the same week as last time": the week start plus the top rows' numbers.
  private var signature: String {
    let weekStart = TrainingMetrics.reportingWeek(
      containing: .now, calendar: TrainingMetrics.reportingCalendar()
    ).start
    return
      "\(weekStart.timeIntervalSince1970)|"
      + top.map { "\($0.muscle.rawValue):\($0.sets)" }.joined(separator: ",")
  }

  private var worked: Set<Muscle> { Set(weekSets.filter { $0.value > 0 }.map(\.key)) }

  var body: some View {
    HStack(alignment: .center, spacing: 16) {
      MuscleMapView(intensity: [:], selected: shown)
        .frame(width: 148)
      Divider()
      bars
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityText)
    .onAppear {
      // Fast-forward only; the animated play waits for real visibility (iOS 18 modifier),
      // because a non-lazy VStack fires onAppear for off-screen children too.
      if reduceMotion || signature == seen {
        barsShown = top.count
        countsShown = top.count
        shown = worked
      }
    }
    .modifier(WhenVisible(action: playAppearAnimation))
    .onChange(of: signature) { _, _ in playAppearAnimation() }
  }

  private var accessibilityText: String {
    top.isEmpty
      ? String(localized: "Log a set this week to see which muscles worked.", bundle: L10n.bundle)
      : String(
        localized:
          "Muscles this week: \(top.map { String(localized: "\($0.muscle.a11yName) \(Fmt.num($0.sets)) sets", bundle: L10n.bundle) }.joined(separator: ", "))",
        bundle: L10n.bundle)
  }

  @ViewBuilder private var bars: some View {
    if top.isEmpty {
      Text("Log a set this week to see which muscles worked.")
        .forgeLabel()
        .foregroundStyle(Theme.textSecondary)
    } else {
      VStack(alignment: .leading, spacing: 14) {
        ForEach(Array(top.enumerated()), id: \.element.muscle) { i, entry in
          VStack(alignment: .leading, spacing: 4) {
            HStack {
              Text(entry.muscle.a11yName).forge(15, .semibold).foregroundStyle(Theme.text)
              Spacer()
              Text("\(Fmt.num(entry.sets)) sets")
                .forge(15, .regular)
                .foregroundStyle(Theme.textSecondary)
                .monospacedDigit()
                .opacity(countsShown > i ? 1 : 0)
                .offset(y: countsShown > i ? 0 : 12)
                .blur(radius: countsShown > i ? 0 : 4)
            }
            GeometryReader { g in
              ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule().fill(Theme.accent)
                  .frame(width: barsShown > i ? max(10, g.size.width * entry.sets / maxSets) : 0)
              }
            }
            .frame(height: 10)
          }
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private func playAppearAnimation() {
    if reduceMotion || signature == seen {
      barsShown = top.count
      countsShown = top.count
      shown = worked
      return
    }
    for i in top.indices {
      withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.7).delay(0.3 + Double(i) * 0.1)) {
        barsShown = i + 1
        shown.insert(top[i].muscle)
      }
      withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.4).delay(0.45 + Double(i) * 0.1)) {
        countsShown = i + 1
      }
    }
    let extra = worked.subtracting(top.map(\.muscle))
    if !extra.isEmpty {
      withAnimation(
        .timingCurve(0.23, 1, 0.32, 1, duration: 0.7)
          .delay(0.3 + Double(max(top.count - 1, 0)) * 0.1)
      ) {
        shown.formUnion(extra)
      }
    }
    seen = signature
  }
}

/// Runs `action` once the card is half on screen (iOS 18+); earlier systems fall back to appear.
private struct WhenVisible: ViewModifier {
  let action: () -> Void

  func body(content: Content) -> some View {
    if #available(iOS 18, *) {
      content.onScrollVisibilityChange(threshold: 0.5) { visible in
        if visible { action() }
      }
    } else {
      content.onAppear(perform: action)
    }
  }
}
