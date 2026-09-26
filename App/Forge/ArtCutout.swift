import UIKit

/// Exercise art with its flat white background made transparent, for dark surfaces. Cached per asset.
enum ArtCutout {
  nonisolated(unsafe) private static let cache = NSCache<NSString, UIImage>()

  static func image(named name: String) async -> UIImage? {
    if let cached = cache.object(forKey: name as NSString) { return cached }
    guard let rendered = await Task.detached(priority: .userInitiated) { render(name) }.value else {
      return nil
    }
    cache.setObject(rendered, forKey: name as NSString)
    return rendered
  }

  /// Makes the art's flat white background transparent; returns nil when the asset is missing.
  private nonisolated static func render(_ name: String) -> UIImage? {
    guard let source = UIImage(named: name)?.cgImage else { return nil }
    let side = 480
    let count = side * side
    var pixels = [UInt8](repeating: 0, count: count * 4)
    let drew = pixels.withUnsafeMutableBytes { raw -> Bool in
      guard let context = CGContext(
        data: raw.baseAddress,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: side * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { return false }
      let scale = CGFloat(side) / CGFloat(max(source.width, source.height))
      let width = CGFloat(source.width) * scale
      let height = CGFloat(source.height) * scale
      context.draw(
        source,
        in: CGRect(
          x: (CGFloat(side) - width) / 2, y: (CGFloat(side) - height) / 2,
          width: width, height: height))
      return true
    }
    guard drew else { return nil }

    // Near-white test: min(r, g, b) >= 238; undrawn (transparent) pixels count as background.
    var nearWhite = [UInt8](repeating: 0, count: count)
    for i in 0..<count {
      let o = i * 4
      if min(pixels[o], pixels[o + 1], pixels[o + 2]) >= 238 || pixels[o + 3] == 0 {
        nearWhite[i] = 1
      }
    }

    // Flood fill from near-white border pixels: those are background.
    var background = [UInt8](repeating: 0, count: count)
    var stack = [Int32]()
    for x in 0..<side {
      stack.append(Int32(x))
      stack.append(Int32((side - 1) * side + x))
    }
    for y in 0..<side {
      stack.append(Int32(y * side))
      stack.append(Int32(y * side + side - 1))
    }
    while let index = stack.popLast() {
      let i = Int(index)
      guard nearWhite[i] == 1, background[i] == 0 else { continue }
      background[i] = 1
      let x = i % side
      let y = i / side
      if x > 0 { stack.append(Int32(i - 1)) }
      if x < side - 1 { stack.append(Int32(i + 1)) }
      if y > 0 { stack.append(Int32(i - side)) }
      if y < side - 1 { stack.append(Int32(i + side)) }
    }

    // Remaining near-white regions larger than the gap limit are background too.
    let gapLimit = 150 * count / (600 * 600)
    var visited = [UInt8](repeating: 0, count: count)
    var region = [Int32]()
    for start in 0..<count {
      guard nearWhite[start] == 1, background[start] == 0, visited[start] == 0 else { continue }
      visited[start] = 1
      stack.append(Int32(start))
      region.removeAll(keepingCapacity: true)
      while let index = stack.popLast() {
        let i = Int(index)
        region.append(Int32(i))
        let x = i % side
        let y = i / side
        if x > 0, nearWhite[i - 1] == 1, visited[i - 1] == 0 {
          visited[i - 1] = 1
          stack.append(Int32(i - 1))
        }
        if x < side - 1, nearWhite[i + 1] == 1, visited[i + 1] == 0 {
          visited[i + 1] = 1
          stack.append(Int32(i + 1))
        }
        if y > 0, nearWhite[i - side] == 1, visited[i - side] == 0 {
          visited[i - side] = 1
          stack.append(Int32(i - side))
        }
        if y < side - 1, nearWhite[i + side] == 1, visited[i + side] == 0 {
          visited[i + side] = 1
          stack.append(Int32(i + side))
        }
      }
      if region.count > gapLimit {
        for index in region { background[Int(index)] = 1 }
      }
    }

    // Erode the foreground by one pixel to drop the light JPEG fringe.
    var foreground = [UInt8](repeating: 0, count: count)
    for y in 1..<(side - 1) {
      for x in 1..<(side - 1) {
        let i = y * side + x
        if background[i] == 0, background[i - 1] == 0, background[i + 1] == 0,
          background[i - side] == 0, background[i + side] == 0
        {
          foreground[i] = 1
        }
      }
    }

    // Premultiplied RGBA: soft 150 edge on the foreground boundary, 255 inside, 0 elsewhere.
    for i in 0..<count {
      let o = i * 4
      guard foreground[i] == 1 else {
        pixels[o] = 0
        pixels[o + 1] = 0
        pixels[o + 2] = 0
        pixels[o + 3] = 0
        continue
      }
      let alpha: Int =
        (foreground[i - 1] == 0 || foreground[i + 1] == 0 || foreground[i - side] == 0
        || foreground[i + side] == 0) ? 150 : 255
      pixels[o] = UInt8(Int(pixels[o]) * alpha / 255)
      pixels[o + 1] = UInt8(Int(pixels[o + 1]) * alpha / 255)
      pixels[o + 2] = UInt8(Int(pixels[o + 2]) * alpha / 255)
      pixels[o + 3] = UInt8(alpha)
    }

    let cutout = pixels.withUnsafeMutableBytes { raw -> CGImage? in
      guard let context = CGContext(
        data: raw.baseAddress,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: side * 4,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      ) else { return nil }
      return context.makeImage()
    }
    return cutout.map { UIImage(cgImage: $0) }
  }
}
