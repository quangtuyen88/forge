import SwiftUI

struct SessionRow: View {
  let title: String
  let value: String
  var unit: String? = nil
  let trailing: String
  var symbol: String = "dumbbell.fill"

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: symbol)
        .font(.system(size: 14, weight: .semibold))
        .foregroundColor(Theme.accent)
        .frame(width: 40, height: 40)
        .background(Circle().fill(Theme.accent.opacity(0.12)))
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forgeLabel()
        MetricValue(value: value, unit: unit, size: 22, color: Theme.accent)
      }
      Spacer()
      Text(trailing).forgeCaption()
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

struct MonthTotalsRow: View {
  let sessions: Int
  let minutes: Int
  let sets: Int
  let tonnage: String
  var unit: String = "kg"

  var body: some View {
    HStack(spacing: 8) {
      column("\(sessions)", nil, "sessions")
      column("\(minutes)", "min", "time")
      column("\(sets)", nil, "sets")
      column(tonnage, unit, "tonnage")
    }
    .innerSurface()
  }

  private func column(_ value: String, _ unit: String?, _ label: String) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      MetricValue(value: value, unit: unit, size: 20)
      Text(label).forgeCaption()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct SessionHeader: View {
  let symbol: String
  let title: String
  let subtitle: String
  var caption: String? = nil

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: symbol)
        .font(.system(size: 26, weight: .semibold))
        .foregroundColor(Theme.accent)
        .frame(width: 64, height: 64)
        .background(Circle().fill(Theme.accent.opacity(0.12)))
      VStack(alignment: .leading, spacing: 3) {
        Text(title).forgeTitle()
        Text(subtitle).forgeLabel()
        if let caption {
          Text(caption).forgeCaption()
        }
      }
      Spacer()
    }
  }
}
