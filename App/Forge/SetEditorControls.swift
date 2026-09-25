import SwiftUI
import UIKit
import ForgeCore

/// Horizontal tick ruler for the set's load, in display units. A sideways drag scrubs one
/// increment per tick and settles on a tick; a vertical drag is left to the page scroll.
struct WeightRuler: View {
  @Binding var value: Double
  let step: Double
  let unit: String
  var onStep: () -> Void = {}
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var dragStart: Double?
  @State private var residual: CGFloat = 0
  private let spacing: CGFloat = 12

  var body: some View {
    GeometryReader { geo in
      let mid = geo.size.width / 2
      let half = Int(mid / spacing) + 2
      let center = (value / step).rounded()
      let fraction = CGFloat(value / step - center) * spacing
      ZStack(alignment: .topLeading) {
        ForEach(-half...half, id: \.self) { k in
          let tickValue = (center + Double(k)) * step
          if tickValue >= 0 {
            let x = mid + CGFloat(k) * spacing - residual - fraction
            tickMark(tickValue)
              .position(x: x, y: 24)
              .opacity(fade(x: x, mid: mid))
          }
        }
        Capsule()
          .fill(Theme.accent)
          .frame(width: 4, height: 34)
          .position(x: mid, y: 17)
      }
    }
    .frame(height: 56)
    .clipped()
    .contentShape(Rectangle())
    .overlay {
      HorizontalPanSurface(
        onChanged: { dx in
          let start = dragStart ?? value
          if dragStart == nil { dragStart = value }
          let travel = -dx
          let ticks = (travel / spacing).rounded()
          residual = travel - ticks * spacing
          let next = max(0, start + Double(ticks) * step)
          if next != value {
            value = next
            onStep()
          }
        },
        onEnded: {
          dragStart = nil
          withAnimation(reduceMotion ? nil : .spring(duration: 0.3, bounce: 0)) { residual = 0 }
        }
      )
      .accessibilityHidden(true)
    }
    .accessibilityElement()
    .accessibilityLabel(String(localized: "Weight", bundle: L10n.bundle))
    .accessibilityValue("\(Fmt.num(value)) \(unit)")
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        value += step
        onStep()
      case .decrement:
        value = max(0, value - step)
        onStep()
      @unknown default: break
      }
    }
  }

  private func isMajor(_ v: Double) -> Bool {
    let major = step * 4
    let remainder = v.truncatingRemainder(dividingBy: major)
    return abs(remainder) < 0.001 || abs(remainder - major) < 0.001
  }

  private func tickMark(_ v: Double) -> some View {
    let major = isMajor(v)
    return VStack(spacing: 4) {
      Capsule()
        .fill(Theme.textSecondary)
        .frame(width: 2, height: major ? 26 : 14)
      Text(major ? Fmt.num(v) : " ")
        .forge(11, .semibold)
        .monospacedDigit()
        .foregroundStyle(Theme.textSecondary)
        .fixedSize()
    }
    .frame(height: 48, alignment: .top)
  }

  private func fade(x: CGFloat, mid: CGFloat) -> Double {
    let d = Double(abs(x - mid) / max(mid, 1))
    return max(0.06, 1 - 1.4 * d * d)
  }
}

/// Rep tally: one capsule per rep, filled up to the count. A tap sets the count; the row is a
/// 44 pt target, and a scroll that starts on it never changes the count.
struct RepPills: View {
  @Binding var reps: Int
  var count: Int = 12
  var onStep: () -> Void = {}

  var body: some View {
    GeometryReader { geo in
      HStack(spacing: 4) {
        ForEach(1...count, id: \.self) { n in
          Capsule()
            .fill(n <= reps ? Theme.metricSets : Color.clear)
            .overlay(
              Capsule().strokeBorder(n <= reps ? Theme.metricSets : Theme.track, lineWidth: 2))
            .frame(height: 28)
        }
      }
      .frame(maxHeight: .infinity)
      .contentShape(Rectangle())
      .onTapGesture(coordinateSpace: .local) { location in
        let n = min(count, max(1, Int(location.x / (geo.size.width / CGFloat(count))) + 1))
        if n != reps {
          reps = n
          onStep()
        }
      }
    }
    .frame(height: 44)
    .accessibilityElement()
    .accessibilityLabel(String(localized: "Reps", bundle: L10n.bundle))
    .accessibilityValue(String(localized: "\(reps) reps", bundle: L10n.bundle))
    .accessibilityAdjustableAction { direction in
      switch direction {
      case .increment:
        reps += 1
        onStep()
      case .decrement:
        reps = max(1, reps - 1)
        onStep()
      @unknown default: break
      }
    }
  }
}

/// After-set effort question: 6–10, the plan's target marked with a dot. Nothing is saved
/// until a value is tapped.
struct RPEPicker: View {
  let selected: Double?
  let target: Double
  let onPick: (Double) -> Void

