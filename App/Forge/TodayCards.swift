import SwiftUI
import ForgeCore

/// Coach photo on top of Today's hero card: week chip (opens the roadmap) and readiness chip.
struct HeroPhoto: View {
  let imageName: String
  let weekLabel: String
  let stateLabel: String
  let stateColor: Color
  let appeared: Bool
  let onWeekTap: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Color.clear
      .frame(height: 188)
      .overlay {
        Image(imageName)
          .resizable()
          .scaledToFill()
          .scaleEffect(appeared || reduceMotion ? 1 : 1.08)
          .animation(reduceMotion ? nil : .easeOut(duration: 0.9).delay(0.05), value: appeared)
          .allowsHitTesting(false)
          .accessibilityHidden(true)
      }
      .clipped()
      .contentShape(Rectangle())
      .overlay(alignment: .topLeading) {
        Button(action: onWeekTap) {
          HStack(spacing: 4) {
            Text(weekLabel)
            Image(systemName: "chevron.right").font(.system(size: 10, weight: .bold))
          }
          .photoChip()
        }
        .buttonStyle(ControlPressStyle())
        .padding(12)
        .accessibilityLabel("Program roadmap, \(weekLabel)")
      }
      .overlay(alignment: .topTrailing) {
        HStack(spacing: 4) {
          Image(systemName: "heart.fill").font(.system(size: 11, weight: .bold))
          Text(stateLabel)
        }
        .foregroundStyle(stateColor)
        .photoChip()
        .padding(12)
        .accessibilityElement(children: .combine)
      }
  }
}

extension View {
  /// Dark translucent capsule that stays legible on any photo.
  fileprivate func photoChip() -> some View {
    self
      .font(.forge(12, .semibold))
      .lineLimit(1)
      .foregroundStyle(.white)
      .padding(.horizontal, 10)
      .frame(height: 28)
      .background(Capsule().fill(.black.opacity(0.55)))
      .environment(\.colorScheme, .dark)
  }
}

/// Front and back figures with the day's worked muscles in the accent.
struct MiniMuscleMap: View {
  let muscles: Set<Muscle>
  var height: CGFloat = 76

  var body: some View {
    HStack(spacing: 4) {
      MuscleFigure(side: .front, tint: { muscles.contains($0) ? Theme.accent : nil })
      MuscleFigure(side: .back, tint: { muscles.contains($0) ? Theme.accent : nil })
    }
    .frame(height: height)
  }
}

/// Today's plan carousel card: exercise art, an up badge when the load goes up, the name.
struct PlanArtCard: View {
  let exercise: Exercise
  let goesUp: Bool
  let isNew: Bool
  let index: Int
  let appeared: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ExerciseArt(exercise: exercise, size: 112)
        .overlay(alignment: .topTrailing) {
          if goesUp {
            Image(systemName: "arrow.up")
              .font(.system(size: 11, weight: .bold))
              .foregroundStyle(Theme.onAccent)
              .frame(width: 24, height: 24)
              .background(Circle().fill(Theme.positive))
              .padding(6)
              .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
              .opacity(appeared ? 1 : 0)
              .animation(
                reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.3).delay(0.75),
                value: appeared)
          }
        }
      Text(exercise.localizedName)
        .forge(13, .semibold)
        .foregroundStyle(Theme.text)
        .lineLimit(2)
        .fixedSize(horizontal: false, vertical: true)
      if isNew {
        Text("New variant").forge(11, .semibold).foregroundStyle(Theme.accent)
      }
    }
    .frame(width: 112, alignment: .leading)
    .opacity(appeared ? 1 : 0)
    .offset(x: appeared || reduceMotion ? 0 : 18)
    .animation(
      reduceMotion ? .easeOut(duration: 0.2) : .easeOut(duration: 0.4).delay(0.16 + Double(index) * 0.045),
      value: appeared)
    .accessibilityElement(children: .combine)
  }
}

/// Weeks-in-a-row chip with the clay flame; the flame flicks once when Today first appears.
struct StreakChip: View {
  let weeks: Int
  let appeared: Bool
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var flick = false

  var body: some View {
    HStack(spacing: 6) {
      Image("art-streak")
        .resizable()
        .scaledToFit()
        .frame(width: 22, height: 22)
        .rotationEffect(.degrees(flick ? -6 : 0))
        .scaleEffect(flick ? 1.15 : 1)
      Text(verbatim: "\(weeks) wk")
        .forge(13, .semibold)
        .monospacedDigit()
        .foregroundStyle(Theme.metricEffort)
    }
    .padding(.leading, 6)
    .padding(.trailing, 10)
    .frame(height: 30)
    .background(Capsule().fill(Theme.metricEffort.opacity(0.12)))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(String(localized: "Streak", bundle: L10n.bundle))
    .accessibilityValue(Text(verbatim: "\(weeks) wk"))
    .onChange(of: appeared, initial: true) { _, shown in
      guard shown, !reduceMotion else { return }
      Task {
        try? await Task.sleep(for: .milliseconds(900))
        withAnimation(.spring(duration: 0.3, bounce: 0.4)) { flick = true }
        try? await Task.sleep(for: .milliseconds(260))
        withAnimation(.spring(duration: 0.4, bounce: 0.3)) { flick = false }
      }
    }
  }
}

/// Illustrated shortcut tile: square art, a check when today's part is done, a short title.
struct ImageTile: View {
  let image: String
  let title: String
  var done = false
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      VStack(alignment: .leading, spacing: 8) {
        Color.clear
          .aspectRatio(1, contentMode: .fit)
          .overlay { Image(image).resizable().scaledToFill().allowsHitTesting(false) }
          .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
          .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
              .strokeBorder(Theme.imageOutline, lineWidth: 1)
          )
          .overlay(alignment: .topTrailing) {
            if done {
              Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Theme.onAccent)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.positive))
                .padding(8)
            }
          }
        Text(title)
          .forge(14, .semibold)
          .foregroundStyle(Theme.text)
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(ControlPressStyle())
    .frame(maxWidth: .infinity)
    .accessibilityLabel(title)
    .accessibilityValue(done ? String(localized: "Done today", bundle: L10n.bundle) : "")
  }
}

/// Best-lift card: trophy art, the lift's name, its best estimate.
struct RecordCard: View {
  let label: String
  let value: String
  let unit: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 14) {
        Image("art-pro")
          .resizable()
          .scaledToFit()
          .frame(width: 56, height: 56)
          .accessibilityHidden(true)
        VStack(alignment: .leading, spacing: 2) {
          Text(label).forgeLabel().lineLimit(1)
          HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(value)
              .forge(28, .bold, tracking: -0.8)
              .monospacedDigit()
              .foregroundStyle(Theme.text)
            Text(unit).forge(13, .semibold).foregroundStyle(Theme.textSecondary)
          }
        }
        Spacer(minLength: 8)
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .bold))
          .foregroundStyle(Theme.textTertiary)
      }
      .card(padding: 14)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityElement(children: .combine)
  }
}
