import SwiftUI

struct MetricItem: Identifiable {
  let id: String
  let label: String
  let value: String
  var unit: String? = nil
  var color: Color = Theme.text

  init(_ label: String, _ value: String, unit: String? = nil, color: Color = Theme.text) {
    self.id = label
    self.label = label
    self.value = value
    self.unit = unit
    self.color = color
  }
}

struct MetricGrid: View {
  let items: [MetricItem]

  var body: some View {
    let rows = stride(from: 0, to: items.count, by: 2).map { Array(items[$0..<min($0 + 2, items.count)]) }
    VStack(spacing: 0) {
      ForEach(Array(rows.enumerated()), id: \.offset) { row in
        if row.offset > 0 {
          Rectangle().fill(Theme.ring).frame(height: 1)
        }
        HStack(spacing: 12) {
          ForEach(row.element) { item in
            VStack(alignment: .leading, spacing: 4) {
              Text(item.label).forgeLabel()
              MetricValue(value: item.value, unit: item.unit, size: 24, color: item.color)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        .padding(.vertical, 10)
      }
    }
  }
}
