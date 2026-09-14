import SwiftUI
import ForgeCore

struct MuscleMapView: View {
  var intensity: [Muscle: Double]

  var body: some View {
    VStack(spacing: 4) {
      Canvas { context, size in
        let s = min(size.width / 200, size.height / 160)
        context.translateBy(x: (size.width - 200 * s) / 2, y: (size.height - 160 * s) / 2)
        context.scaleBy(x: s, y: s)
        for (cx, back) in [(CGFloat(50), false), (CGFloat(150), true)] {
          figure(cx: cx, back: back, context: &context)
        }
      }
      .aspectRatio(200.0 / 160.0, contentMode: .fit)
      HStack {
        Text("Front").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
        Text("Back").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity)
      }
    }
  }

  private func figure(cx: CGFloat, back: Bool, context: inout GraphicsContext) {
    let base = Color(.tertiarySystemFill)
    func mirror(_ r: CGRect) -> [CGRect] {
      [r, CGRect(x: 2 * cx - r.maxX, y: r.minY, width: r.width, height: r.height)]
    }
    func capsule(_ r: CGRect) -> Path {
      let c = min(r.width, r.height) / 2
      return Path(roundedRect: r, cornerSize: CGSize(width: c, height: c), style: .continuous)
    }
    func regions(_ muscle: Muscle, _ rects: [CGRect], ellipse: Bool = false) {
      let i = intensity[muscle] ?? 0
      let color = i > 0 ? Theme.accent.opacity(0.15 + 0.85 * i) : Color(.systemFill)
      for r in rects {
        context.fill(ellipse ? Path(ellipseIn: r) : capsule(r), with: .color(color))
      }
    }

    // Base figure
    context.fill(Path(ellipseIn: CGRect(x: cx - 8, y: 7, width: 16, height: 17)), with: .color(base)) // head
    for r in [
      CGRect(x: cx - 3.5, y: 23, width: 7, height: 6),   // neck
      CGRect(x: cx - 19, y: 28, width: 38, height: 19),  // upper torso
      CGRect(x: cx - 14, y: 45, width: 28, height: 19),  // lower torso (taper)
      CGRect(x: cx - 13, y: 62, width: 26, height: 11),  // pelvis
    ] + mirror(CGRect(x: cx - 28, y: 30, width: 9, height: 22))    // upper arms
      + mirror(CGRect(x: cx - 27.5, y: 51, width: 8, height: 22))  // forearms
      + mirror(CGRect(x: cx - 13, y: 70, width: 11, height: 36))   // thighs
      + mirror(CGRect(x: cx - 12, y: 104, width: 9, height: 36)) { // shins
      context.fill(capsule(r), with: .color(base))
    }

    // Muscle regions
    if back {
      regions(.back, [
        CGRect(x: cx - 14, y: 29, width: 28, height: 14),
        CGRect(x: cx - 17, y: 42, width: 34, height: 17),
      ])
      regions(.rearDelts, mirror(CGRect(x: cx - 23, y: 27, width: 11, height: 11)), ellipse: true)
      regions(.triceps, mirror(CGRect(x: cx - 28, y: 34, width: 8, height: 14)))
      regions(.glutes, [CGRect(x: cx - 12, y: 63, width: 10, height: 10), CGRect(x: cx + 2, y: 63, width: 10, height: 10)])
      regions(.hamstrings, mirror(CGRect(x: cx - 13, y: 85, width: 11, height: 20)))
      regions(.calves, mirror(CGRect(x: cx - 12, y: 105, width: 9, height: 25)))
    } else {
      regions(.chest, [CGRect(x: cx - 11, y: 31, width: 10, height: 13), CGRect(x: cx + 1, y: 31, width: 10, height: 13)])
      regions(.frontDelts, mirror(CGRect(x: cx - 22, y: 27, width: 11, height: 11)), ellipse: true)
      regions(.biceps, mirror(CGRect(x: cx - 28, y: 34, width: 8, height: 14)))
      regions(.forearms, mirror(CGRect(x: cx - 27, y: 53, width: 8, height: 15)))
      regions(.abs, (0..<3).map { CGRect(x: cx - 8, y: 48 + CGFloat($0) * 5.5, width: 16, height: 4) })
      regions(.quads, mirror(CGRect(x: cx - 13, y: 72, width: 11, height: 27)))
    }
    regions(.sideDelts, mirror(CGRect(x: cx - 26, y: 29, width: 8, height: 8)), ellipse: true)
  }
}

#Preview {
  MuscleMapView(intensity: [
    .chest: 1.0, .frontDelts: 0.6, .sideDelts: 0.5, .triceps: 0.7, .biceps: 0.4,
    .abs: 0.3, .quads: 0.55, .back: 0.2, .rearDelts: 0.3, .calves: 0.25,
  ])
  .padding()
}
