import XCTest
@testable import ForgeCore

final class ProgramTests: XCTestCase {
  func makeProfile(days: Int, session: SessionLength = .m60, goal: Goal = .hypertrophy,
                   flags: Set<InjuryFlag> = []) -> ProfileInput {
    ProfileInput(goal: goal, daysPerWeek: days, sessionLength: session,
                 equipment: Set(Equipment.allCases), injuryFlags: flags)
  }

  func testSplits() {
    XCTAssertEqual(Program.split(daysPerWeek: 3), ["Full A", "Full B", "Full C"])
    XCTAssertEqual(Program.split(daysPerWeek: 4), ["Upper", "Lower", "Upper", "Lower"])
    XCTAssertEqual(Program.split(daysPerWeek: 5), ["Upper", "Lower", "Push", "Pull", "Legs"])
    XCTAssertEqual(Program.split(daysPerWeek: 6), ["Push", "Pull", "Legs", "Push", "Pull", "Legs"])
  }

  func testWeekShapesForAllSplits() {
    for days in 3...6 {
      let p = makeProfile(days: days)
      let week = Program.week(1, profile: p)
      XCTAssertEqual(week.count, days)
      for day in week {
        XCTAssertGreaterThanOrEqual(day.exercises.count, 1, day.name)
        XCTAssertLessThanOrEqual(day.exercises.count, p.sessionLength.maxExercises, day.name)
        for pe in day.exercises {
          XCTAssertTrue(p.equipment.contains(pe.exercise.equipment), pe.exercise.id)
          XCTAssertGreaterThanOrEqual(pe.sets, 2, pe.exercise.id)
          XCTAssertLessThanOrEqual(pe.repRange.lowerBound, pe.repRange.upperBound, pe.exercise.id)
          XCTAssertEqual(pe.targetRPE, 8, pe.exercise.id)
        }
      }
    }
  }

  func testShoulderSubstitution() {
    for days in 3...6 {
      let p = makeProfile(days: days, flags: [.shoulder])
      for day in Program.week(1, profile: p) {
        for pe in day.exercises {
          XCTAssertNotEqual(pe.exercise.id, "barbell_bench", day.name)
          XCTAssertNotEqual(pe.exercise.id, "overhead_press", day.name)
          XCTAssertNotEqual(pe.exercise.id, "dips", day.name)
        }
      }
    }
  }

  func testDeloadWeekHalvesSets() {
    let p = makeProfile(days: 4)
    let week5 = Program.week(5, profile: p)
    let week6 = Program.week(6, profile: p)
    for day in week6 {
      for pe in day.exercises { XCTAssertEqual(pe.targetRPE, Mesocycle.deloadRPECap, pe.exercise.id) }
    }
    for (d5, d6) in zip(week5, week6) {
      XCTAssertEqual(d5.name, d6.name)
      XCTAssertEqual(d5.exercises.count, d6.exercises.count)
      for (e5, e6) in zip(d5.exercises, d6.exercises) {
        XCTAssertEqual(e5.exercise.id, e6.exercise.id)
        XCTAssertLessThanOrEqual(Double(e6.sets), Double(e5.sets) / 2 + 1, e6.exercise.id)
      }
    }
  }

  func testChestWeeklyVolume4Days() {
    let p = makeProfile(days: 4, session: .m60)
    let week = Program.week(1, profile: p)
    let chestSets = week.reduce(0) { total, day in
      total + day.exercises.filter { $0.exercise.primary == .chest }.reduce(0) { $0 + $1.sets }
    }
    let mev = VolumeLandmarks.base(for: .chest)!.mev
    XCTAssertGreaterThanOrEqual(chestSets, mev - 1)
    XCTAssertLessThanOrEqual(chestSets, mev + p.daysPerWeek)
  }

