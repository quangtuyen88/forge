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
        .foregroundStyle(Theme.accent)
        .frame(width: 40, height: 40)
        .background(Circle().fill(Theme.accentTint))
      VStack(alignment: .leading, spacing: 2) {
        Text(title).forgeLabel()
        MetricValue(value: value, unit: unit, size: 22, color: Theme.metricLoad)
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
      column("\(sessions)", nil, sessions == 1 ? "session" : "sessions", Theme.metricSets)
      column("\(minutes)", "min", "time", Theme.metricTime)
      column("\(sets)", nil, sets == 1 ? "set" : "sets", Theme.metricSets)
      column(tonnage, unit, "tonnage", Theme.metricLoad)
    }
    .innerSurface()
  }

  private func column(_ value: String, _ unit: String?, _ label: LocalizedStringKey, _ color: Color)
    -> some View
  {
    VStack(alignment: .leading, spacing: 3) {
      MetricValue(value: value, unit: unit, size: 20, color: color)
      Text(label, bundle: L10n.bundle).forgeCaption()
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
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
        .foregroundStyle(Theme.accent)
        .frame(width: 64, height: 64)
        .background(Circle().fill(Theme.accentTint))
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
