import SwiftUI

struct VolumeRingView: View {
  var sets: Double
  var mev: Int
  var mrv: Int
  var size: CGFloat = 44

  var body: some View {
    ZStack {
      Canvas { context, canvas in
        let center = CGPoint(x: canvas.width / 2, y: canvas.height / 2)
        let radius = (min(canvas.width, canvas.height) - 6) / 2
        let bounds = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
        context.stroke(Path(ellipseIn: bounds), with: .color(Theme.track), lineWidth: 6)
        let denom = max(Double(mrv), 1)
        let fraction = min(sets / denom, 1)
        let color: Color = sets > Double(mrv) ? Theme.negative : (sets >= Double(mev) ? Theme.accent : Theme.ramp[2])
        if fraction > 0 {
          context.stroke(Path { p in
            p.addArc(center: center, radius: radius, startAngle: .degrees(-90),
                     endAngle: .degrees(-90 + 360 * fraction), clockwise: false)
          }, with: .color(color), lineWidth: 6)
        }
        let tick = Angle.degrees(-90 + 360 * Double(mev) / denom).radians
        let dx = cos(tick), dy = sin(tick)
        context.stroke(Path { p in
          p.move(to: CGPoint(x: center.x + (radius - 5) * dx, y: center.y + (radius - 5) * dy))
          p.addLine(to: CGPoint(x: center.x + (radius + 5) * dx, y: center.y + (radius + 5) * dy))
        }, with: .color(Theme.textSecondary), lineWidth: 2)
      }
      Text("\(Int(sets.rounded()))").forge(12, .semibold).monospacedDigit()
    }
    .frame(width: size, height: size)
  }
}

#Preview("Ring") {
  VStack(spacing: 16) {
    HStack(spacing: 16) {
      VolumeRingView(sets: 4, mev: 8, mrv: 20)
      VolumeRingView(sets: 14, mev: 8, mrv: 20)
      VolumeRingView(sets: 22, mev: 8, mrv: 20)
    }
  }
  .padding()
}