  func testRepRangesByGoal() {
    for goal in Goal.allCases {
      let p = makeProfile(days: 4, goal: goal)
      for day in Program.week(1, profile: p) {
        for pe in day.exercises {
          let expected: ClosedRange<Int>
          switch (goal, pe.exercise.isCompound) {
          case (.strength, true): expected = 4...6
          case (.strength, false): expected = 8...12
          case (.hypertrophy, true): expected = 8...12
          case (.hypertrophy, false): expected = 12...15
          case (.both, true): expected = 6...10
          case (.both, false): expected = 10...15
          }
          XCTAssertEqual(pe.repRange, expected, "\(pe.exercise.id) \(goal)")
        }
      }
    }
  }

  func testBackWeeklyVolumeStaysUnderMRV() {
    let p = makeProfile(days: 4, session: .m60)
    let mrv = VolumeLandmarks.base(for: .back)!.mrv
    for week in 1...5 {
      let backSets = Program.week(week, profile: p).reduce(0) { total, day in
        total + day.exercises.filter { $0.exercise.primary == .back }.reduce(0) { $0 + $1.sets }
      }
      XCTAssertLessThanOrEqual(backSets, mrv, "week \(week)")
    }
  }

  func testDeterministic() {
    let p = makeProfile(days: 5)
    XCTAssertEqual(Program.week(2, profile: p), Program.week(2, profile: p))
  }

  func testSessionLengthCapsExercises() {
    let p = makeProfile(days: 4, session: .m45)
    let week = Program.week(1, profile: p)
    for day in week {
      XCTAssertLessThanOrEqual(day.exercises.count, 4, day.name)
    }
  }

  func testPlateauRotatesToNextVariant() {
    let p = makeProfile(days: 4)
    let upper = Program.week(1, profile: p).first { $0.name == "Upper" }!
    let x = upper.exercises.first!.exercise
    var plateaued = p
    plateaued.plateauedExerciseIDs = [x.id]
    let rotated = Program.week(1, profile: plateaued).first { $0.name == "Upper" }!
    let y = rotated.exercises.first!
    XCTAssertNotEqual(y.exercise.id, x.id)
    XCTAssertEqual(y.exercise.primary, x.primary)
  }

  func testPlateauBumpsVolumeWhenAllVariantsPlateaued() {
    let p = makeProfile(days: 4)
    let upper = Program.week(1, profile: p).first { $0.name == "Upper" }!
    let x = upper.exercises.first!.exercise
    var plateaued = p
    plateaued.plateauedExerciseIDs = Set(ExerciseDB.all
      .filter { $0.primary == x.primary && $0.pattern == x.pattern }
      .map(\.id))
    let bumped = Program.week(1, profile: plateaued).first { $0.name == "Upper" }!
    XCTAssertEqual(bumped.exercises.first!.exercise.id, x.id)
    XCTAssertEqual(bumped.exercises.first!.sets, upper.exercises.first!.sets + 1)
  }

  func testSmallMusclesSpreadOn3DaySplit() {
    let p = makeProfile(days: 3)
    let week5 = Program.week(5, profile: p)
    XCTAssertGreaterThanOrEqual(week5.filter { $0.exercises.contains { $0.exercise.primary == .sideDelts } }.count, 2)
    for pe in week5.flatMap({ $0.exercises }) where pe.exercise.primary == .sideDelts {
      XCTAssertLessThanOrEqual(pe.sets, Mesocycle.maxSetsPerSlot, pe.exercise.id)
    }
    let week1 = Program.week(1, profile: p)
    XCTAssertEqual(week1.reduce(0) { $0 + $1.exercises.filter { $0.exercise.primary == .sideDelts }.reduce(0) { $0 + $1.sets } }, 8)
    XCTAssertGreaterThanOrEqual(week1.filter { $0.exercises.contains { $0.exercise.primary == .sideDelts } }.count, 2)
  }