  var body: some View {
    HStack(spacing: 8) {
      ForEach([6.0, 7, 8, 9, 10], id: \.self) { value in
        let on = selected == value
        Button {
          onPick(value)
        } label: {
          Text(Fmt.num(value))
            .forge(15, .semibold)
            .monospacedDigit()
            .foregroundStyle(on ? Color.black : Theme.text)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(Capsule().fill(on ? Theme.metricEffort : Theme.innerSurface))
            .overlay(alignment: .bottom) {
              if value == target.rounded() && !on {
                Circle().fill(Theme.metricEffort).frame(width: 4, height: 4).padding(.bottom, 6)
              }
            }
        }
        .buttonStyle(ControlPressStyle())
        .accessibilityLabel(String(localized: "Reported effort \(Fmt.num(value))", bundle: L10n.bundle))
        .accessibilityAddTraits(on ? .isSelected : [])
      }
    }
    .animation(.easeOut(duration: 0.15), value: selected)
  }
}

/// Pinned strip of the session's exercises with an adherence bar. The current one is ringed,
/// finished ones dim with a check; a tap jumps the editor there.
struct ExerciseRail: View {
  struct Item: Identifiable {
    let id: String
    let exercise: Exercise
    let done: Bool
    let current: Bool
  }

  let items: [Item]
  let progress: Double
  var progressLabel: String = ""
  let onTap: (String) -> Void

  var body: some View {
    VStack(spacing: 8) {
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 8) {
          ForEach(items) { item in
            Button {
              onTap(item.id)
            } label: {
              ExerciseArt(exercise: item.exercise, size: 48)
                .opacity(item.done ? 0.45 : 1)
                .overlay(alignment: .bottomTrailing) {
                  if item.done {
                    Image(systemName: "checkmark")
                      .font(.system(size: 9, weight: .bold))
                      .foregroundStyle(Theme.onAccent)
                      .frame(width: 18, height: 18)
                      .background(Circle().fill(Theme.positive))
                      .offset(x: 4, y: 4)
                  }
                }
                .padding(3)
                .overlay(
                  RoundedRectangle(cornerRadius: Theme.radiusRow + 3, style: .continuous)
                    .strokeBorder(item.current ? Theme.accent : Color.clear, lineWidth: 2))
            }
            .buttonStyle(ControlPressStyle())
            .accessibilityLabel(item.exercise.localizedName)
            .accessibilityAddTraits(item.current ? .isSelected : [])
          }
        }
        .padding(.vertical, 4)
      }
      Capsule()
        .fill(Theme.track)
        .frame(height: 4)
        .overlay(alignment: .leading) {
          GeometryReader { geo in
            Capsule()
              .fill(Theme.metricSets)
              .frame(width: geo.size.width * min(1, max(0, progress)))
          }
        }
        .animation(.easeOut(duration: 0.4), value: progress)
        .accessibilityElement()
        .accessibilityLabel(progressLabel)
    }
  }
}

/// Large exercise illustration on a white plate for the active set card.
struct ExerciseHeroArt: View {
  let exercise: Exercise
  var height: CGFloat = 176

  var body: some View {
    Group {
      if UIImage(named: "ex-\(exercise.id)") != nil {
        Image("ex-\(exercise.id)")
          .resizable()
          .scaledToFit()
          .frame(maxWidth: .infinity)
          .frame(height: height)
          .background(Color.white)
      } else {
        MuscleThumb(exercise: exercise, size: height * 0.8)
          .frame(maxWidth: .infinity)
          .frame(height: height)
          .background(Theme.innerSurface)
      }
    }
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
        .strokeBorder(Theme.imageOutline, lineWidth: 1)
    )
    .accessibilityHidden(true)
  }
}

/// Transparent pan surface that begins only for sideways drags, so a vertical swipe starting on it
/// still scrolls the page.
private struct HorizontalPanSurface: UIViewRepresentable {
  var onChanged: (CGFloat) -> Void
  var onEnded: () -> Void

  func makeUIView(context: Context) -> UIView {
    let view = UIView()
    view.backgroundColor = .clear
    let pan = UIPanGestureRecognizer(
      target: context.coordinator, action: #selector(Coordinator.handle(_:)))
    pan.delegate = context.coordinator
    view.addGestureRecognizer(pan)
    return view
  }

  func updateUIView(_ view: UIView, context: Context) {
    context.coordinator.onChanged = onChanged
    context.coordinator.onEnded = onEnded
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(onChanged: onChanged, onEnded: onEnded)
  }

  final class Coordinator: NSObject, UIGestureRecognizerDelegate {
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void

    init(onChanged: @escaping (CGFloat) -> Void, onEnded: @escaping () -> Void) {
      self.onChanged = onChanged
      self.onEnded = onEnded
    }

    @objc func handle(_ pan: UIPanGestureRecognizer) {
      switch pan.state {
      case .changed: onChanged(pan.translation(in: pan.view).x)
      case .ended, .cancelled, .failed: onEnded()
      default: break
      }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
      guard let pan = gestureRecognizer as? UIPanGestureRecognizer else { return true }
      let velocity = pan.velocity(in: pan.view)
      return abs(velocity.x) > abs(velocity.y)
    }
  }
}
