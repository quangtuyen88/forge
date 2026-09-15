import SwiftUI
import ForgeCore

struct MuscleMapView: View {
  var intensity: [Muscle: Double]
  var selected: Set<Muscle> = []
  var onTap: ((Muscle) -> Void)? = nil

  private static func muscleRegions(cx: CGFloat, back: Bool) -> [(muscle: Muscle, rects: [CGRect], ellipse: Bool)] {
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

  var body: some View {
    VStack(spacing: 4) {
      mapCanvas
      HStack {
        Text("Front").forgeCaption().frame(maxWidth: .infinity)
        Text("Back").forgeCaption().frame(maxWidth: .infinity)
      }
    }
  }

  @ViewBuilder private var mapCanvas: some View {
    GeometryReader { geo in
      let canvas = Canvas { context, size in
        let s = min(size.width / 200, size.height / 160)
        context.translateBy(x: (size.width - 200 * s) / 2, y: (size.height - 160 * s) / 2)
        context.scaleBy(x: s, y: s)
        for (cx, back) in [(CGFloat(50), false), (CGFloat(150), true)] {
          figure(cx: cx, back: back, context: &context)
        }
      }
      .aspectRatio(200.0 / 160.0, contentMode: .fit)
      if let onTap {
        canvas
          .contentShape(Rectangle())
          .onTapGesture(coordinateSpace: .local) { location in
            let p = CGPoint(x: location.x / geo.size.width * 200, y: location.y / geo.size.height * 160)
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

  private func figure(cx: CGFloat, back: Bool, context: inout GraphicsContext) {
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
      let color = Theme.rampColor(intensity[region.muscle] ?? 0)
      let isSore = selected.contains(region.muscle)
      for r in region.rects {
        let path = region.ellipse ? Path(ellipseIn: r) : capsule(r)
        context.fill(path, with: .color(color))
        if isSore {
          context.stroke(path, with: .color(Theme.accent), lineWidth: 1.5)
        }
      }
    }
  }

  private func mirrorRects(_ r: CGRect, _ cx: CGFloat) -> [CGRect] {
    [r, CGRect(x: 2 * cx - r.maxX, y: r.minY, width: r.width, height: r.height)]
  }
}

#Preview {
  MuscleMapView(intensity: [
    .chest: 1.0, .frontDelts: 0.6, .sideDelts: 0.5, .triceps: 0.7, .biceps: 0.4,
    .abs: 0.3, .quads: 0.55, .back: 0.2, .rearDelts: 0.3, .calves: 0.25,
  ])
  .padding()
}
