import SwiftUI
import ForgeCore

struct WeekStrip: View {
  let sessions: [WorkoutSession]
  let plannedDays: Int
  var todayProgress: Double? = nil
  var appeared: Bool = true
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  static func completed(_ sessions: [WorkoutSession]) -> Int {
    let calendar = TrainingMetrics.reportingCalendar()
    let week = TrainingMetrics.reportingWeek(containing: .now, calendar: calendar)
    return sessions.filter { $0.completed && TrainingMetrics.contains(week, $0.date) }.count
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(Array(weekCells.enumerated()), id: \.element.id) { index, cell in
        dayCell(cell, index: index)
      }
    }
  }

  private struct Cell: Identifiable {
    let id: Date
    let initial: String
    let isToday: Bool
    let isDone: Bool
    let isFuture: Bool
  }

  private var weekCells: [Cell] {
    let cal = TrainingMetrics.reportingCalendar()
    var symbolCal = Calendar(identifier: .gregorian)
    symbolCal.locale = L10n.locale
    let week = TrainingMetrics.reportingWeek(containing: .now, calendar: cal)
    let today = cal.startOfDay(for: .now)
    let doneDays = Set(sessions.filter(\.completed).map { cal.startOfDay(for: $0.date) })
    return (0..<7).map { offset in
      let date = cal.date(byAdding: .day, value: offset, to: week.start) ?? week.start
      let symbol = symbolCal.veryShortWeekdaySymbols[max(0, cal.component(.weekday, from: date) - 1)]
      return Cell(
        id: cal.startOfDay(for: date),
        initial: symbol.uppercased(),
        isToday: cal.isDateInToday(date),
        isDone: doneDays.contains(cal.startOfDay(for: date)),
        isFuture: cal.startOfDay(for: date) > today)
    }
  }

  private func dayCell(_ cell: Cell, index: Int) -> some View {
    let delay = 0.3 + Double(index) * 0.06
    return VStack(spacing: 6) {
      Group {
        if cell.isDone {
          RingView(progress: appeared ? 1 : 0, lineWidth: 5, color: Theme.positive, delay: delay)
        } else if cell.isToday {
          RingView(progress: appeared ? (todayProgress ?? 0) : 0, lineWidth: 5, delay: delay)
        } else {
          RingView(progress: 0, lineWidth: 5)
        }
      }
      .overlay {
        if cell.isDone {
          Image(systemName: "checkmark")
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(Theme.positive)
            .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
            .opacity(appeared ? 1 : 0)
            .animation(
              reduceMotion ? .easeOut(duration: 0.2) : .spring(duration: 0.35, bounce: 0.3).delay(0.4 + delay),
              value: appeared)
        }
      }
      .frame(width: 30, height: 30)
      .opacity(cell.isFuture ? 0.45 : 1)
      if cell.isToday {
        Text(cell.initial)
          .forge(11, .semibold)
          .lineLimit(1)
          .minimumScaleFactor(0.6)
          .foregroundStyle(Theme.onAccent)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(Capsule().fill(Theme.accent))
      } else {
        Text(cell.initial)
          .forgeCaption()
          .lineLimit(1)
          .minimumScaleFactor(0.6)
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(Self.cellLabel(cell))
  }

  /// Built through the catalog rather than interpolating bare English words, which shipped
  /// "done" / "today" / "no session" untranslated into every locale.
  private static func cellLabel(_ cell: Cell) -> String {
    let day = cell.id.formatted(.dateTime.weekday(.wide).locale(L10n.locale))
    if cell.isDone { return String(localized: "\(day), workout done", bundle: L10n.bundle) }
    if cell.isToday { return String(localized: "\(day), today, no workout yet", bundle: L10n.bundle) }
    if cell.isFuture { return String(localized: "\(day), upcoming", bundle: L10n.bundle) }
    return String(localized: "\(day), no workout", bundle: L10n.bundle)
  }
}
