import SwiftUI

struct ChartCallout: View {
  let value: String
  let caption: String

  var body: some View {
    VStack(spacing: 1) {
      Text(value).forge(15, .bold).monospacedDigit()
      Text(caption).forge(11, .medium)
    }
    .foregroundColor(.white)
    .padding(.horizontal, 10)
    .padding(.vertical, 6)
    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Theme.accent))
  }
}
