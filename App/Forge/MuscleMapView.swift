import SwiftUI
import UIKit
import ForgeCore

enum MuscleSide {
  case front, back

  var muscles: [Muscle] {
    self == .front
      ? [.chest, .frontDelts, .sideDelts, .biceps, .forearms, .abs, .quads]
      : [.back, .rearDelts, .sideDelts, .triceps, .glutes, .hamstrings, .calves]
  }

  var regions: [Muscle: CGRect] { self == .front ? MuscleFigureRegions.front : MuscleFigureRegions.back }
  var assetName: String { self == .front ? "figure-front" : "figure-back" }
}

/// Samples the muscle mask alpha exactly, so taps land on painted pixels, not bounding boxes.
enum MaskSampler {
  private static var cache: [String: (width: Int, height: Int, alpha: [UInt8])] = [:]
  private static let lock = NSLock()

  static func hit(_ side: MuscleSide, _ muscle: Muscle, _ p: CGPoint) -> Bool {
    let name = "\(side.assetName)-\(muscle)"
    guard let mask = mask(for: name) else { return false }
    let x = min(max(Int(p.x * CGFloat(mask.width)), 0), mask.width - 1)
    let y = min(max(Int(p.y * CGFloat(mask.height)), 0), mask.height - 1)
    return mask.alpha[y * mask.width + x] > 96
  }

  private static func mask(for name: String) -> (width: Int, height: Int, alpha: [UInt8])? {
    lock.lock()
    defer { lock.unlock() }
    if let cached = cache[name] { return cached }
    guard let cg = UIImage(named: name)?.cgImage else { return nil }
    let width = cg.width, height = cg.height
    var alpha = [UInt8](repeating: 0, count: width * height)
    if let ctx = CGContext(
      data: &alpha, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width,
      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.alphaOnly.rawValue)
    {
      ctx.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
    }
    let entry = (width, height, alpha)
    cache[name] = entry
    return entry
  }
}

/// One side of the illustrated figure: the gray écorché base with tinted muscle overlays.
struct MuscleFigure: View {
  let side: MuscleSide
  let tint: (Muscle) -> Color?
  var onTap: ((Muscle) -> Void)? = nil

  var body: some View {
    Group {
      if let onTap {
        GeometryReader { geo in
          figure
            .contentShape(Rectangle())
            .onTapGesture(coordinateSpace: .local) { location in
              let p = CGPoint(x: location.x / geo.size.width, y: location.y / geo.size.height)
              if let muscle = hitTest(p) { onTap(muscle) }
            }
        }
      } else {
        figure
      }
    }
    .aspectRatio(MuscleFigureRegions.aspect, contentMode: .fit)
    .accessibilityHidden(true)
  }

  private var figure: some View {
    ZStack {
      Image(side.assetName).resizable().scaledToFit()
      ForEach(side.muscles, id: \.self) { muscle in
        if let c = tint(muscle) {
          Image("\(side.assetName)-\(muscle)")
            .renderingMode(.template)
            .resizable()
            .scaledToFit()
            .foregroundStyle(c)
        }
      }
    }
  }

  /// Exact mask alpha first, then the nearest region rect within 0.04 (same nearest-rect rule as before).
  private func hitTest(_ p: CGPoint) -> Muscle? {
    for muscle in side.muscles where MaskSampler.hit(side, muscle, p) {
      return muscle
    }
    var best: (muscle: Muscle, distance: CGFloat)?
    for (muscle, rect) in side.regions {
      let dx = max(rect.minX - p.x, 0, p.x - rect.maxX)
      let dy = max(rect.minY - p.y, 0, p.y - rect.maxY)
      let d = (dx * dx + dy * dy).squareRoot()
      if d <= 0.04, d < (best?.distance ?? .infinity) { best = (muscle, d) }
    }
    return best?.muscle
  }
}

struct MuscleMapView: View {
  var intensity: [Muscle: Double]
  var selected: Set<Muscle> = []
  var onTap: ((Muscle) -> Void)? = nil

  var body: some View {
    HStack(alignment: .top, spacing: 16) {
      ForEach([MuscleSide.front, .back], id: \.self) { side in
        VStack(spacing: 6) {
          MuscleFigure(side: side, tint: tint(for:), onTap: onTap)
          Text(side == .front ? "Front" : "Back").forgeCaption()
        }
      }
    }
    .frame(maxWidth: .infinity)
  }

  private func tint(for muscle: Muscle) -> Color? {
    if selected.contains(muscle) { return Theme.accent }
    if let v = intensity[muscle], v > 0 { return Theme.rampColor(v) }
    return nil
  }
}

/// One body figure, front or back, with the exercise's primary muscle in the accent and
/// synergists muted. A crop of the illustrated figure around the primary muscle.
struct MuscleThumb: View {
  let exercise: Exercise
  var size: CGFloat = 40

  private var side: MuscleSide {
    switch exercise.primary {
    case .back, .rearDelts, .triceps, .glutes, .hamstrings, .calves: return .back
    default: return .front
    }
  }

  private func tint(for muscle: Muscle) -> Color? {
    if muscle == exercise.primary { return Theme.accent }
    if exercise.synergists.contains(muscle) { return Theme.accent.opacity(0.35) }
    return nil
  }

  var body: some View {
    let r = side.regions[exercise.primary] ?? CGRect(x: 0.5, y: 0.4, width: 0, height: 0)
    let h = size * 2.4
    let w = h * MuscleFigureRegions.aspect
    MuscleFigure(side: side, tint: tint(for:))
      .frame(width: w, height: h)
      .offset(x: (0.5 - r.midX) * w, y: (0.5 - r.midY) * h)
      .frame(width: size, height: size)
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
      .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
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
