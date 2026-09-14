import SwiftUI
import ForgeCore

struct WeekStrip: View {
  let sessions: [WorkoutSession]
  let plannedDays: Int

  var body: some View {
    VStack(spacing: 12) {
      HStack(spacing: 0) {
        ForEach(weekCells.indices, id: \.self) { index in
          dayCell(weekCells[index])
        }
      }
      Text("\(completed) of \(plannedDays) sessions this week")
        .font(.caption)
        .foregroundStyle(.secondary)
        .monospacedDigit()
        .frame(maxWidth: .infinity, alignment: .leading)
    }
  }

  private struct Cell {
    let initial: String
    let isToday: Bool
    let isDone: Bool
  }

  private var weekCells: [Cell] {
    let cal = Calendar.current
    guard let week = cal.dateInterval(of: .weekOfYear, for: .now) else { return [] }
    let doneDays = Set(sessions.filter(\.completed).map { cal.startOfDay(for: $0.date) })
    return (0..<7).map { offset in
      let date = cal.date(byAdding: .day, value: offset, to: week.start) ?? week.start
      let symbol = cal.veryShortWeekdaySymbols[max(0, cal.component(.weekday, from: date) - 1)]
      return Cell(
        initial: String(symbol.prefix(1)).uppercased(),
        isToday: cal.isDateInToday(date),
        isDone: doneDays.contains(cal.startOfDay(for: date)))
    }
  }

  private var completed: Int {
    let cal = Calendar.current
    guard let week = cal.dateInterval(of: .weekOfYear, for: .now) else { return 0 }
    return sessions.filter { $0.completed && week.contains($0.date) }.count
  }

  private func dayCell(_ cell: Cell) -> some View {
    VStack(spacing: 6) {
      ZStack {
        if cell.isDone {
          Circle().fill(Theme.accent).frame(width: 28, height: 28)
          Image(systemName: "checkmark")
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
        } else {
          Circle()
            .stroke(cell.isToday ? Theme.accent : Color(.tertiarySystemFill), lineWidth: 2)
            .frame(width: 28, height: 28)
        }
      }
      Text(cell.initial)
        .font(.caption2)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity)
  }
}
