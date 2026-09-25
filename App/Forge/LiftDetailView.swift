import SwiftUI
import SwiftData
import Charts
import ForgeCore

/// One lift's detail: hero on the sky, estimated-max trend card, records.
struct LiftDetailView: View {
  let exercise: Exercise
  let data: ProgressData
  let usesLb: Bool
  @Query private var profiles: [UserProfile]

  /// Per-exercise kg/lb override beats the profile-wide default.
  private var isLb: Bool {
    profiles.first?.isLb(for: exercise.id) ?? usesLb
  }

  private var series: [E1RMPoint] { data.e1rmSeries(for: exercise.id) }
  private var record: ProgressData.Record? { data.bestSet(for: exercise.id) }
  private var next: ProgressData.NextTarget? { data.nextTarget(for: exercise) }
  private var recent: Bool {
    record.map { $0.date >= Date.now.addingTimeInterval(-30 * 86400) } ?? false
  }

  private var unit: String { isLb ? "lb" : "kg" }

  /// e1RM series converted to display units.
  private var points: [(date: Date, value: Double)] {
    series.map { (date: $0.date, value: isLb ? Plates.kgToLb($0.e1rm) : $0.e1rm) }
  }

  private var shareText: String {
    let name = exercise.localizedName
    if points.count >= 2, let first = points.first, let last = points.last {
      let delta = last.value - first.value
      let signedDelta = "\(delta >= 0 ? "+" : "−")\(Fmt.num(abs(delta).rounded()))"
      let month = first.date.formatted(.dateTime.month(.wide).locale(L10n.locale))
      return String(
        localized:
          "\(name): estimated max \(Fmt.num(last.value.rounded())) \(unit) · \(signedDelta) \(unit) since \(month) — Regulift",
        bundle: L10n.bundle)
    }
    let value = points.last.map { Fmt.num($0.value.rounded()) }
      ?? record.map { Fmt.num(display($0.e1rm).rounded()) } ?? ""
    return String(
      localized: "\(name): estimated max \(value) \(unit) — Regulift",
      bundle: L10n.bundle)
  }

  private func display(_ kg: Double) -> Double {
    isLb ? Plates.kgToLb(kg) : kg
  }

  private func recordPillText(for record: ProgressData.Record) -> String {
    if Calendar.current.isDateInToday(record.date) {
      return String(localized: "Record today", bundle: L10n.bundle)
    }
    return String(
      localized: "Record \(record.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))",
      bundle: L10n.bundle)
  }

