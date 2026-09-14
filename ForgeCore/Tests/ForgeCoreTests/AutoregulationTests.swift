import XCTest
@testable import ForgeCore

final class AutoregulationTests: XCTestCase {
  let bench = ExerciseDB.find("barbell_bench")!
  let squat = ExerciseDB.find("back_squat")!

  func perf(_ exercise: Exercise, _ logs: [SetLog], range: ClosedRange<Int> = 8...12, target: Double = 8) -> ExercisePerformance {
    ExercisePerformance(exercise: exercise, repRange: range, targetRPE: target, sets: logs)
  }

  func log(_ reps: Int, _ rpe: Double) -> SetLog { SetLog(weightKg: 100, reps: reps, rpe: rpe) }

  let sixDay = ProfileInput(goal: .hypertrophy, daysPerWeek: 6, sessionLength: .m60, equipment: [.barbell, .dumbbell, .machine, .cable])

  func chestSets(_ week: [PlannedDay]) -> Int {
    week.reduce(0) { $0 + $1.exercises.filter { $0.exercise.primary == .chest }.reduce(0) { $0 + $1.sets } }
  }

  func testEasyAddsSet() {
    let p = perf(bench, [log(12, 8), log(12, 8), log(12, 8)])
    XCTAssertEqual(Autoregulation.signals([p])[.chest], .easy)
    XCTAssertEqual(Autoregulation.volumeDelta([p])[.chest], 1)
  }

  func testOvershootRPERemovesSet() {
    let p = perf(bench, [log(12, 8), log(12, 9)])
    XCTAssertEqual(Autoregulation.signals([p])[.chest], .overreached)
    XCTAssertEqual(Autoregulation.volumeDelta([p])[.chest], -1)
  }

  func testUnderRangeRemovesSet() {
    let p = perf(bench, [log(6, 8), log(12, 8)])
    XCTAssertEqual(Autoregulation.signals([p])[.chest], .overreached)
    XCTAssertEqual(Autoregulation.volumeDelta([p])[.chest], -1)
  }

  func testSorenessBlocksIncreaseOnly() {
    let easy = perf(bench, [log(12, 8), log(12, 8), log(12, 8)])
    XCTAssertNil(Autoregulation.volumeDelta([easy], soreness: 4)[.chest])
    let hard = perf(bench, [log(12, 8), log(12, 9)])
    XCTAssertEqual(Autoregulation.volumeDelta([hard], soreness: 4)[.chest], -1)
  }

  func testSingleSetIsOnTarget() {
    let p = perf(squat, [log(12, 8)])
    XCTAssertEqual(Autoregulation.signals([p])[.quads], .onTarget)
    XCTAssertNil(Autoregulation.volumeDelta([p])[.quads])
  }

  func testNonCountingSetsIgnored() {
    let p = perf(bench, [log(12, 5), log(12, 5)])
    XCTAssertNil(Autoregulation.signals([p])[.chest])
  }

  func testOverreachedWinsAcrossExercises() {
    let easyBench = perf(bench, [log(12, 8), log(12, 8)])
    let underFly = perf(ExerciseDB.find("cable_fly")!, [log(10, 8)], range: 12...15)
    XCTAssertEqual(Autoregulation.signals([easyBench, underFly])[.chest], .overreached)
  }

  func testProgramWeekAppliesDelta() {
    XCTAssertLessThan(
      chestSets(Program.week(2, profile: sixDay)),
      chestSets(Program.week(2, profile: sixDay, volumeDelta: [.chest: 1]))
    )
  }

  func testDeltaClampsAtMRV() {
    XCTAssertEqual(
      chestSets(Program.week(2, profile: sixDay, volumeDelta: [.chest: 50])),
      chestSets(Program.week(2, profile: sixDay, volumeDelta: [.chest: 11]))
    )
  }

  func testDeloadIgnoresDelta() {
    XCTAssertEqual(
      Program.week(6, profile: sixDay, volumeDelta: [.chest: 5]),
      Program.week(6, profile: sixDay)
    )
  }

  func testWeeklySetsMatchTarget() {
    XCTAssertEqual(
      chestSets(Program.week(2, profile: sixDay)),
      Mesocycle.targetSets(muscle: .chest, week: 2, recoveryReduced: false)!
    )
    let fourDay = ProfileInput(goal: .hypertrophy, daysPerWeek: 4, sessionLength: .m60, equipment: Set(Equipment.allCases))
    let backSets = Program.week(3, profile: fourDay).reduce(0) { total, day in
      total + day.exercises.filter { $0.exercise.primary == .back }.reduce(0) { $0 + $1.sets }
    }
    XCTAssertEqual(backSets, Mesocycle.targetSets(muscle: .back, week: 3, recoveryReduced: false)!)
  }

  func testRampIsVisibleEveryWeek() {
    var previous = -1
    for w in 1...5 {
      let sets = chestSets(Program.week(w, profile: sixDay))
      XCTAssertGreaterThan(sets, previous, "week \(w)")
      previous = sets
    }
  }

  func testShortSessionsHitTarget() {
    let p = ProfileInput(goal: .hypertrophy, daysPerWeek: 4, sessionLength: .m45, equipment: Set(Equipment.allCases))
    let week = Program.week(1, profile: p)
    let chest = week.reduce(0) { total, day in
      total + day.exercises.filter { $0.exercise.primary == .chest }.reduce(0) { $0 + $1.sets }
    }
    let back = week.reduce(0) { total, day in
      total + day.exercises.filter { $0.exercise.primary == .back }.reduce(0) { $0 + $1.sets }
    }
    XCTAssertEqual(chest, 8)
    XCTAssertEqual(back, 10)
  }
}
