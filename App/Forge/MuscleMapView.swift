import SwiftUI
import UIKit
import ForgeCore

struct MuscleMapView: View {
  var intensity: [Muscle: Double]
  var selected: Set<Muscle> = []
  var onTap: ((Muscle) -> Void)? = nil

  fileprivate static func muscleRegions(cx: CGFloat, back: Bool) -> [(muscle: Muscle, rects: [CGRect], ellipse: Bool)] {
    func mirror(_ r: CGRect) -> [CGRect] {
      [r, CGRect(x: 2 * cx - r.maxX, y: r.minY, width: r.width, height: r.height)]
    }
    var list: [(muscle: Muscle, rects: [CGRect], ellipse: Bool)] = []
    if back {
      list.append((.back, [
        CGRect(x: cx - 14, y: 29, width: 28, height: 14),
        CGRect(x: cx - 17, y: 42, width: 34, height: 17),
      ], ellipse: false))
      list.append((.rearDelts, mirror(CGRect(x: cx - 23, y: 27, width: 11, height: 11)), ellipse: true))
      list.append((.triceps, mirror(CGRect(x: cx - 28, y: 34, width: 8, height: 14)), ellipse: false))
      list.append((.glutes, [CGRect(x: cx - 12, y: 63, width: 10, height: 10), CGRect(x: cx + 2, y: 63, width: 10, height: 10)], ellipse: false))
      list.append((.hamstrings, mirror(CGRect(x: cx - 13, y: 85, width: 11, height: 20)), ellipse: false))
      list.append((.calves, mirror(CGRect(x: cx - 12, y: 105, width: 9, height: 25)), ellipse: false))
    } else {
      list.append((.chest, [CGRect(x: cx - 11, y: 31, width: 10, height: 13), CGRect(x: cx + 1, y: 31, width: 10, height: 13)], ellipse: false))
      list.append((.frontDelts, mirror(CGRect(x: cx - 22, y: 27, width: 11, height: 11)), ellipse: true))
      list.append((.biceps, mirror(CGRect(x: cx - 28, y: 34, width: 8, height: 14)), ellipse: false))
      list.append((.forearms, mirror(CGRect(x: cx - 27.5, y: 53, width: 8, height: 15)), ellipse: false))
      list.append((.abs, (0..<3).map { CGRect(x: cx - 8, y: 48 + CGFloat($0) * 5.5, width: 16, height: 4) }, ellipse: false))
      list.append((.quads, mirror(CGRect(x: cx - 13, y: 72, width: 11, height: 27)), ellipse: false))
    }
    list.append((.sideDelts, mirror(CGRect(x: cx - 26, y: 29, width: 8, height: 8)), ellipse: true))
    return list
  }

  /// Draw-order region list across both figures, in the 200×160 space, for tap hit-testing.
  private static var hitRegions: [(muscle: Muscle, rect: CGRect)] {
    [(CGFloat(50), false), (CGFloat(150), true)].flatMap { cx, back in
      muscleRegions(cx: cx, back: back).flatMap { region in region.rects.map { (region.muscle, $0) } }
    }
  }

  /// Map space: two 100-wide figures plus a caption row under them. The reader keeps this aspect,
  /// so a caller's height or width sizes the whole map and the captions stay under their figures.
  private static let mapSize = CGSize(width: 200, height: 176)

  var body: some View {
    mapCanvas.aspectRatio(Self.mapSize.width / Self.mapSize.height, contentMode: .fit)
  }

  @ViewBuilder private var mapCanvas: some View {
    GeometryReader { geo in
      let canvas = Canvas { context, size in
        let s = min(size.width / Self.mapSize.width, size.height / Self.mapSize.height)
        let origin = CGPoint(x: (size.width - Self.mapSize.width * s) / 2, y: (size.height - Self.mapSize.height * s) / 2)
        for (cx, label) in [(CGFloat(50), Text("Front")), (CGFloat(150), Text("Back"))] {
          context.draw(
            label.forge(12, .medium).foregroundStyle(Theme.textTertiary),
            at: CGPoint(x: origin.x + cx * s, y: origin.y + 166 * s))
        }
        context.translateBy(x: origin.x, y: origin.y)
        context.scaleBy(x: s, y: s)
        for (cx, back) in [(CGFloat(50), false), (CGFloat(150), true)] {
          Self.figure(
            cx: cx, back: back, context: &context,
            color: { Theme.rampColor(intensity[$0] ?? 0) }, stroked: { selected.contains($0) })
        }
      }
      if let onTap {
        canvas
          .contentShape(Rectangle())
          .onTapGesture(coordinateSpace: .local) { location in
            let p = CGPoint(
              x: location.x / geo.size.width * Self.mapSize.width,
              y: location.y / geo.size.height * Self.mapSize.height)
            var best: (muscle: Muscle, distance: CGFloat)?
            for (muscle, rect) in Self.hitRegions {
              let dx = max(rect.minX - p.x, 0, p.x - rect.maxX)
              let dy = max(rect.minY - p.y, 0, p.y - rect.maxY)
              let d = (dx * dx + dy * dy).squareRoot()
              if d <= 12, d < (best?.distance ?? .infinity) { best = (muscle, d) }
            }
            if let best { onTap(best.muscle) }
          }
      } else {
        canvas
      }
    }
  }

