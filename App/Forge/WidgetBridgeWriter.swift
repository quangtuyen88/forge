import Foundation
import ForgeCore

enum WidgetBridgeWriter {
  static func write(day: PlannedDay?, streakWeeks: Int, weekSets: Int, weekTarget: Int, checkedIn: Bool) {
    let sets = day?.exercises.reduce(0) { $0 + $1.sets } ?? 0
    WidgetBridge.save(WidgetSnapshot(
      dayName: day?.name ?? "Rest",
      minutes: Int((Double(sets) * 2.5 / 5).rounded() * 5),
      exercises: day?.exercises.count ?? 0,
      streakWeeks: streakWeeks,
      weekSets: weekSets,
      weekTarget: weekTarget,
      checkedIn: checkedIn,
      updated: .now))
  }
}
