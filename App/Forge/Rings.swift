import SwiftUI

struct RingView: View {
  var progress: Double
  var lineWidth: CGFloat = 10
  var color: Color = Theme.accent
  var track: Color = Theme.track
  var accessibilityLabel: String? = nil

  @State private var animated: Double = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      Circle().stroke(track, lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: animated)
        .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        .rotationEffect(.degrees(-90))
    }
    .padding(lineWidth / 2)
    .onAppear { animate() }
    .onChange(of: progress) { _ in animate() }
    .modifier(RingA11y(label: accessibilityLabel))
  }

  private func animate() {
    withAnimation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0)) {
      animated = min(1, max(0, progress))
    }
  }
}

private struct RingA11y: ViewModifier {
  let label: String?

  func body(content: Content) -> some View {
    if let label {
      content.accessibilityElement(children: .ignore).accessibilityLabel(label)
    } else {
      content.accessibilityHidden(true)
    }
  }
}

struct RingSpec: Identifiable {
  let id: String
  var progress: Double
  var color: Color = Theme.accent
}

struct RingsView: View {
  let rings: [RingSpec]
  var size: CGFloat = 132
  var lineWidth: CGFloat = 10
  var gap: CGFloat = 4

  var body: some View {
    ZStack {
      ForEach(Array(rings.enumerated()), id: \.element.id) { pair in
        RingView(progress: pair.element.progress, lineWidth: lineWidth, color: pair.element.color)
          .padding(CGFloat(pair.offset) * (lineWidth + gap))
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
