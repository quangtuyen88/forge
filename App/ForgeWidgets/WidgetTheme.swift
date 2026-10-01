import SwiftUI
import UIKit

/// Widget and Live Activity colors. Fills and rings keep the brand orange; text and the container adapt to light and dark.
enum WidgetTheme {
  static let accent = Color(red: 0xF5 / 255, green: 0x62 / 255, blue: 0x1C / 255)
  static let accentText = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0xF5 / 255, green: 0x62 / 255, blue: 0x1C / 255, alpha: 1)
      : UIColor(red: 0xC2 / 255, green: 0x46 / 255, blue: 0x0C / 255, alpha: 1)
  })
  static let done = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0x30 / 255, green: 0xD1 / 255, blue: 0x58 / 255, alpha: 1)
      : UIColor(red: 0x15 / 255, green: 0x70 / 255, blue: 0x3A / 255, alpha: 1)
  })
  static let background = Color(uiColor: UIColor { traits in
    traits.userInterfaceStyle == .dark
      ? UIColor(red: 0x1C / 255, green: 0x1C / 255, blue: 0x1E / 255, alpha: 1)
      : UIColor.systemBackground
  })
}
