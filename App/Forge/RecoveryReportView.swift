import SwiftUI
import SwiftData
import Charts
import ForgeCore

struct RecoveryReportView: View {
  @Query(sort: \CheckIn.date) private var checkIns: [CheckIn]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]

  private var week: [CheckIn] {
    checkIns.filter { $0.date > Date.now.addingTimeInterval(-7 * 86400) }
  }

  private var weekSessions: [WorkoutSession] {
    sessions.filter { $0.completed && $0.date > Date.now.addingTimeInterval(-7 * 86400) }
  }

  private var avgSleepHours: Double { week.isEmpty ? 0 : week.reduce(0.0) { $0 + $1.sleepHours } / Double(week.count) }
  private var avgSleep: Double { week.isEmpty ? 0 : Double(week.reduce(0) { $0 + $1.sleep }) / Double(week.count) }
  private var avgSoreness: Double { week.isEmpty ? 0 : Double(week.reduce(0) { $0 + $1.soreness }) / Double(week.count) }
  private var avgEnergy: Double { week.isEmpty ? 0 : Double(week.reduce(0) { $0 + $1.energy }) / Double(week.count) }

  private var fatiguePoints: [(date: Date, value: Double)] {
    week.map { (date: $0.date, value: Double($0.soreness + (5 - $0.energy))) }
      .sorted { $0.date < $1.date }
  }

  private var coachLine: String {
    if week.isEmpty { return String(localized: "No check-ins this week. Log one tomorrow morning.", bundle: L10n.bundle) }
    if avgSoreness >= 4 { return String(localized: "Soreness is running high. Deload is doing its job / consider one.", bundle: L10n.bundle) }
    if avgEnergy <= 2.5 { return String(localized: "Energy is low. Keep RPE honest and bank sleep.", bundle: L10n.bundle) }
    return String(localized: "Recovery looks solid. Train hard.", bundle: L10n.bundle)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.groupGap) {
        VStack(alignment: .leading, spacing: 12) {
          Text("Last 7 days").forgeSection()
          LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            StatTile(symbol: "moon.zzz", value: String(format: "%.1f h", avgSleepHours), label: String(localized: "sleep", bundle: L10n.bundle))
            StatTile(symbol: "sparkles", value: String(format: "%.1f", avgSleep), label: String(localized: "sleep quality", bundle: L10n.bundle))
            StatTile(symbol: "flame", value: String(format: "%.1f", avgSoreness), label: String(localized: "soreness", bundle: L10n.bundle))
            StatTile(symbol: "bolt.fill", value: String(format: "%.1f", avgEnergy), label: String(localized: "energy", bundle: L10n.bundle))
            StatTile(symbol: "dumbbell", value: "\(weekSessions.count)", label: String(localized: "sessions", bundle: L10n.bundle))
            StatTile(symbol: "square.stack.3d.up.fill", value: "\(weekSessions.flatMap(\.sets).count)", label: String(localized: "sets", bundle: L10n.bundle))
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()

        VStack(alignment: .leading, spacing: 12) {
          HStack(alignment: .firstTextBaseline) {
            Text("Fatigue").forgeSection()
            Spacer()
            Text("soreness + (5 − energy)").forgeCaption()
          }
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
          .frame(height: 140)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()

        Text(coachLine)
          .forgeLabel()
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Recovery")
  }
}
