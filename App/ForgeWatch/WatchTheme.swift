import SwiftUI
import CoreText

enum WatchTheme {
  static let accent = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
  static let sets = Color(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255)
  static let time = Color(red: 0x0A / 255, green: 0x84 / 255, blue: 0xFF / 255)
  static let effort = Color(red: 0xFF / 255, green: 0x9F / 255, blue: 0x0A / 255)
  static let danger = Color(red: 0xFF / 255, green: 0x3B / 255, blue: 0x30 / 255)
  static let fill = Color.white.opacity(0.14)
  static func font(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font {
    let name: String
    switch weight {
    case .bold: name = "InterTight-Bold"
    case .semibold: name = "InterTight-SemiBold"
    default: name = "InterTight-Regular"
    }
    return .custom(name, size: size)
  }
  static func registerFonts() {
    for name in ["InterTight-Regular", "InterTight-SemiBold", "InterTight-Bold"] {
      guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
      CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }
  }
}
