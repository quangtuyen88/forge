import SwiftUI
import ForgeCore

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
      .todayCard(padding: 14)
      .contentShape(Rectangle())
    }
    .buttonStyle(RowPressStyle())
    .accessibilityElement(children: .combine)
  }
}
