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
                      "overhead_press": 45, "bent_row": 60, "lat_pulldown": 55])
    profile.mesoStart = dayAgo(24, hour: cal.component(.hour, from: .now), minute: cal.component(.minute, from: .now))
    profile.trialStartedAt = dayAgo(20, hour: 12)
    profile.nextDayIndex = 10
    profile.theme = "system"
    context.insert(profile)
    UserDefaults.standard.set("kai", forKey: Coach.storageKey)
    UserDefaults.standard.set(true, forKey: "coachConsent")

    if ProcessInfo.processInfo.arguments.contains("--seed-trends") {
      seedTrends(in: context, profile: profile, dayAgo: dayAgo)
      try? context.save()
      return
    }

    // 2. Sessions — 10 completed, 3x/week rhythm ending yesterday, cycling Full A/B/C.
    // Loads rise ~2.5 % per week. Last week: 16 sets/session normally (readiness ~75);
    // with --red-days 24 sets + RPE-9.5 grinders so the acute:chronic set ratio clears 1.5
    // and missed-RPE fires — both fatigue scores pass 80 (TodayView.offersEarlyDeload).
    let offsets = [22, 19, 17, 15, 12, 10, 8, 5, 3, 1]
    let dayNames = ["Full A", "Full B", "Full C"]
    let blocks = [
      ["barbell_bench", "back_squat", "bent_row", "lat_pulldown"],
      ["deadlift", "landmine_press", "barbell_curl", "db_calf_raise"],
      ["back_squat", "barbell_bench", "bent_row", "lat_pulldown"],
    ]
    let baseLoads = ["barbell_bench": 70.0, "back_squat": 100.0, "deadlift": 120.0,
                     "overhead_press": 45.0, "bent_row": 60.0, "lat_pulldown": 55.0,
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
            loggedAt: sessionDate.addingTimeInterval(Double(slot * setsPerExercise + setIndex) * 150),
            // Seeded sets stand for a lifter who rated their work. Without this every demo
            // screen reads "effort not recorded", which is true of the data and false about
            // the lifter this fixture is meant to portray.
            effortReported: true)
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

    // 5. --done-today: Full B finished today, 14 of 16 sets, so Today shows the goal card.
    if ProcessInfo.processInfo.arguments.contains("--done-today") {
      let start = max(cal.startOfDay(for: .now), Date.now.addingTimeInterval(-70 * 60))
      let session = WorkoutSession(date: start, dayName: dayNames[1], week: 4, completed: true)
      session.plannedSetCount = 16
      context.insert(session)
      for (slot, exerciseID) in blocks[1].enumerated() {
        for setIndex in 0..<(slot == 3 ? 2 : 4) {
          let set = LoggedSet(
            exerciseID: exerciseID, setIndex: setIndex,
            weightKg: ((baseLoads[exerciseID] ?? 50) * 1.1 / 2.5).rounded() * 2.5, reps: 10,
            rpe: 8, targetRPE: 8,
            loggedAt: start.addingTimeInterval(Double(slot * 4 + setIndex) * 240),
            effortReported: true)
          set.session = session
          context.insert(set)
        }
      }
      profile.nextDayIndex = 11
      profile.reminderHour = 18
      let fuel = NutritionProfile(
        sex: .male, age: 32, heightCm: 180, activity: .moderate, phase: .recomp)
      fuel.kcal = 2700
      fuel.proteinG = 160
      fuel.carbsG = 300
      fuel.fatG = 80
      context.insert(fuel)
      let morning = cal.startOfDay(for: .now)
      context.insert(
        FoodEntry(
          date: morning.addingTimeInterval(8 * 3600), meal: .breakfast, itemID: "demo-oats",
          name: "Oats with whey", grams: 350, kcal: 620, proteinG: 48, carbsG: 80, fatG: 14))
      context.insert(
        FoodEntry(
          date: morning.addingTimeInterval(13 * 3600), meal: .lunch,
          itemID: "demo-chicken-rice", name: "Chicken and rice", grams: 450, kcal: 720,
          proteinG: 54, carbsG: 90, fatG: 12))
    }

    try? context.save()
  }

  // --seed-demo --seed-trends: nine weeks of three Full A/B/C sessions for the lift trend screens.
  private static func seedTrends(in context: ModelContext, profile: UserProfile, dayAgo: (Int, Int, Int) -> Date) {
    let dayNames = ["Full A", "Full B", "Full C"]
    let liftsByDay: [String: [String]] = [
      "Full A": ["back_squat", "barbell_bench", "bent_row", "lat_pulldown"],
      "Full B": ["deadlift", "overhead_press", "pull_up", "hip_thrust"],
      "Full C": ["leg_press", "dips", "lateral_raise", "seated_cable_row"],
    ]
    let targets: [String: [Double]] = [
      "deadlift": [156, 158, 161, 163, 165, 166, 169, 172, 175],
      "back_squat": [127, 128, 131, 129, 135, 134, 139, 138, 142],
      "hip_thrust": [132, 133, 135, 134, 136, 137, 136, 137, 138],
      "leg_press": [210, 212, 210, 209, 211, 210, 212, 211, 210],
      "barbell_bench": [90, 91, 92, 93, 94, 95, 96, 97, 98],
      "overhead_press": [57, 58, 58, 59, 60, 60, 61, 60, 61],
      "dips": [31, 32, 32, 33, 34, 33, 34, 33, 34],
      "lateral_raise": [14, 14, 15, 14, 14, 15, 14, 14, 14],
      "lat_pulldown": [71, 72, 73, 74, 75, 76, 76, 77, 78],
      "bent_row": [86, 87, 88, 90, 91, 92, 91, 92, 92],
      "seated_cable_row": [75, 76, 77, 78, 79, 80, 79, 80, 80],
      "pull_up": [20, 21, 20, 20, 19, 19, 19, 18, 18],
    ]

    func roundTo1_25(_ x: Double) -> Double { (x / 1.25).rounded() * 1.25 }

    for k in 0..<9 {
      let base = 7 * (8 - k)
      let week = k < 6 ? k + 1 : k - 5
      let offsets = [base + 6, base + 4, base + 1] // oldest first
      for (position, offset) in offsets.enumerated() {
        let dayName = dayNames[position]
        let sessionDate = dayAgo(offset, 18, 0)
        let session = WorkoutSession(date: sessionDate, dayName: dayName, week: week, completed: true)
        context.insert(session)
        for (slot, exerciseID) in (liftsByDay[dayName] ?? []).enumerated() {
          let target = targets[exerciseID]?[k] ?? 0
          let topWeight = roundTo1_25(target / 1.2)
          for setIndex in 0..<3 {
            let weight = setIndex == 2 ? topWeight : roundTo1_25(topWeight * 0.9)
            let set = LoggedSet(
              exerciseID: exerciseID, setIndex: setIndex, weightKg: weight,
              reps: setIndex == 2 ? 6 : 8, rpe: setIndex == 2 ? 8.5 : 7.5, targetRPE: 8,
              loggedAt: sessionDate.addingTimeInterval(Double(slot * 3 + setIndex) * 150),
              effortReported: true)
            set.session = session
            context.insert(set)
          }
        }
      }
    }

    profile.mesoStart = dayAgo(20, 18, 0) // k = 6 first session: base 14 + 6 = 20 days ago
    profile.nextDayIndex = 27
  }
}
#endif
