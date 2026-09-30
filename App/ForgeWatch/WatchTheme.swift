import SwiftUI
import CoreText

enum WatchTheme {
  static let accent = Color(red: 0xFF / 255, green: 0x7A / 255, blue: 0x33 / 255)
  static let sets = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
  static let time = Color(red: 0x5A / 255, green: 0xA9 / 255, blue: 0xFF / 255)
  static let effort = Color(red: 0xFF / 255, green: 0x6B / 255, blue: 0x4A / 255)
  static let danger = Color(red: 0xFF / 255, green: 0x3B / 255, blue: 0x30 / 255)
  static let fill = Color.white.opacity(0.14)
  static func font(_ size: CGFloat, _ weight: Font.Weight = .regular, relativeTo style: Font.TextStyle = .body) -> Font {
    let name: String
    switch weight {
    case .bold: name = "InterTight-Bold"
    case .semibold: name = "InterTight-SemiBold"
    default: name = "InterTight-Regular"
    }
    return .custom(name, size: size, relativeTo: style)
  }
  static func registerFonts() {
    for name in ["InterTight-Regular", "InterTight-SemiBold", "InterTight-Bold"] {
      guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }
}