  func testNoSlotExceedsCap() {
    for days in 3...6 {
      for session in SessionLength.allCases {
        let p = makeProfile(days: days, session: session)
        for week in 1...6 {
          for pe in Program.week(week, profile: p).flatMap({ $0.exercises }) {
            XCTAssertLessThanOrEqual(pe.sets, Mesocycle.maxSetsPerSlot, "\(days)d \(session) w\(week) \(pe.exercise.id)")
          }
        }
      }
    }
  }

  func testExtrasRespectSessionLength() {
    for days in 3...6 {
      for session in SessionLength.allCases {
        let p = makeProfile(days: days, session: session)
        for day in Program.week(5, profile: p) {
          XCTAssertLessThanOrEqual(day.exercises.count, session.maxExercises, "\(days)d \(session) \(day.name)")
        }
      }
    }
  }

  func testStructureStableAcrossWeeks() {
    let p = makeProfile(days: 3)
    let ids = { Program.week($0, profile: p).map { $0.exercises.map(\.exercise.id) } }
    let base = ids(1)
    for week in 2...6 {
      XCTAssertEqual(ids(week), base, "week \(week)")
    }
    XCTAssertEqual(Program.week(5, profile: p, volumeDelta: [.sideDelts: 1]).map { $0.exercises.map(\.exercise.id) }, base)
  }

  func testNoExtrasWithoutTemplateSlotOrLandmarks() {
    let p = makeProfile(days: 3, session: .m90)
    let week = Program.week(5, profile: p)
    XCTAssertTrue(week.flatMap({ $0.exercises }).filter { $0.exercise.primary == .glutes }.isEmpty)
    XCTAssertEqual(week.flatMap({ $0.exercises }).filter { $0.exercise.primary == .frontDelts }.count, 1)
  }

  func testExtrasAreIsolation() {
    let week = Program.week(5, profile: makeProfile(days: 3))
    for muscle in [Muscle.sideDelts, .calves] {
      for pe in week.flatMap({ $0.exercises }).filter({ $0.exercise.primary == muscle }).dropFirst() {
        XCTAssertFalse(pe.exercise.isCompound, "\(muscle) \(pe.exercise.id)")
      }
    }
  }

  func testSessionSetBudget() {
    for days in 3...6 {
      for session in SessionLength.allCases {
        let p = makeProfile(days: days, session: session)
        for week in 1...6 {
          for day in Program.week(week, profile: p) {
            XCTAssertLessThanOrEqual(day.exercises.reduce(0) { $0 + $1.sets }, Program.setBudget(for: session), "\(days)d \(session) w\(week) \(day.name)")
          }
        }
      }
    }
  }

  func testShortSessionsTrimBiggestSlotFirst() {
    let p = makeProfile(days: 3, session: .m45)
    let fullA = Program.week(2, profile: p).first { $0.name == "Full A" }!
    let sideDelt = fullA.exercises.first { $0.exercise.primary == .sideDelts }!
    XCTAssertLessThanOrEqual(sideDelt.sets, 5)
    XCTAssertGreaterThan(fullA.trimmedSets, 0)
    XCTAssertEqual(fullA.exercises.reduce(0) { $0 + $1.sets }, 18)
  }

  func testDeloadDerivedFromWeekFive() {
    let p = makeProfile(days: 3, session: .m45)
    let week5 = Program.week(5, profile: p)
    let week6 = Program.week(6, profile: p)
    for (d5, d6) in zip(week5, week6) {
      XCTAssertEqual(d5.name, d6.name)
      XCTAssertEqual(d5.exercises.map(\.exercise.id), d6.exercises.map(\.exercise.id))
      for (e5, e6) in zip(d5.exercises, d6.exercises) {
        XCTAssertEqual(e6.sets, max(2, Int((Double(e5.sets) * 0.5).rounded())), e6.exercise.id)
        XCTAssertEqual(e6.targetRPE, Mesocycle.deloadRPECap, e6.exercise.id)
      }
    }
  }
}
