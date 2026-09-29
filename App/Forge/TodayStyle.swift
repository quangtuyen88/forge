import SwiftUI

/// The flat Huawei-grey Today page (DESIGN.md §12); fills the caller's frame.
struct TodayBackdrop: View {
  var body: some View {
    Theme.pageGrey
      .allowsHitTesting(false)
  }
}

/// Legibility scrim over the next-up cover photo.
struct TodayPhotoScrim: View {
  var body: some View {
    LinearGradient(
      stops: [
        .init(color: .clear, location: 0.35),
        .init(color: Color.black.opacity(0.42), location: 1),
      ],
      startPoint: .top,
      endPoint: .bottom)
    .allowsHitTesting(false)
  }
}

extension View {
  /// Elevated Today card (DESIGN.md §12): shadow on the background shape only, never on text.
  func todayCard(padding: CGFloat = 16, fill: Color = Theme.card, tint: Color? = nil) -> some View {
    self
      .padding(padding)
      .background {
        ZStack {
          RoundedRectangle(cornerRadius: Theme.radiusToday, style: .continuous).fill(fill)
          if let tint {
            RoundedRectangle(cornerRadius: Theme.radiusToday, style: .continuous).fill(tint)
          }
        }
        .shadow(color: Theme.shadow, radius: 18, x: 0, y: 10)
      }
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusToday, style: .continuous)
          .strokeBorder(Theme.todayCardRing, lineWidth: 1))
  }

  /// Glass pill: solid white fill in light, 10 % white in dark, hairline ring.
  func todayGlass<S: InsettableShape>(_ shape: S) -> some View {
    self
      .background(shape.fill(Theme.todayGlass))
      .overlay(shape.strokeBorder(Theme.todayCardRing, lineWidth: 1))
  }

  /// Tinted footer strip at the bottom of a Today card.
  func todayFooterStrip() -> some View {
    self
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
      .background(Theme.todayFooter)
  }
}

/// The flat Huawei-grey page as a fixed background for screens with a pinned header
/// (Progress, DESIGN.md §12).
struct TodaySkyPage: View {
  var body: some View {
    Theme.pageGrey
      .ignoresSafeArea()
  }
}

/// Soft gold celebration glow behind a record token (new-record sheet).
struct RecordGlow: View {
  private let size: CGFloat

  init(size: CGFloat) {
    self.size = size
  }

