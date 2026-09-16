#if DEBUG
import Foundation
import SwiftData
import ForgeCore

/// Debug-only demo seed: `xcrun simctl launch <udid> app.regulift --seed-demo` on a fresh
/// install skips onboarding and fills a realistic week-4 block for App Store screenshots.
/// Add `--red-days` for the fatigue variant: two red check-ins (sleep 4.5 h, soreness 5)
/// plus a volume spike in the last week push both fatigue scores past 80, so Today shows
/// the rest-day card with the early-deload offer. Compiled out of Release builds together
/// with its call site in ForgeApp.
enum DemoSeed {
  static func run(in context: ModelContext) {
    guard (try? context.fetchCount(FetchDescriptor<UserProfile>())) ?? 0 == 0 else { return }
    let redDays = ProcessInfo.processInfo.arguments.contains("--red-days")

    let cal = Calendar.current
    func dayAgo(_ days: Int, hour: Int = 18, minute: Int = 0) -> Date {
      cal.date(bySettingHour: hour, minute: minute, second: 0, of: cal.date(byAdding: .day, value: -days, to: .now) ?? .now) ?? .now
    }

    // 1. Profile — Kai, hypertrophy, intermediate, 3 days/week, 60 min, kg, dark, subscribed.
    let profile = UserProfile(
      goal: .hypertrophy, experience: .intermediate, daysPerWeek: 3, sessionMinutes: 60,
      equipment: [.barbell, .dumbbell, .cable], injuryFlags: [.shoulder],
      recoveryReduced: false, bodyweightKg: 82, usesLb: false,
      startingLoads: ["barbell_bench": 70, "back_squat": 100, "deadlift": 120,
                      "overhead_press": 45, "barbell_row": 60, "lat_pulldown": 55])
    profile.mesoStart = dayAgo(24, hour: cal.component(.hour, from: .now), minute: cal.component(.minute, from: .now))
    profile.trialStartedAt = dayAgo(20, hour: 12)
    profile.nextDayIndex = 10
    profile.theme = "dark"
    context.insert(profile)
    UserDefaults.standard.set("kai", forKey: Coach.storageKey)
    UserDefaults.standard.set(true, forKey: "coachConsent")

    // 2. Sessions — 10 completed, 3x/week rhythm ending yesterday, cycling Full A/B/C.
    // Loads rise ~2.5 % per week. Last week: 16 sets/session normally (readiness ~75);
    // with --red-days 24 sets + RPE-9.5 grinders so the acute:chronic set ratio clears 1.5
    // and missed-RPE fires — both fatigue scores pass 80 (TodayView.offersEarlyDeload).
    let offsets = [22, 19, 17, 15, 12, 10, 8, 5, 3, 1]
    let dayNames = ["Full A", "Full B", "Full C"]
    let blocks = [
      ["barbell_bench", "back_squat", "barbell_row", "lat_pulldown"],
      ["deadlift", "landmine_press", "barbell_curl", "db_calf_raise"],
      ["back_squat", "barbell_bench", "barbell_row", "lat_pulldown"],
    ]
    let baseLoads = ["barbell_bench": 70.0, "back_squat": 100.0, "deadlift": 120.0,
                     "overhead_press": 45.0, "barbell_row": 60.0, "lat_pulldown": 55.0,
                     "landmine_press": 30.0, "barbell_curl": 25.0, "db_calf_raise": 40.0]
    let sleeps = [7.0, 7.3, 7.6]

    for (i, offset) in offsets.enumerated() {
      let sessionDate = dayAgo(offset)
      let session = WorkoutSession(date: sessionDate, dayName: dayNames[i % 3], week: i / 3 + 1, completed: true)
      context.insert(session)

      let factor = 1.0 + 0.025 * Double(i / 3) + (i == 9 ? 0.025 : 0) // yesterday rides a bit higher
      let setsPerExercise = i >= 7 ? (redDays ? 6 : 4) : 3
      let reps = i >= 7 ? 10 : 8
      for (slot, exerciseID) in blocks[i % 3].enumerated() {
        var load = (baseLoads[exerciseID] ?? 50) * factor
        if i == 9 && exerciseID == "barbell_bench" { load += 5 } // PR top set beats every earlier bench e1RM
        for setIndex in 0..<setsPerExercise {
          let topSet = setIndex == setsPerExercise - 1
          let rpe: Double = redDays && i >= 7 && topSet ? 9.5 : 7.0 + Double(slot) * 0.5
          let weight = (load / 2.5).rounded() * 2.5
          let set = LoggedSet(
            exerciseID: exerciseID, setIndex: setIndex, weightKg: weight, reps: reps,
            rpe: min(rpe, 9.5), targetRPE: 8,
            loggedAt: sessionDate.addingTimeInterval(Double(slot * setsPerExercise + setIndex) * 150))
          set.session = session
          context.insert(set)
        }
      }

      // 3. Check-ins — one per training day; with --red-days yesterday flips red.
      let red = redDays && offset <= 1
      context.insert(CheckIn(
        date: dayAgo(offset, hour: 8),
        sleep: red ? 1 : 3, soreness: red ? 5 : 2, energy: red ? 1 : 4,
        sleepHours: red ? 4.5 : sleeps[i % 3]))
    }
    // Today's check-in: normal (sleep 7.0) or red (sleep 4.5), same as the streak requires.
    context.insert(CheckIn(
      date: dayAgo(0, hour: 8),
      sleep: redDays ? 1 : 3, soreness: redDays ? 5 : 2, energy: redDays ? 1 : 4,
      sleepHours: redDays ? 4.5 : 7.0))

    // 4. Measurements — 82.0 → 81.6 → 81.2 kg.
    context.insert(BodyMeasurement(date: dayAgo(21, hour: 8), weightKg: 82.0))
    context.insert(BodyMeasurement(date: dayAgo(10, hour: 8), weightKg: 81.6))
    context.insert(BodyMeasurement(date: dayAgo(2, hour: 8), weightKg: 81.2))

    try? context.save()
  }
}
#endif
