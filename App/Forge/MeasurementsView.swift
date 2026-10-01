import ForgeCore
import SwiftData
import SwiftUI

/// Body stats: is bodyweight moving the right way? Weekly weigh-ins, the goal verdict,
/// waist, and the full history grouped by block.
struct MeasurementsView: View {
  let usesLb: Bool
  @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
  @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query private var profiles: [UserProfile]
  @Query(sort: \NutritionProfile.updated, order: .reverse) private var nutritionProfiles:
    [NutritionProfile]
  @Query(sort: \FoodEntry.date, order: .reverse) private var foodEntries: [FoodEntry]
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var showAdd = false
  @State private var pendingDelete: BodyMeasurement?

  private var profile: UserProfile? { profiles.first }
  private var unit: String { usesLb ? "lb" : "kg" }

  private var weightEntries: [(date: Date, kg: Double)] {
    measurements
      .compactMap { m in m.weightKg.map { (date: m.date, kg: $0) } }
      .filter { $0.kg > 0 }
      .sorted { $0.date < $1.date }
  }

  private var waistEntries: [(date: Date, cm: Double)] {
    measurements
      .compactMap { m in m.tape["waist"].map { (date: m.date, cm: $0) } }
      .filter { $0.cm > 0 }
      .sorted { $0.date < $1.date }
  }

  /// Weigh-ins inside the 90-day chart window, in the display unit.
  private var chartPoints: [(date: Date, value: Double)] {
    let cutoff = Date.now.addingTimeInterval(-90 * 86400)
    return weightEntries
      .filter { $0.date > cutoff }
      .map { (date: $0.date, value: UnitFormat.plain($0.kg, usesLb: usesLb)) }
  }

