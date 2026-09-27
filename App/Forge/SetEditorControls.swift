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

/// Rep tally: one capsule per rep, filled up to the count. The filled pills ramp through the
/// exercise gradient deep → bright across the row; the rest stay track outlines. A tap sets
/// the count; the row is a 44 pt target, and a scroll that starts on it never changes the count.
struct RepPills: View {
  @Binding var reps: Int
  var count: Int = 12
  var onStep: () -> Void = {}
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    GeometryReader { geo in
      HStack(spacing: 4) {
        ForEach(1...count, id: \.self) { n in
          Capsule()
            .fill(
              n <= reps
              ? Color.mix(
                Theme.gradExercise[0], Theme.gradExercise[1],
                Double(n - 1) / Double(max(1, reps - 1)), in: colorScheme)
              : Color.clear)
            .overlay(
              Capsule().strokeBorder(n <= reps ? Color.clear : Theme.track, lineWidth: 1.5))
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

/// After-set effort question: 6–10 zone chips, the plan's target marked with a dot. Nothing
/// is saved until a value is tapped.
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
          VStack(spacing: 5) {
            Text(Fmt.num(value))
              .forge(21, .bold)
              .monospacedDigit()
              .foregroundStyle(on ? Theme.zoneTextOnFill(rpe: value) : Theme.text)
            Capsule()
              .fill(
                on ? Theme.zoneTextOnFill(rpe: value).opacity(0.55) : Theme.zone(rpe: value)[0])
              .frame(width: 18, height: 3)
          }
          .frame(maxWidth: .infinity, minHeight: 56)
          .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
              .fill(
                on
                ? AnyShapeStyle(
                  .mark(Theme.zone(rpe: value), startPoint: .topLeading, endPoint: .bottomTrailing))
                : AnyShapeStyle(Theme.innerSurface)))
          .overlay(alignment: .topTrailing) {
            if value == target.rounded() && !on {
              Circle().fill(Theme.accent).frame(width: 5, height: 5).padding(5)
            }
          }
          .contentShape(Rectangle())
        }
        .buttonStyle(ControlPressStyle())
        .accessibilityLabel(String(localized: "Reported effort \(Fmt.num(value))", bundle: L10n.bundle))
        .accessibilityAddTraits(on ? .isSelected : [])
      }
    }
    .animation(.easeOut(duration: 0.15), value: selected)
  }
}

/// Pinned exercise-name tabs (Huawei pattern): the current one reads accent with an accent
/// underline, finished ones carry a green check; a tap jumps the editor exactly like the old
/// rail thumbnails did, and the current tab stays scrolled into view.
struct ExerciseTabs: View {
  struct Item: Identifiable {
    let id: String
    let name: String
    let done: Bool
    let current: Bool
  }

  let items: [Item]
  let onTap: (String) -> Void

  private var currentID: String? { items.first(where: \.current)?.id }

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 22) {
          ForEach(items) { item in
            tab(item)
              .id(item.id)
          }
        }
        .padding(.horizontal, 16)
      }
      .frame(height: 44)
      .onAppear { scrollCurrent(proxy) }
      .onChange(of: currentID) { _, _ in scrollCurrent(proxy) }
    }
  }

  private func scrollCurrent(_ proxy: ScrollViewProxy) {
    guard let id = currentID else { return }
    proxy.scrollTo(id, anchor: .center)
  }

  private func tab(_ item: Item) -> some View {
    Button {
      onTap(item.id)
    } label: {
      HStack(spacing: 4) {
        Text(item.name)
          .forge(15, item.current ? .semibold : .medium)
          .foregroundStyle(item.current ? Theme.accentText : Theme.textSecondary)
          .lineLimit(1)
          .overlay(alignment: .bottom) {
            if item.current {
              RoundedRectangle(cornerRadius: 2)
                .fill(Theme.accent)
                .frame(height: 3)
                .offset(y: 12)
            }
          }
        if item.done {
          Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.positive)
        }
      }
      .frame(minHeight: 44)
      .contentShape(Rectangle())
    }
    .buttonStyle(ControlPressStyle())
    .accessibilityLabel(item.name)
    .accessibilityAddTraits(item.current ? .isSelected : [])
  }
}

/// Flat art tile for the workout page (Huawei pattern): the illustration centered on a
/// recessed surface with a hairline outline, radius 12.
struct WorkoutArtTile: View {
  let exercise: Exercise
  var size: CGFloat = 56

  var body: some View {
    if UIImage(named: "ex-\(exercise.id)") != nil {
      Image("ex-\(exercise.id)")
        .resizable()
        .scaledToFit()
        .padding(6)
        .frame(width: size, height: size)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.innerSurface))
        .overlay(
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(Theme.imageOutline, lineWidth: 1))
        .accessibilityHidden(true)
    } else {
      MuscleThumb(exercise: exercise, size: size)
    }
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

extension Color {
  /// Linear mix of two Theme colors in the given appearance — the rep pills ramp between the
  /// exercise gradient's endpoints. Derived from existing tokens, not a new palette color.
  static func mix(_ a: Color, _ b: Color, _ t: Double, in scheme: ColorScheme) -> Color {
    let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
    func components(_ c: Color) -> (Double, Double, Double, Double) {
      var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, a: CGFloat = 0
      UIColor(c).resolvedColor(with: traits).getRed(&r, green: &g, blue: &bl, alpha: &a)
      return (Double(r), Double(g), Double(bl), Double(a))
    }
    let x = min(1, max(0, t))
    let (r1, g1, b1, a1) = components(a)
    let (r2, g2, b2, a2) = components(b)
    return Color(
      .sRGB,
      red: r1 + (r2 - r1) * x,
      green: g1 + (g2 - g1) * x,
      blue: b1 + (b2 - b1) * x,
      opacity: a1 + (a2 - a1) * x)
  }
}
