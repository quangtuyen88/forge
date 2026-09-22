import SwiftUI
import ForgeCore

struct WeekStrip: View {
  let sessions: [WorkoutSession]
  let plannedDays: Int
  var todayProgress: Double? = nil

  static func completed(_ sessions: [WorkoutSession]) -> Int {
    let cal = Calendar.current
    guard let week = cal.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
    return sessions.filter { $0.completed && week.contains($0.date) }.count
  }

  var body: some View {
    HStack(spacing: 0) {
      ForEach(weekCells) { cell in
        dayCell(cell)
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
    let cal = Calendar.current
    var symbolCal = Calendar(identifier: .gregorian)
    symbolCal.locale = L10n.locale
    guard let week = cal.dateInterval(of: .weekOfYear, for: .now) else { return [] }
    let today = cal.startOfDay(for: .now)
    let doneDays = Set(sessions.filter(\.completed).map { cal.startOfDay(for: $0.date) })
    return (0..<7).map { offset in
      let date = cal.date(byAdding: .day, value: offset, to: week.start) ?? week.start
      let symbol = symbolCal.veryShortWeekdaySymbols[max(0, cal.component(.weekday, from: date) - 1)]
      return Cell(
        id: cal.startOfDay(for: date),
        initial: String(symbol.prefix(1)).uppercased(),
        isToday: cal.isDateInToday(date),
        isDone: doneDays.contains(cal.startOfDay(for: date)),
        isFuture: cal.startOfDay(for: date) > today)
    }
  }

  private func dayCell(_ cell: Cell) -> some View {
    VStack(spacing: 6) {
      Group {
        if cell.isDone {
          RingView(progress: 1, lineWidth: 5, color: Theme.positive)
        } else if cell.isToday {
          RingView(progress: todayProgress ?? 0, lineWidth: 5)
        } else {
          RingView(progress: 0, lineWidth: 5)
        }
      }
      .frame(width: 30, height: 30)
      .opacity(cell.isFuture ? 0.45 : 1)
      if cell.isToday {
        Text(cell.initial)
          .forge(11, .semibold)
          .foregroundStyle(Theme.onAccent)
          .padding(.horizontal, 7)
          .padding(.vertical, 2)
          .background(Capsule().fill(Theme.accent))
      } else {
        Text(cell.initial)
          .forgeCaption()
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
