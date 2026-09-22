import SwiftUI

struct MetricItem: Identifiable {
  let id: String
  let label: String
  let value: String
  var unit: String? = nil
  /// The scope or coverage the number actually has — "1 of 3 sets", "not recorded". A metric
  /// that covers less than it appears to has to say so next to the value, not in a footnote.
  var caption: String? = nil
  var color: Color = Theme.text

  init(
    _ label: String, _ value: String, unit: String? = nil, caption: String? = nil,
    color: Color = Theme.text
  ) {
    self.id = label
    self.label = label
    self.value = value
    self.unit = unit
    self.caption = caption
    self.color = color
  }
}

struct MetricGrid: View {
  let items: [MetricItem]

  /// A row carries the identity of its first metric. Keying on the index instead re-identifies
  /// every row below whenever a metric is added, removed or reordered at runtime.
  private struct Row: Identifiable {
    let id: String
    let items: [MetricItem]
    let isFirst: Bool
  }

  private var rows: [Row] {
    stride(from: 0, to: items.count, by: 2).map { start in
      let slice = Array(items[start..<min(start + 2, items.count)])
      return Row(id: slice.first?.id ?? "row-\(start)", items: slice, isFirst: start == 0)
    }
  }

  var body: some View {
    VStack(spacing: 0) {
      ForEach(rows) { row in
        // Zero-height rather than absent: a constant number of views per element keeps the
        // row's structural identity stable when the first row changes.
        Rectangle().fill(Theme.ring).frame(height: row.isFirst ? 0 : 1)
        HStack(spacing: 12) {
          ForEach(row.items) { item in
            VStack(alignment: .leading, spacing: 4) {
              Text(item.label).forgeLabel()
              MetricValue(value: item.value, unit: item.unit, size: 24, color: item.color)
              if let caption = item.caption {
                Text(caption).forgeCaption()
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
          }
        }
        .padding(.vertical, 10)
      }
    }
  }
}