  fileprivate static func figure(
    cx: CGFloat, back: Bool, context: inout GraphicsContext,
    color: (Muscle) -> Color, stroked: (Muscle) -> Bool
  ) {
    let base = Theme.track
    func capsule(_ r: CGRect) -> Path {
      let c = min(r.width, r.height) / 2
      return Path(roundedRect: r, cornerSize: CGSize(width: c, height: c), style: .continuous)
    }

    // Base figure
    context.fill(Path(ellipseIn: CGRect(x: cx - 8, y: 7, width: 16, height: 17)), with: .color(base)) // head
    for r in [
      CGRect(x: cx - 3.5, y: 23, width: 7, height: 6),   // neck
      CGRect(x: cx - 19, y: 28, width: 38, height: 19),  // upper torso
      CGRect(x: cx - 14, y: 45, width: 28, height: 19),  // lower torso (taper)
      CGRect(x: cx - 13, y: 62, width: 26, height: 11),  // pelvis
    ] + mirrorRects(CGRect(x: cx - 28, y: 30, width: 9, height: 22), cx)    // upper arms
      + mirrorRects(CGRect(x: cx - 27.5, y: 51, width: 8, height: 22), cx)  // forearms
      + mirrorRects(CGRect(x: cx - 13, y: 70, width: 11, height: 36), cx)   // thighs
      + mirrorRects(CGRect(x: cx - 12, y: 104, width: 9, height: 36), cx) { // shins
      context.fill(capsule(r), with: .color(base))
    }

    // Muscle regions
    for region in Self.muscleRegions(cx: cx, back: back) {
      let color = color(region.muscle)
      let isSore = stroked(region.muscle)
      for r in region.rects {
        let path = region.ellipse ? Path(ellipseIn: r) : capsule(r)
        context.fill(path, with: .color(color))
        if isSore {
          context.stroke(path, with: .color(Theme.accent), lineWidth: 1.5)
        }
      }
    }
  }

  private static func mirrorRects(_ r: CGRect, _ cx: CGFloat) -> [CGRect] {
    [r, CGRect(x: 2 * cx - r.maxX, y: r.minY, width: r.width, height: r.height)]
  }
}

/// One body figure, front or back, with the exercise's primary muscle in the accent and
/// synergists muted. Replaces an illustration where the lifter picks among unfamiliar names.
struct MuscleThumb: View {
  let exercise: Exercise
  var size: CGFloat = 40

  private var back: Bool {
    switch exercise.primary {
    case .back, .rearDelts, .triceps, .glutes, .hamstrings, .calves: return true
    default: return false
    }
  }

  private func color(for muscle: Muscle) -> Color {
    if muscle == exercise.primary { return Theme.accent }
    if exercise.synergists.contains(muscle) { return Theme.accent.opacity(0.35) }
    return Theme.track
  }

  /// Vertical center of the primary muscle in figure space, so the crop shows the part that matters.
  private var focusY: CGFloat {
    let rects = MuscleMapView.muscleRegions(cx: 50, back: back)
      .first { $0.muscle == exercise.primary }?.rects ?? []
    guard let first = rects.first else { return 73 }
    let union = rects.dropFirst().reduce(first) { $0.union($1) }
    return union.midY
  }

  var body: some View {
    Canvas { context, _ in
      // Fill the width with the figure and crop vertically around the primary muscle, Lyfta style.
      let s = (size - 8) / 56
      let half = size / (2 * s)
      let y = min(max(focusY, 7 + half), 140 - half)
      context.translateBy(x: size / 2 - 50 * s, y: size / 2 - y * s)
      context.scaleBy(x: s, y: s)
      MuscleMapView.figure(cx: 50, back: back, context: &context, color: color(for:), stroked: { _ in false })
    }
    .frame(width: size, height: size)
    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).strokeBorder(Theme.imageOutline, lineWidth: 1))
    .accessibilityHidden(true)
  }
}

/// The illustration when the catalog has it, otherwise the data-driven muscle figure.
struct ExerciseArt: View {
  let exercise: Exercise
  var size: CGFloat = 40

  private var hasArt: Bool { UIImage(named: "ex-\(exercise.id)") != nil }

  var body: some View {
    if hasArt {
      Image("ex-\(exercise.id)")
        .resizable()
        .scaledToFill()
        // The art has generous margins; zooming in keeps the figure legible at 40 pt.
        .scaleEffect(size < 64 ? 1.3 : 1)
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).strokeBorder(Theme.imageOutline, lineWidth: 1))
        .accessibilityHidden(true)
    } else {
      MuscleThumb(exercise: exercise, size: size)
    }
  }
}

#Preview {
  HStack(spacing: 16) {
    MuscleThumb(exercise: ExerciseDB.everything.first { $0.primary == .chest }!)
    MuscleThumb(exercise: ExerciseDB.everything.first { $0.primary == .back }!)
    MuscleThumb(exercise: ExerciseDB.everything.first { $0.primary == .quads }!)
    MuscleThumb(exercise: ExerciseDB.everything.first { $0.primary == .chest }!, size: 56)
    MuscleThumb(exercise: ExerciseDB.everything.first { $0.primary == .back }!, size: 56)
    MuscleThumb(exercise: ExerciseDB.everything.first { $0.primary == .quads }!, size: 56)
  }
  .padding()
}

#Preview {
  MuscleMapView(intensity: [
    .chest: 1.0, .frontDelts: 0.6, .sideDelts: 0.5, .triceps: 0.7, .biceps: 0.4,
    .abs: 0.3, .quads: 0.55, .back: 0.2, .rearDelts: 0.3, .calves: 0.25,
  ])
  .padding()
}
