import SwiftUI
import SwiftData
import Charts
import ForgeCore

struct MeasurementsView: View {
  let usesLb: Bool
  @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var showAdd = false

  private var weightPoints: [(date: Date, value: Double)] {
    measurements
      .filter { ($0.weightKg ?? 0) > 0 && $0.date > Date.now.addingTimeInterval(-90 * 86400) }
      .sorted { $0.date < $1.date }
      .map { (date: $0.date, value: UnitFormat.plain($0.weightKg!, usesLb: usesLb)) }
  }

  var body: some View {
    List {
      Section {
        if weightPoints.count >= 2 {
          Chart(weightPoints, id: \.date) { point in
            AreaMark(x: .value("Date", point.date), y: .value("Weight", point.value))
              .foregroundStyle(
                LinearGradient(colors: [Theme.accentValue.opacity(0.28), Theme.accentValue.opacity(0)], startPoint: .top, endPoint: .bottom))
              .interpolationMethod(.catmullRom)
            LineMark(x: .value("Date", point.date), y: .value("Weight", point.value))
              .foregroundStyle(Theme.accentValue)
              .interpolationMethod(.catmullRom)
              .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
          }
          .chartYScale(domain: .automatic(includesZero: false))
          .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) {
              AxisGridLine().foregroundStyle(Theme.track)
              AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                .font(.forge(11, .medium))
                .foregroundStyle(Theme.textTertiary)
            }
          }
          .chartYAxis {
            AxisMarks(position: .trailing) {
              AxisGridLine().foregroundStyle(Theme.track)
              AxisValueLabel()
                .font(.forge(11, .medium))
                .foregroundStyle(Theme.textTertiary)
            }
          }
          .frame(height: 180)
          .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
        } else {
          Text("Log two weights to see the 90-day trend.")
            .forgeLabel()
        }
      } header: {
        Text("Weight · last 90 days (\(usesLb ? "lb" : "kg"))").forgeLabel()
      }

      Section {
        ForEach(measurements) { entry in
          MeasurementRow(entry: entry, usesLb: usesLb)
        }
        .onDelete { indexes in
          for index in indexes { modelContext.delete(measurements[index]) }
        }
      }
    }
    .navigationTitle("Measurements")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button { showAdd = true } label: { Image(systemName: "plus") }
      }
    }
    .sheet(isPresented: $showAdd) { AddMeasurementSheet(usesLb: usesLb) }
  }
}

private struct MeasurementRow: View {
  let entry: BodyMeasurement
  let usesLb: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(entry.date, format: .dateTime.month(.wide).day().year()).forgeBodyStrong()
      Text(mainLine).forgeLabel().monospacedDigit()
      if !tapeLine.isEmpty {
        Text(tapeLine).forgeCaption().monospacedDigit()
      }
    }
  }

  private var mainLine: String {
    let parts = [
      entry.weightKg.map { String(localized: "\(Int(UnitFormat.plain($0, usesLb: usesLb).rounded())) \(usesLb ? "lb" : "kg")") },
      entry.bodyFatPercent.map { String(format: "%.1f %% BF", $0) },
    ].compactMap { $0 }
    return parts.isEmpty ? "—" : parts.joined(separator: " · ")
  }

  private var tapeLine: String {
    BodyMeasurement.tapeKeys
      .compactMap { key in entry.tape[key].map { String(localized: "\(tapeName(key)) \(Int($0.rounded())) cm") } }
      .joined(separator: " · ")
  }
}

private struct AddMeasurementSheet: View {
  let usesLb: Bool
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var date = Date.now
  @State private var weightText = ""
  @State private var bodyFatText = ""
  @State private var tapeTexts: [String: String] = [:]

  private func parse(_ text: String) -> Double? {
    Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.groupGap) {
          DatePicker("Date", selection: $date, displayedComponents: .date)
            .forgeBody()
          HStack {
            Text("Weight").forgeBodyStrong()
            Spacer()
            TextField(usesLb ? "lb" : "kg", text: $weightText)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .monospacedDigit()
              .frame(width: 110)
          }
          .innerSurface()
          HStack {
            Text("Body fat").forgeBodyStrong()
            Spacer()
            TextField("%", text: $bodyFatText)
              .keyboardType(.decimalPad)
              .multilineTextAlignment(.trailing)
              .monospacedDigit()
              .frame(width: 110)
          }
          .innerSurface()
          ForEach(BodyMeasurement.tapeKeys, id: \.self) { key in
            HStack {
              Text(tapeName(key)).forgeBodyStrong()
              Spacer()
              TextField("cm", text: binding(key))
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .frame(width: 110)
            }
            .innerSurface()
          }
          Button("Save") {
            let weight = parse(weightText).map { usesLb ? Plates.lbToKg($0) : $0 }
            let tape = BodyMeasurement.tapeKeys.reduce(into: [String: Double]()) { result, key in
              if let v = parse(tapeTexts[key] ?? "") { result[key] = v }
            }
            modelContext.insert(BodyMeasurement(
              date: date,
              weightKg: weight,
              bodyFatPercent: parse(bodyFatText),
              tape: tape))
            dismiss()
          }
          .buttonStyle(PillButtonStyle())
        }
        .padding(Theme.margin)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
      .background(Theme.page)
      .navigationTitle("Add measurement")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Cancel") { dismiss() } }
      .presentationDetents([.large, .medium])
    }
  }

  private func binding(_ key: String) -> Binding<String> {
    Binding(get: { tapeTexts[key] ?? "" }, set: { tapeTexts[key] = $0 })
  }
}

/// Display name for a tape-measurement key; keys themselves are stored data.
private func tapeName(_ key: String) -> String {
  switch key {
  case "chest": return String(localized: "Chest")
  case "waist": return String(localized: "Waist")
  case "hips": return String(localized: "Hips")
  case "arm": return String(localized: "Arm")
  case "thigh": return String(localized: "Thigh")
  default: return key.capitalized
  }
}
