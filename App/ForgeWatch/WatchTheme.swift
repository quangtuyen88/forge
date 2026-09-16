import SwiftUI
import CoreText

enum WatchTheme {
  static let accent = Color(red: 0x6E / 255, green: 0x93 / 255, blue: 0xF0 / 255)
  static let mint = Color(red: 0x34 / 255, green: 0xD3 / 255, blue: 0x99 / 255)
  static let amber = Color(red: 0xFF / 255, green: 0xD6 / 255, blue: 0x0A / 255)
  static let danger = Color(red: 0xFF / 255, green: 0x45 / 255, blue: 0x3A / 255)
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