  private func repRangeText(_ range: ClosedRange<Int>) -> String {
    range.lowerBound == range.upperBound ? "\(range.lowerBound)" : "\(range.lowerBound)–\(range.upperBound)"
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        hero
        strengthCard
        recordsCard
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 32)
    }
    .background(TodaySkyPage())
    .toolbarBackground(.hidden, for: .navigationBar)
    .navigationTitle(exercise.localizedName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .principal) { Text("") }
      ToolbarItem(placement: .topBarTrailing) {
        ShareLink(item: shareText) { Image(systemName: "square.and.arrow.up") }
          .accessibilityLabel("Share")
      }
    }
  }

  private var hero: some View {
    VStack(spacing: 12) {
      LiftToken(exercise: exercise, size: 148, record: recent, onSky: true)
      Text(exercise.localizedName)
        .forge(34, .bold)
        .foregroundStyle(Theme.text)
        .multilineTextAlignment(.center)
        .accessibilityAddTraits(.isHeader)
      HStack(spacing: 8) {
        SkyPill(exercise.primary.a11yName, style: .neutral)
        if recent, let record {
          SkyPill(recordPillText(for: record), symbol: "trophy.fill", style: .gold)
        }
      }
    }
    .frame(maxWidth: .infinity)
  }

  private var strengthCard: some View {
    SkyCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Estimated max").forge(15, .semibold).foregroundStyle(Theme.textSecondary)
        if points.isEmpty {
          Text("No eligible sets for this lift yet.").forgeBody()
        } else {
          HStack(alignment: .firstTextBaseline) {
            Text(Fmt.num(points.last!.value.rounded())).forge(56, .bold).foregroundStyle(Theme.text).monospacedDigit()
              .lineLimit(1).fixedSize()
            Text(unit).forge(22, .semibold).foregroundStyle(Theme.textSecondary)
            Spacer()
            if points.count >= 2, let first = points.first, let last = points.last {
              let delta = last.value - first.value
              SkyPill(
                String(
                  localized:
                    "\(delta >= 0 ? "+" : "-")\(Fmt.num(abs(delta).rounded())) \(unit) since \(first.date.formatted(.dateTime.month(.abbreviated).locale(L10n.locale)))",
                  bundle: L10n.bundle),
                symbol: delta >= 0 ? "arrow.up" : "arrow.down",
                style: delta >= 0 ? .green : .neutral)
            }
          }
          trendChart
        }
        Text("Estimated from your best set each session").forge(13, .regular).foregroundStyle(Theme.textTertiary)
      }
    } footer: {
      if let next {
        HStack(spacing: 12) {
          CoachAvatar(size: 28)
          VStack(alignment: .leading, spacing: 2) {
            Text("Next: \(Fmt.num(display(next.weightKg))) \(unit) × \(repRangeText(next.repRange))")
              .forge(17, .semibold)
              .foregroundStyle(Theme.text)
              .monospacedDigit()
            Text(next.dayName).forge(15, .regular).foregroundStyle(Theme.textSecondary)
          }
          Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .background(Theme.todayFooter)
      }
    }
  }

  /// Under two months of history, month-only axis labels would repeat ("Sep Sep Sep").
  private var shortHistory: Bool {
    guard let first = points.first?.date, let last = points.last?.date else { return true }
    return last.timeIntervalSince(first) < 60 * 86400
  }

  private var trendChart: some View {
    let values = points.map(\.value)
    let lo = ((values.min()! - 5) / 5).rounded(.down) * 5
    let hi = ((values.max()! + 5) / 5).rounded(.up) * 5
    let lastDate = points.last?.date
    return Chart(points, id: \.date) { point in
      // The fill starts at the axis floor; from 0 it would bleed under the axis labels.
      AreaMark(
        x: .value("Date", point.date), yStart: .value("Estimated max", lo),
        yEnd: .value("Estimated max", point.value))
        .foregroundStyle(Theme.accent.opacity(0.08))
        .interpolationMethod(.catmullRom)
      LineMark(x: .value("Date", point.date), y: .value("Estimated max", point.value))
        .foregroundStyle(Theme.accent)
        .interpolationMethod(.catmullRom)
        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
      PointMark(x: .value("Date", point.date), y: .value("Estimated max", point.value))
        .foregroundStyle(point.date == lastDate && recent ? Theme.recordRing : Theme.accent)
        .symbolSize(point.date == lastDate ? 90 : 25)
    }
    .chartYScale(domain: lo...hi)
    .chartYAxis {
      AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) {
        AxisGridLine().foregroundStyle(Theme.track)
        AxisValueLabel().font(.forge(13, .regular)).foregroundStyle(Theme.textTertiary)
      }
    }
    .chartXAxis {
      AxisMarks(values: .automatic(desiredCount: 4)) {
        AxisGridLine().foregroundStyle(Theme.track)
        AxisValueLabel(format: shortHistory ? .dateTime.day().month(.abbreviated).locale(L10n.locale) : .dateTime.month(.abbreviated).locale(L10n.locale))
          .font(.forge(13, .regular))
          .foregroundStyle(Theme.textTertiary)
      }
    }
    .frame(height: 160)
  }

  private var recordsCard: some View {
    SkyCard {
      VStack(alignment: .leading, spacing: 12) {
        Text("Records").forgeBodyStrong()
        if let best = points.max(by: { $0.value < $1.value }) {
          recordRow(title: "Best estimated max", value: "\(Fmt.num(best.value)) \(unit)", date: best.date)
        }
        if let record {
          recordRow(
            title: "Newest record",
            value: "\(Fmt.num(display(record.weightKg))) \(unit) × \(record.reps)",
            date: record.date)
        }
        recordRow(title: "Sessions", value: "\(series.count)", date: nil)
      }
    }
  }

  private func recordRow(title: LocalizedStringKey, value: String, date: Date?) -> some View {
    HStack(spacing: 12) {
      ZStack {
        Circle().fill(Theme.recordTint)
        Image(systemName: "trophy.fill")
          .font(.system(size: 14))
          .foregroundStyle(Theme.recordInk)
      }
      .frame(width: 32, height: 32)
      Text(title).forge(17, .regular).foregroundStyle(Theme.text)
      Spacer()
      VStack(alignment: .trailing, spacing: 2) {
        Text(value).forge(17, .semibold).monospacedDigit()
        if let date {
          Text(date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))
            .forge(13, .regular)
            .foregroundStyle(Theme.textTertiary)
        }
      }
    }
  }
}
