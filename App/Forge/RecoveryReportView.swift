import Charts
import ForgeCore
import SwiftData
import SwiftUI

struct RecoveryReportView: View {
  @Query(sort: \CheckIn.date) private var checkIns: [CheckIn]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  private var week: [CheckIn] {
    checkIns.filter { $0.date > Date.now.addingTimeInterval(-7 * 86400) }
  }

  private var weekSessions: [WorkoutSession] {
    sessions.filter { $0.completed && $0.date > Date.now.addingTimeInterval(-7 * 86400) }
  }

  private var avgSleepHours: Double? { average(week.map(\.sleepHours)) }
  private var avgSleep: Double? { average(week.map { Double($0.sleep) }) }
  private var avgSoreness: Double? { average(week.map { Double($0.soreness) }) }
  private var avgEnergy: Double? { average(week.map { Double($0.energy) }) }

  private var fatiguePoints: [(date: Date, value: Double)] {
    week.map { (date: $0.date, value: Double($0.soreness + (5 - $0.energy))) }
      .sorted { $0.date < $1.date }
  }

  private var assessedSummary: String {
    if let soreness = avgSoreness, soreness >= 4 {
      return String(
        localized:
          "Recorded soreness is elevated. Keep effort conservative and use the plan's recovery rules.",
        bundle: L10n.bundle)
    }
    if let energy = avgEnergy, energy <= 2.5 {
      return String(
        localized: "Recorded energy is low. Keep reported effort honest and prioritize recovery.",
        bundle: L10n.bundle)
    }
    return String(
      localized:
        "Recorded check-ins look stable. Follow today's prescribed session and report how it feels.",
      bundle: L10n.bundle)
  }

  private var presentation: RecoveryPresentation {
    RecoveryPresentationPolicy.presentation(
      sampleCount: week.count,
      assessedSummary: assessedSummary)
  }

  private var columns: [GridItem] {
    dynamicTypeSize.isAccessibilitySize
      ? [GridItem(.flexible())]
      : [GridItem(.adaptive(minimum: 160), spacing: 10)]
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.groupGap) {
        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .firstTextBaseline) {
            Text("Last 7 days").forgeSection()
            Spacer()
            Text("\(week.count) check-in\(week.count == 1 ? "" : "s") recorded")
              .forgeCaption().monospacedDigit()
          }
          LazyVGrid(columns: columns, spacing: 10) {
            RecoveryMetricTile(
              symbol: "moon.zzz", value: format(avgSleepHours, suffix: " h"),
              label: "Sleep duration", detail: "Average of recorded check-ins")
            RecoveryMetricTile(
              symbol: "sparkles", value: format(avgSleep), label: "Sleep quality",
              detail: "Subjective 1–5 scale")
            RecoveryMetricTile(
              symbol: "flame", value: format(avgSoreness), label: "Soreness",
              detail: "Subjective 1–5 scale")
            RecoveryMetricTile(
              symbol: "bolt.fill", value: format(avgEnergy), label: "Energy",
              detail: "Subjective 1–5 scale")
            RecoveryMetricTile(
              symbol: "dumbbell", value: "\(weekSessions.count)", label: "Recorded sessions",
              detail: "Completed in this 7-day window")
            RecoveryMetricTile(
              symbol: "square.stack.3d.up.fill",
              value: "\(weekSessions.flatMap(\.trustedSets).count)", label: "Eligible sets",
              detail: "Trusted sets in this 7-day window")
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()

        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .firstTextBaseline) {
            Text("Fatigue observations").forgeSection()
            Spacer()
            Text("soreness + (5 − energy)").forgeCaption()
          }
          if fatiguePoints.count >= 2 {
            Chart(fatiguePoints, id: \.date) { point in
              LineMark(x: .value("Date", point.date), y: .value("Fatigue", point.value))
                .foregroundStyle(Theme.accentValue)
                .interpolationMethod(.catmullRom)
                .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
              PointMark(x: .value("Date", point.date), y: .value("Fatigue", point.value))
                .foregroundStyle(Theme.accentValue)
                .symbolSize(40)
            }
            .chartYScale(domain: 0...10)
            .chartXAxis {
              AxisMarks(values: .automatic(desiredCount: 4)) {
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel(format: .dateTime.month(.abbreviated).day().locale(L10n.locale))
                  .font(.forge(11, .medium)).foregroundStyle(Theme.textTertiary)
              }
            }
            .chartYAxis {
              AxisMarks(position: .trailing) {
                AxisGridLine().foregroundStyle(Theme.track)
                AxisValueLabel().font(.forge(11, .medium)).foregroundStyle(Theme.textTertiary)
              }
            }
            .frame(height: 160)
          } else {
            HStack(spacing: 10) {
              Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(Theme.textTertiary)
              Text(
                "Record at least two check-ins to draw a trend. Missing days stay unknown, not zero."
              ).forgeLabel()
            }
            .frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()

        recoveryStateCard
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Recovery")
  }

  @ViewBuilder
  private var recoveryStateCard: some View {
    let content: (symbol: String, title: String, detail: String, color: Color) =
      switch presentation {
      case .empty:
        (
          "questionmark.circle", "No recovery evidence yet",
          "Add a check-in when useful. Missing data is not treated as poor recovery.",
          Theme.textTertiary
        )
      case .collecting(let count, let days):
        (
          "hourglass", "Collecting recovery evidence",
          "\(count) of at least \(RecoveryPresentationPolicy.minimumAssessmentSamples) check-ins recorded in the last \(days) days. No training directive is generated yet.",
          Theme.metricTime
        )
      case .assessed(let summary, let count, let days):
        (
          "checkmark.circle.fill", "Based on recorded check-ins",
          "\(summary) Coverage: \(count) check-ins in \(days) days.", Theme.metricSets
        )
      }
    HStack(alignment: .top, spacing: 12) {
      Image(systemName: content.symbol)
        .font(.system(size: 18, weight: .semibold))
        .foregroundStyle(content.color)
        .frame(width: 40, height: 40)
        .background(Circle().fill(content.color.opacity(0.12)))
      VStack(alignment: .leading, spacing: 4) {
        Text(content.title).forgeBodyStrong()
        Text(content.detail).forgeLabel()
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
    .accessibilityElement(children: .combine)
  }

  private func average(_ values: [Double]) -> Double? {
    values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
  }

  private func format(_ value: Double?, suffix: String = "") -> String {
    guard let value else { return "—" }
    return String(format: "%.1f", value) + suffix
  }
}

private struct RecoveryMetricTile: View {
  let symbol: String
  let value: String
  let label: String
  let detail: String

  var body: some View {
    HStack(alignment: .top, spacing: 10) {
      Image(systemName: symbol)
        .font(.system(size: 15, weight: .semibold))
        .foregroundStyle(Theme.metricTime)
        .frame(width: 32, height: 32)
        .background(Circle().fill(Theme.metricTime.opacity(0.12)))
      VStack(alignment: .leading, spacing: 3) {
        Text(value).forge(22, .bold).monospacedDigit()
        Text(label).forgeBodyStrong().fixedSize(horizontal: false, vertical: true)
        Text(detail).forgeCaption().fixedSize(horizontal: false, vertical: true)
      }
      Spacer(minLength: 0)
    }
    .frame(maxWidth: .infinity, minHeight: 92, alignment: .leading)
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface)
    )
    .accessibilityElement(children: .combine)
  }
}
