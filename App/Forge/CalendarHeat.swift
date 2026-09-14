import SwiftUI

struct CalendarHeat: View {
  let sessions: [WorkoutSession]
  var weeks: Int = 12

  private let gap: CGFloat = 3

  var body: some View {
    Canvas { context, size in
      let pitch = size.width / CGFloat(weeks)
      let cell = pitch - gap
      let labelBand = pitch
      let cal = Calendar(identifier: .iso8601)
      let today = cal.startOfDay(for: .now)
      guard let currentWeekStart = cal.dateInterval(of: .weekOfYear, for: today)?.start else { return }

      var countedByDay: [Date: Int] = [:]
      for session in sessions {
        let sets = session.sets.filter { $0.rpe >= 6 }.count
        guard sets > 0 else { continue }
        countedByDay[cal.startOfDay(for: session.date), default: 0] += sets
      }

      var prevMonth = -1
      for w in 0..<weeks {
        guard let weekStart = cal.date(byAdding: .weekOfYear, value: w - (weeks - 1), to: currentWeekStart) else { continue }
        let x = CGFloat(w) * pitch
        let month = cal.component(.month, from: weekStart)
        if month != prevMonth {
          let initial = String(cal.monthSymbols[month - 1].prefix(1))
          context.draw(
            Text(initial).forge(11, .medium).foregroundStyle(Theme.textTertiary),
            at: CGPoint(x: x + cell / 2, y: labelBand / 2))
        }
        for d in 0..<7 {
          guard let date = cal.date(byAdding: .day, value: d, to: weekStart), date <= today else { continue }
          let sets = countedByDay[date] ?? 0
          let color = sets > 0
            ? Theme.rampColor(min(Double(sets) / 20, 1))
            : Theme.track
          let rect = CGRect(x: x, y: labelBand + CGFloat(d) * pitch, width: cell, height: cell)
          context.fill(
            Path(roundedRect: rect, cornerSize: CGSize(width: cell / 4, height: cell / 4), style: .continuous),
            with: .color(color))
        }
        prevMonth = month
      }
    }
    .aspectRatio(CGFloat(weeks) / 8, contentMode: .fit)
    .frame(maxWidth: .infinity)
  }
}

#Preview {
  let cal = Calendar(identifier: .iso8601)
  var sessions: [WorkoutSession] = []
  for day in 0..<60 {
    let date = cal.date(byAdding: .day, value: -day, to: .now)!
    let session = WorkoutSession(date: date, dayName: "Full A", week: 1, completed: true)
    let count = day % 3 == 0 ? 0 : (day % 7 + 4)
    for i in 0..<max(count, 1) {
      if count > 0 {
        session.sets.append(LoggedSet(exerciseID: "barbell_bench", setIndex: i, weightKg: 80, reps: 8, rpe: 8, targetRPE: 8, loggedAt: date))
      }
    }
    if count > 0 { sessions.append(session) }
  }
  return CalendarHeat(sessions: sessions).padding()
}