  private var blockStarts: [Date] {
    LogV3.blocks(sessions: sessions, profile: profile).compactMap(\.firstDate)
  }

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ProgressLargeTitle(
          title: "Body stats",
          subtitle: subtitle,
          art: "art-numbers"
        )
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 20)

        if chartPoints.count < 2 {
          Text("Log two weights to see the 90-day trend.")
            .forgeLabel()
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 20)
        } else {
          headline
          chart
            .padding(.bottom, 20)
          verdict
            .padding(.bottom, 12)
        }
        LogBand()
        if !waistEntries.isEmpty {
          waistSection
          LogBand()
        }
        historySection.padding(.bottom, 24)
      }
    }
    .background(Theme.page)
    .progressTitleNavigation("Body stats")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button { showAdd = true } label: { Image(systemName: "plus") }
          .accessibilityLabel(String(localized: "Add measurement", bundle: L10n.bundle))
      }
    }
    .navigationDestination(isPresented: $showAdd) { AddMeasurementSheet(usesLb: usesLb) }
    .confirmationDialog(
      "Delete this entry?",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        guard let entry = pendingDelete else { return }
        SyncEngine.shared.deleteEverywhere(type: "measurement", wireID: entry.remoteID)
        modelContext.delete(entry)
        pendingDelete = nil
      }
      Button("Cancel", role: .cancel) { pendingDelete = nil }
    } message: {
      Text("This can't be undone.")
    }
  }

  private var subtitle: String? {
    guard let first = weightEntries.first else { return nil }
    return String(
      localized: "Weigh-ins since \(first.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))",
      bundle: L10n.bundle)
  }

  // MARK: headline

  private var headline: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Text(verbatim: Fmt.num(UnitFormat.plain(weightEntries.last!.kg, usesLb: usesLb)))
          .forge(44, .bold)
          .tracking(-1)
          .monospacedDigit()
          .foregroundStyle(Theme.text)
        Text(verbatim: unit)
          .forge(22, .medium)
          .foregroundStyle(Theme.textSecondary)
        if let delta = deltaSinceFirst {
          Text(verbatim: delta)
            .forge(17, .medium)
            .monospacedDigit()
            .foregroundStyle(Theme.textSecondary)
        }
      }
      Text(verbatim: lastNextLine)
        .forge(15, .regular)
        .foregroundStyle(Theme.textSecondary)
        .monospacedDigit()
    }
    .padding(.horizontal, Theme.margin)
    .padding(.bottom, 20)
    .accessibilityElement(children: .combine)
  }

  private var deltaSinceFirst: String? {
    guard weightEntries.count >= 2, let first = weightEntries.first,
      let last = weightEntries.last
    else { return nil }
    let delta = UnitFormat.plain(last.kg - first.kg, usesLb: usesLb)
    guard abs(delta) >= 0.05 else {
      return String(localized: "Same as the first weigh-in", bundle: L10n.bundle)
    }
    let sign = delta > 0 ? "+" : "\u{2212}"
    let since = first.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
    return String(
      localized: "\(sign)\(Fmt.num(abs(delta))) \(unit) since \(since)", bundle: L10n.bundle)
  }

  /// "Last weigh-in Sat Sep 26 · next Sat Oct 3" — the next date only when the rhythm is
  /// steady enough to predict one.
  private var lastNextLine: String {
    guard let last = weightEntries.last else {
      return String(localized: "No weigh-ins yet", bundle: L10n.bundle)
    }
    let lastText = last.date.formatted(
      .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
    let lastPart = String(localized: "Last weigh-in \(lastText)", bundle: L10n.bundle)
    if let gap = BodyV3.steadyGap(days: weightEntries.suffix(4).map(\.date)),
      let next = Calendar.current.date(byAdding: .day, value: gap, to: last.date)
    {
      let nextText = next.formatted(
        .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
      return String(
        localized: "\(lastPart) · next \(nextText)", bundle: L10n.bundle)
    }
    return lastPart
  }

  // MARK: chart

  private var chart: some View {
    let starts = blockStarts
    let blockIndex: Int? = starts.count > 1
      ? (chartPoints.firstIndex { $0.date >= (starts.last ?? .distantFuture) } ?? chartPoints.count)
      : nil
    return V3WeightChart(
      points: chartPoints,
      currentBlockStart: blockIndex,
      blockLabel: starts.count > 1
        ? String(localized: "Block \(starts.count)", bundle: L10n.bundle)
        : nil
    )
    .frame(height: 178)
    .padding(.horizontal, Theme.margin)
  }

  // MARK: verdict

  @ViewBuilder private var verdict: some View {
    if let text = verdictText {
      VStack(alignment: .leading, spacing: 6) {
        Text(verbatim: text.headline)
          .forge(17, .semibold)
          .foregroundStyle(Theme.text)
        Text(verbatim: text.detail)
          .forge(15, .regular)
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
        NavigationLink {
          NutritionView()
        } label: {
          V3Link(text: String(localized: "Open Fuel", bundle: L10n.bundle))
        }
        .buttonStyle(RowPressStyle())
        .accessibilityIdentifier("body.openFuel")
      }
      .padding(.horizontal, Theme.margin)
    }
  }

  /// The goal verdict, only when both the goal and a weight trend are known.
  private var verdictText: (headline: String, detail: String)? {
    guard let goalString = profile?.goal, let goal = Goal(rawValue: goalString),
      weightEntries.count >= 2,
      let first = weightEntries.first, let last = weightEntries.last
    else { return nil }
    let delta = last.kg - first.kg
    guard abs(delta) >= 0.05 else { return nil }
    let headline: String
    switch goal {
    case .strength:
      headline = String(localized: "For building strength, hold or gain slowly", bundle: L10n.bundle)
    default:
      headline = String(localized: "For building muscle, hold or gain slowly", bundle: L10n.bundle)
    }
    let displayDelta = UnitFormat.plain(delta, usesLb: usesLb)
    let since = first.date.formatted(.dateTime.month(.abbreviated).locale(L10n.locale))
    let trend = displayDelta < 0
      ? String(
        localized: "Weight is down \(Fmt.num(abs(displayDelta))) \(unit) since \(since).",
        bundle: L10n.bundle)
      : String(
        localized: "Weight is up \(Fmt.num(displayDelta)) \(unit) since \(since).",
        bundle: L10n.bundle)
    return (headline, [trend, kcalLine].compactMap { $0 }.joined(separator: " "))
  }

  /// "You average 2,480 kcal a day, 170 under your target.", when fuel data can say it.
  private var kcalLine: String? {
    guard let target = nutritionProfiles.first?.kcal, target > 0 else { return nil }
    let cutoff = Date.now.addingTimeInterval(-7 * 86400)
    let days = Dictionary(grouping: foodEntries.filter { !$0.tombstoned && $0.date > cutoff }) {
      Calendar.current.startOfDay(for: $0.date)
    }
    let totals = days.values.map { $0.reduce(0.0) { $0 + $1.kcal } }
    guard !totals.isEmpty else { return nil }
    let avg = totals.reduce(0, +) / Double(totals.count)
    let diff = Double(target) - avg
    guard abs(diff) >= 10 else { return nil }
    let under = diff > 0
    let average = Fmt.grouped(avg.rounded())
    let gap = Fmt.grouped(abs(diff).rounded())
    return under
      ? String(localized: "You average \(average) kcal a day, \(gap) kcal under your target.", bundle: L10n.bundle)
      : String(localized: "You average \(average) kcal a day, \(gap) kcal over your target.", bundle: L10n.bundle)
  }

  // MARK: waist

  private var waistSection: some View {
    VStack(spacing: 0) {
      V3SectionHeader(
        "Waist",
        trailing: String(
          localized: "Measured \(waistEntries.last!.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))",
          bundle: L10n.bundle))
      HStack(alignment: .center, spacing: 12) {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          Text(verbatim: Fmt.num(waistEntries.last!.cm, max: 0))
            .forge(28, .bold)
            .tracking(-0.5)
            .monospacedDigit()
            .foregroundStyle(Theme.text)
          Text(verbatim: "cm")
            .forge(15, .medium)
            .foregroundStyle(Theme.textSecondary)
          if let delta = waistDelta {
            Text(verbatim: delta)
              .forge(17, .medium)
              .monospacedDigit()
              .foregroundStyle(Theme.textSecondary)
          }
        }
        LiftSparkline(valuesKg: waistEntries.suffix(10).map(\.cm), ringColor: Theme.page)
          .frame(width: 72, height: 28)
      }
      .frame(maxWidth: .infinity, alignment: .trailing)
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 12)
      if let note = unmeasuredNote {
        V3NoteRow(icon: "figure-standing", title: note.title, subtitle: note.detail)
          .padding(.horizontal, Theme.margin)
          .padding(.bottom, 20)
      }
    }
  }

  private var waistDelta: String? {
    guard waistEntries.count >= 2, let first = waistEntries.first,
      let last = waistEntries.last
    else { return nil }
    let delta = last.cm - first.cm
    guard abs(delta) >= 0.5 else { return nil }
    let sign = delta > 0 ? "+" : "\u{2212}"
    let since = first.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
    return String(
      localized: "\(sign)\(Fmt.num(abs(delta), max: 1)) cm since \(since)", bundle: L10n.bundle)
  }

  /// Tape sites the lifter never measured, offered for the next weigh-in.
  private var unmeasuredNote: (title: String, detail: String)? {
    let measured = Set(measurements.flatMap { m in m.tape.filter { $0.value > 0 }.keys })
    let missing = BodyMeasurement.tapeKeys.filter { !measured.contains($0) }
    guard !missing.isEmpty else { return nil }
    let names = missing.map(tapeName)
    let list = names.formatted(.list(type: .and).locale(L10n.locale))
    return (
      list,
      String(
        localized: "Not measured yet. Add them with your next weigh-in.", bundle: L10n.bundle)
    )
  }

  // MARK: history

  private struct HistoryGroup {
    let title: String
    let span: String?
    let entries: [BodyMeasurement]
  }

  private var historyGroups: [HistoryGroup] {
    let ascending = measurements.sorted { $0.date < $1.date }
    guard !ascending.isEmpty else { return [] }
    var groups: [HistoryGroup] = []
    let starts = blockStarts
    if starts.isEmpty {
      let byMonth = Dictionary(grouping: ascending) {
        Calendar.current.date(
          from: Calendar.current.dateComponents([.year, .month], from: $0.date)) ?? $0.date
      }
      for month in byMonth.keys.sorted(by: >) {
        let entries = byMonth[month]!.sorted { $0.date > $1.date }
        groups.append(
          HistoryGroup(
            title: month.formatted(.dateTime.month(.wide).locale(L10n.locale)), span: nil,
            entries: entries))
      }
      return groups
    }
    var bounds = starts
    if let earliest = ascending.first?.date, earliest < bounds[0] { bounds[0] = earliest }
    for (index, start) in bounds.enumerated() {
      let end = index + 1 < bounds.count ? bounds[index + 1] : .distantFuture
      let inBlock = ascending.filter { $0.date >= start && $0.date < end }
      guard !inBlock.isEmpty else { continue }
      let firstDate = inBlock.first!.date
      let lastDate = inBlock.map { $0.date }.max() ?? firstDate
      groups.append(
        HistoryGroup(
          title: String(localized: "Block \(index + 1)", bundle: L10n.bundle),
          span: LogV3.spanText(from: firstDate, to: lastDate),
          entries: inBlock.sorted { $0.date > $1.date }))
    }
    return groups.reversed()
  }

  private var historySection: some View {
    VStack(spacing: 0) {
      V3SectionHeader("History", trailing: historyCountText)
      ForEach(Array(historyGroups.enumerated()), id: \.offset) { groupIndex, group in
        groupHeader(group)
        ForEach(Array(group.entries.enumerated()), id: \.element.id) { index, entry in
          if index > 0 || groupIndex > 0 {
            Divider()
              .padding(.leading, Theme.margin + 44)
              .padding(.trailing, Theme.margin)
          }
          historyRow(entry)
        }
      }
    }
  }

  private var historyCountText: String {
    let count = measurements.count
    guard count > 0 else { return String(localized: "No entries yet", bundle: L10n.bundle) }
    return String(localized: "\(count) entries", bundle: L10n.bundle)
  }

  private func groupHeader(_ group: HistoryGroup) -> some View {
    HStack(alignment: .firstTextBaseline) {
      Text(verbatim: group.title).forge(15, .semibold).foregroundStyle(Theme.textSecondary)
      Spacer()
      if let span = group.span {
        Text(verbatim: span)
          .forge(14, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
      }
    }
    .padding(.horizontal, Theme.margin)
    .padding(.top, 8)
    .padding(.bottom, 2)
  }

  private func historyRow(_ entry: BodyMeasurement) -> some View {
    SwipeDeleteRow(onDelete: { pendingDelete = entry }, surface: Theme.page) {
      V3DetailRow(
        icon: entry.weightKg != nil ? "scalemass.fill" : "ruler",
        title: historyTitle(entry),
        subtitle: historySubtitle(entry),
        trailing: {
          Text(verbatim: historyChange(entry))
            .lineLimit(1)
            .minimumScaleFactor(0.85)
        }
      )
    }
    .padding(.horizontal, Theme.margin)
  }

  /// "80.6 kg", "Waist 84 cm", or the first tape reading of an entry without weight.
  private func historyTitle(_ entry: BodyMeasurement) -> String {
    if let weight = entry.weightKg {
      let text = "\(Fmt.num(UnitFormat.plain(weight, usesLb: usesLb))) \(unit)"
      if let waist = entry.tape["waist"], waist > 0 {
        return String(
          localized: "\(text) · waist \(Fmt.num(waist, max: 1)) cm", bundle: L10n.bundle)
      }
      return text
    }
    if let waist = entry.tape["waist"], waist > 0 {
      return String(localized: "Waist \(Fmt.num(waist, max: 1)) cm", bundle: L10n.bundle)
    }
    return tapeLine(entry)
  }

  private func historySubtitle(_ entry: BodyMeasurement) -> String {
    let date = entry.date.formatted(
      .dateTime.weekday(.abbreviated).month(.abbreviated).day().locale(L10n.locale))
    let sameDay = photos.contains { Calendar.current.isDate($0.date, inSameDayAs: entry.date) }
    return sameDay
      ? String(localized: "\(date) · with photos", bundle: L10n.bundle)
      : date
  }

  /// Change from the previous entry of the same kind; "Start" on the first one.
  private func historyChange(_ entry: BodyMeasurement) -> String {
    let ascending = measurements.sorted { $0.date < $1.date }
    let index = ascending.firstIndex(where: { $0.id == entry.id }) ?? 0
    if entry.weightKg != nil {
      let previous = ascending[..<index].last { $0.weightKg != nil }?.weightKg
      guard let prev = previous, let weight = entry.weightKg else {
        return String(localized: "Start", bundle: L10n.bundle)
      }
      return changeText(weight - prev, unit: unit, usesLb: usesLb)
    }
    if let waist = entry.tape["waist"] {
      let previous = ascending[..<index].compactMap { $0.tape["waist"] }.last
      guard let prev = previous else { return String(localized: "Start", bundle: L10n.bundle) }
      return changeText(waist - prev, unit: "cm", usesLb: false)
    }
    return ""
  }

  private func changeText(_ delta: Double, unit: String, usesLb: Bool) -> String {
    let d = usesLb ? UnitFormat.plain(delta, usesLb: true) : delta
    if abs(d) < 0.05 { return String(localized: "No change", bundle: L10n.bundle) }
    let sign = d > 0 ? "+" : "\u{2212}"
    return String(
      localized: "\(sign)\(Fmt.num(abs(d))) \(unit)", bundle: L10n.bundle)
  }

  /// Tape readings of an entry, as one line (kept from the previous screen).
  private func tapeLine(_ entry: BodyMeasurement) -> String {
    BodyMeasurement.tapeKeys
      .compactMap { key in entry.tape[key].map { "\(tapeName(key)) \(Fmt.num($0, max: 2)) cm" } }
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
  @State private var confirmDiscard = false
  @FocusState private var focused: Field?

  private enum Field: Hashable { case weight, bodyFat, tape(String) }

  private var fields: [Field] { [.weight, .bodyFat] + BodyMeasurement.tapeKeys.map(Field.tape) }
  private var nextField: Field? {
    guard let focused, let i = fields.firstIndex(of: focused), i + 1 < fields.count else { return nil }
    return fields[i + 1]
  }

  private func parse(_ text: String) -> Double? {
    Double(text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: "."))
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.groupGap) {
        DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
          .forgeBody()
        HStack {
          Text("Weight").forgeBodyStrong()
          Spacer()
          TextField(usesLb ? "lb" : "kg", text: $weightText)
            .keyboardType(.decimalPad)
            .focused($focused, equals: .weight)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 110)
            .accessibilityLabel(
              usesLb
              ? String(localized: "Body weight in pounds", bundle: L10n.bundle)
              : String(localized: "Body weight in kilograms", bundle: L10n.bundle))
        }
        .innerSurface()
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
        .onTapGesture { focused = .weight }
        HStack {
          Text("Body fat").forgeBodyStrong()
          Spacer()
          TextField("%", text: $bodyFatText)
            .keyboardType(.decimalPad)
            .focused($focused, equals: .bodyFat)
            .multilineTextAlignment(.trailing)
            .monospacedDigit()
            .frame(width: 110)
            .accessibilityLabel(String(localized: "Body fat percentage", bundle: L10n.bundle))
        }
        .innerSurface()
        .contentShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
        .onTapGesture { focused = .bodyFat }
        ForEach(BodyMeasurement.tapeKeys, id: \.self) { key in
          HStack {
            Text(tapeName(key)).forgeBodyStrong()
            Spacer()
            TextField("cm", text: binding(key))
              .keyboardType(.decimalPad)
              .focused($focused, equals: .tape(key))
              .multilineTextAlignment(.trailing)
              .monospacedDigit()
              .frame(width: 110)
              .accessibilityLabel(
                String(localized: "\(tapeName(key)) in centimeters", bundle: L10n.bundle))
          }
          .innerSurface()
          .contentShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
          .onTapGesture { focused = .tape(key) }
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
        .disabled(!isDirty)
      }
      .padding(Theme.margin)
      .frame(maxWidth: .infinity, alignment: .leading)
      .onSubmit { focused = nextField }
    }
    .background(Theme.page)
    .scrollDismissesKeyboard(.interactively)
    .navigationTitle("Add measurement")
    .navigationBarTitleDisplayMode(.inline)
    .onAppear { focused = .weight }
    .navigationBarBackButtonHidden(isDirty)
    .interactiveDismissDisabled(isDirty)
    .toolbar {
      if isDirty {
        ToolbarItem(placement: .topBarLeading) {
          Button(String(localized: "Go back", bundle: L10n.bundle)) { confirmDiscard = true }
        }
      }
      ToolbarItemGroup(placement: .keyboard) {
        Spacer()
        if let next = nextField {
          Button(String(localized: "Next", bundle: L10n.bundle)) { focused = next }
        }
        Button(String(localized: "Done", bundle: L10n.bundle)) { focused = nil }
      }
    }
    .confirmationDialog(
      "Discard this entry?",
      isPresented: $confirmDiscard,
      titleVisibility: .visible
    ) {
      Button("Discard", role: .destructive) { dismiss() }
      Button("Cancel", role: .cancel) { confirmDiscard = false }
    } message: {
      Text("Your changes will be lost.")
    }
  }

  private var isDirty: Bool {
    let trimmed = [weightText, bodyFatText].map { $0.trimmingCharacters(in: .whitespaces) }
      + tapeTexts.values.map { $0.trimmingCharacters(in: .whitespaces) }
    return trimmed.contains { !$0.isEmpty }
  }

  private func binding(_ key: String) -> Binding<String> {
    Binding(get: { tapeTexts[key] ?? "" }, set: { tapeTexts[key] = $0 })
  }
}

/// Display name for a tape-measurement key; keys themselves are stored data.
private func tapeName(_ key: String) -> String {
  switch key {
  case "chest": return String(localized: "Chest", bundle: L10n.bundle)
  case "waist": return String(localized: "Waist", bundle: L10n.bundle)
  case "hips": return String(localized: "Hips", bundle: L10n.bundle)
  case "arm": return String(localized: "Arm", bundle: L10n.bundle)
  case "thigh": return String(localized: "Thigh", bundle: L10n.bundle)
  default: return key.capitalized
  }
}