  var body: some View {
    ZStack {
      Circle().fill(RadialGradient(colors: [Theme.recordRing.opacity(0.30), Theme.recordRing.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
      ForEach(0..<12, id: \.self) { i in
        Capsule().fill(Theme.recordRing.opacity(0.45))
          .frame(width: 4, height: size * 0.075)
          .offset(y: -size * 0.43)
          .rotationEffect(.degrees(Double(i) * 30 + 15))
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}

/// Huawei open ring: 280° track starting at 130° (0° = 3 o'clock, clockwise), open at the
/// bottom, round caps. Track = colors[0] at 14 %; fill = colors[0] → colors[1] along the
/// swept arc. Optional white SF Symbol centered in the start cap.
struct ArcRing: View {
  var progress: Double
  var lineWidth: CGFloat
  var colors: [Color]
  var glyph: String? = nil
  var delay: Double = 0

  @State private var animated: Double = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let start = 130.0
  private static let span = 280.0

  var body: some View {
    GeometryReader { geo in
      let side = min(geo.size.width, geo.size.height)
      let radius = (side - lineWidth) / 2
      let sweep = Self.span * min(1, max(0, animated))
      let cap = CGPoint(
        x: side / 2 + radius * cos(Self.start * .pi / 180),
        y: side / 2 + radius * sin(Self.start * .pi / 180))
      ZStack {
        Circle()
          .inset(by: lineWidth / 2)
          .trim(from: 0, to: Self.span / 360)
          .stroke(colors[0].opacity(0.14), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
          .rotationEffect(.degrees(Self.start))
        // Huawei shows the solid start cap even before any progress (fix 1A); the white
        // glyph sits on it instead of on the pale track.
        Circle()
          .fill(colors[0])
          .frame(width: lineWidth, height: lineWidth)
          .position(cap)
        if sweep > 0.5 {
          Circle()
            .inset(by: lineWidth / 2)
            .trim(from: 0, to: sweep / 360)
            .stroke(
              AngularGradient(colors: colors, center: .center, startAngle: .degrees(0), endAngle: .degrees(sweep)),
              style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(Self.start))
          // The gradient clamps to the bright end before its start angle, so the end cap
          // needs its own solid color.
          Circle()
            .fill(colors[1])
            .frame(width: lineWidth, height: lineWidth)
            .position(
              x: side / 2 + radius * cos((Self.start + sweep) * .pi / 180),
              y: side / 2 + radius * sin((Self.start + sweep) * .pi / 180))
        }
        if let glyph {
          Image(systemName: glyph)
            .font(.system(size: lineWidth * 0.55))
            .foregroundStyle(.white)
            .position(cap)
        }
      }
      .frame(width: side, height: side)
      .position(x: geo.size.width / 2, y: geo.size.height / 2)
    }
    .onAppear { animate() }
    .onChange(of: progress) { _, _ in animate() }
    .accessibilityHidden(true)
  }

  private func animate() {
    withAnimation(reduceMotion ? nil : .spring(duration: 0.55, bounce: 0).delay(delay)) {
      animated = min(1, max(0, progress))
    }
  }
}

struct ArcRingSpec {
  let id: String
  var progress: Double
  var colors: [Color]
  var glyph: String? = nil
}

/// Concentric Huawei rings: outer diameter `size`, band width = size × 0.105 with a 2 pt gap
/// between bands, staggered 0.08 s per ring. Shorter than the circle: the ring is open at the bottom.
struct ArcRings: View {
  let rings: [ArcRingSpec]
  var size: CGFloat

  var body: some View {
    let band = size * 0.105
    ZStack {
      ForEach(Array(rings.enumerated()), id: \.element.id) { pair in
        let side = size - CGFloat(pair.offset) * 2 * (band + 2)
        ArcRing(
          progress: pair.element.progress,
          lineWidth: band,
          colors: pair.element.colors,
          glyph: pair.element.glyph,
          delay: Double(pair.offset) * 0.08)
          .frame(width: side, height: side)
      }
    }
    .frame(width: size, height: size * 0.92, alignment: .top)
    .accessibilityHidden(true)
  }
}

extension ShapeStyle where Self == LinearGradient {
  /// Data-mark gradient (deep → bright by default): `.fill(.mark(Theme.gradMove))`.
  static func mark(_ colors: [Color], startPoint: UnitPoint = .leading, endPoint: UnitPoint = .trailing) -> LinearGradient {
    LinearGradient(colors: colors, startPoint: startPoint, endPoint: endPoint)
  }
}

extension View {
  /// Gradient fill for data marks (capsules, bars, dots): deep → bright by default.
  /// Applies the foreground style, so bare shapes fill with it.
  func gradientFill(_ colors: [Color], startPoint: UnitPoint = .leading, endPoint: UnitPoint = .trailing) -> some View {
    foregroundStyle(.mark(colors, startPoint: startPoint, endPoint: endPoint))
  }
}

/// 8 pt gradient dot that names a metric next to a stat label.
struct GradientDot: View {
  let colors: [Color]

  var body: some View {
    Circle()
      .fill(.mark(colors, startPoint: .topLeading, endPoint: .bottomTrailing))
      .frame(width: 8, height: 8)
      .accessibilityHidden(true)
  }
}

// MARK: - Today tab

extension ShapeStyle where Self == LinearGradient {
  /// Vertical fade of one color to clear, for chart area fills (Today tiles).
  static func fade(_ color: Color, opacity: Double) -> LinearGradient {
    LinearGradient(
      colors: [color.opacity(opacity), color.opacity(0)],
      startPoint: .top,
      endPoint: .bottom)
  }
}

extension View {
  /// Soft orange shadow under the floating Start button (Today, spec §9).
  func todayFabShadow() -> some View {
    self.shadow(color: Theme.accent.opacity(0.45), radius: 14, x: 0, y: 8)
  }
}

// MARK: - Progress overview v3

extension View {
  /// Right-edge soft fade for horizontal shelves (Overview v3): opaque to 82 %, then clear.
  func shelfFadeMask() -> some View {
    mask(
      LinearGradient(
        stops: [.init(color: .black, location: 0.82), .init(color: .clear, location: 1)],
        startPoint: .leading, endPoint: .trailing)
    )
  }
}

/// Diagonal accent hatch (Overview v3 "short" muscle): 135° stripes on a transparent ground.
struct HatchOverlay: View {
  var period: CGFloat = 3.6
  var lineWidth: CGFloat = 1.6

  var body: some View {
    Canvas { context, size in
      var path = Path()
      var x = -size.height
      while x < size.width {
        path.move(to: CGPoint(x: x, y: 0))
        path.addLine(to: CGPoint(x: x + size.height, y: size.height))
        x += period
      }
      context.stroke(path, with: .color(Theme.accent), lineWidth: lineWidth)
    }
    .accessibilityHidden(true)
  }
}

// MARK: - Workout

/// Rest-countdown ring (W2b): ArcRing's open-arc geometry and gradient, but the arc tracks
/// its progress with a 1 s linear step — one tick per second — instead of ArcRing's entrance
/// spring, so the countdown hand moves steadily instead of bouncing on every tick.
struct RestArcRing: View {
  var progress: Double
  var lineWidth: CGFloat
  var colors: [Color]
  var glyph: String? = nil

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private static let start = 130.0
  private static let span = 280.0

  var body: some View {
    GeometryReader { geo in
      let side = min(geo.size.width, geo.size.height)
      let radius = (side - lineWidth) / 2
      let sweep = Self.span * min(1, max(0, progress))
      let cap = CGPoint(
        x: side / 2 + radius * cos(Self.start * .pi / 180),
        y: side / 2 + radius * sin(Self.start * .pi / 180))
      ZStack {
        Circle()
          .inset(by: lineWidth / 2)
          .trim(from: 0, to: Self.span / 360)
          .stroke(colors[0].opacity(0.14), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
          .rotationEffect(.degrees(Self.start))
        if sweep > 0.5 {
          Circle()
            .inset(by: lineWidth / 2)
            .trim(from: 0, to: sweep / 360)
            .stroke(
              AngularGradient(colors: colors, center: .center, startAngle: .degrees(0), endAngle: .degrees(sweep)),
              style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
            .rotationEffect(.degrees(Self.start))
          // The gradient clamps to the bright end before its start angle, so both caps need
          // their own solid color.
          Circle()
            .fill(colors[0])
            .frame(width: lineWidth, height: lineWidth)
            .position(cap)
          Circle()
            .fill(colors[1])
            .frame(width: lineWidth, height: lineWidth)
            .position(
              x: side / 2 + radius * cos((Self.start + sweep) * .pi / 180),
              y: side / 2 + radius * sin((Self.start + sweep) * .pi / 180))
        }
        if let glyph {
          Image(systemName: glyph)
            .font(.system(size: lineWidth * 0.55))
            .foregroundStyle(.white)
            .position(cap)
        }
      }
      .frame(width: side, height: side)
      .position(x: geo.size.width / 2, y: geo.size.height / 2)
    }
    .animation(reduceMotion ? nil : .linear(duration: 1), value: progress)
    .accessibilityHidden(true)
  }
}
