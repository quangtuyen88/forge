import SwiftUI
import CoreText

enum WatchTheme {
  static let accent = Color(red: 0x38 / 255, green: 0x66 / 255, blue: 0xD6 / 255)
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
