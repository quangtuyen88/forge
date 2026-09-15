import XCTest
@testable import ForgeCore

final class ImportTests: XCTestCase {
  func testDetect() {
    let strong = "Date,Workout Name,Exercise Name,Set Order,Weight,Reps,Workout Notes,Duration\n2024-01-15 17:30:00,Push,Bench Press (Barbell),1,80,8,,1h 5m\n"
    let hevy = "title,start_time,end_time,description,exercise_title,set_index,set_type,weight_kg,reps,rpe,exercise_notes\nLegs,15 Jan 2024, 10:30,15 Jan 2024, 11:20,,Squat (Barbell),1,normal,100,5,7,\n"
    XCTAssertEqual(WorkoutImport.detect(strong), .strong)
    XCTAssertEqual(WorkoutImport.detect(hevy), .hevy)
    XCTAssertEqual(WorkoutImport.detect("﻿" + strong), .strong)
    XCTAssertNil(WorkoutImport.detect("a,b,c\n1,2,3\n"))
  }

  func testStrongQuotedNotesRestTimerDuration() {
    let csv = """
    "Date","Workout Name","Exercise Name","Set Order","Weight","Weight Unit","Reps","RPE","Notes","Workout Notes","Duration"
    "2024-01-15 17:30:00","Push A","Bench Press (Barbell)","1","80","kg","8","8","","Felt strong, bar speed good","1h 5m"
    "2024-01-15 17:30:00","Push A","Bench Press (Barbell)","2","82.5","kg","8","8.5","","Felt strong, bar speed good","1h 5m"
    "2024-01-15 17:30:00","Push A","Bench Press (Barbell)","Rest Timer","","","","","","Felt strong, bar speed good","1h 5m"
    "2024-01-15 17:30:00","Push A","Overhead Press (Barbell)","1","50","kg","10","7","","Felt strong, bar speed good","45m"
    """
    let r = WorkoutImport.parse(csv, assumeLb: false)!
    XCTAssertEqual(r.source, .strong)
    XCTAssertEqual(r.sessions.count, 1)
    let s = r.sessions[0]
    XCTAssertEqual(s.name, "Push A")
    XCTAssertEqual(s.sets.count, 3)
    XCTAssertEqual(s.notes, "Felt strong, bar speed good")
    XCTAssertEqual(s.durationSeconds, 3900)
    XCTAssertEqual(s.sets[1].weightKg, 82.5, accuracy: 0.001)
    XCTAssertEqual(s.sets[2].weightKg, 50, accuracy: 0.001)
    XCTAssertEqual(s.sets[0].rpe, 8)
    XCTAssertFalse(r.unitIsLb)
    XCTAssertTrue(r.unmatchedNames.isEmpty)
    XCTAssertEqual(r.droppedSets, 0)
  }

  func testStrongSemicolonWithLbsUnit() {
    let csv = "Date;Workout Name;Exercise Name;Set Order;Weight;Weight Unit;Reps;Workout Notes;Duration\n" +
      "2024-02-01 09:00:00;Legs;Squat (Barbell);1;225;lbs;5;;1:05:00\n" +
      "2024-02-01 09:00:00;Legs;Leg Press;1;180;kg;10;;\n"
    let r = WorkoutImport.parse(csv, assumeLb: false)!
    XCTAssertEqual(r.sessions.count, 1)
    XCTAssertEqual(r.sessions[0].sets[0].weightKg, 225 * 0.45359237, accuracy: 0.001)
    XCTAssertEqual(r.sessions[0].sets[1].weightKg, 180, accuracy: 0.001)
    XCTAssertEqual(r.sessions[0].durationSeconds, 3900)
    XCTAssertEqual(r.sessions[0].sets[0].reps, 5)
    XCTAssertTrue(r.unitIsLb)
  }

  func testAssumeLbDrivesUnitlessStrongWeights() {
    let csv = "Date,Workout Name,Exercise Name,Set Order,Weight,Reps,Workout Notes,Duration\n" +
      "2024-04-01 10:00:00,Push,Bench Press (Barbell),1,100,8,,\n"
    let kg = WorkoutImport.parse(csv, assumeLb: false)!
    let lb = WorkoutImport.parse(csv, assumeLb: true)!
    XCTAssertEqual(kg.sessions[0].sets[0].weightKg, 100, accuracy: 0.001)
    XCTAssertEqual(lb.sessions[0].sets[0].weightKg, 100 * 0.45359237, accuracy: 0.001)
    XCTAssertFalse(kg.unitIsLb)
    XCTAssertTrue(lb.unitIsLb)
  }

  func testStrongGroupingPerDateAndName() {
    let row = { (date: String, name: String, ex: String) in
      "\(date),\(name),\(ex),1,60,8,,\n"
    }
    let csv = "Date,Workout Name,Exercise Name,Set Order,Weight,Reps,Workout Notes,Duration\n" +
      row("2024-01-01 10:00:00", "Push", "Bench Press (Barbell)") +
      row("2024-01-01 10:00:00", "Pull", "Lat Pulldown (Cable)") +
      row("2024-01-01 10:00:00", "Push", "Overhead Press (Barbell)") +
      row("2024-01-02 10:00:00", "Push", "Bench Press (Barbell)")
    let r = WorkoutImport.parse(csv, assumeLb: false)!
    XCTAssertEqual(r.sessions.count, 3)
    XCTAssertEqual(r.sessions[0].name, "Push")
    XCTAssertEqual(r.sessions[0].sets.count, 2)
    XCTAssertEqual(r.sessions[1].name, "Pull")
    XCTAssertEqual(r.sessions[2].sets.count, 1)
  }

  func testHevyLbsConversionAndDuration() {
    let csv = "title,start_time,end_time,description,exercise_title,set_index,set_type,weight_lbs,reps,rpe,exercise_notes\n" +
      "\"Chest Day\",\"15 Jan 2024, 10:30\",\"15 Jan 2024, 11:20\",\"good session, solid work\",\"Bench Press (Barbell)\",2,normal,135,8,7,\n"
    let r = WorkoutImport.parse(csv, assumeLb: false)!
    XCTAssertEqual(r.source, .hevy)
    XCTAssertEqual(r.sessions.count, 1)
    let s = r.sessions[0]
    XCTAssertEqual(s.name, "Chest Day")
    XCTAssertEqual(s.notes, "good session, solid work")
    XCTAssertEqual(s.durationSeconds, 3000)
    XCTAssertEqual(s.sets.count, 1)
    XCTAssertEqual(s.sets[0].weightKg, 135 * 0.45359237, accuracy: 0.001)
    XCTAssertEqual(s.sets[0].reps, 8)
    XCTAssertEqual(s.sets[0].rpe, 7)
    XCTAssertTrue(r.unitIsLb)
  }

  func testHevyWarmupSkippedAndEmptyDropped() {
    let csv = "title,start_time,end_time,description,exercise_title,set_index,set_type,weight_kg,reps,rpe,exercise_notes\n" +
      "\"Legs\",\"5 Jan 2024, 18:00\",\"5 Jan 2024, 18:50\",\"\",\"Squat (Barbell)\",1,warmup,60,5,,\n" +
      "\"Legs\",\"5 Jan 2024, 18:00\",\"5 Jan 2024, 18:50\",\"\",\"Squat (Barbell)\",2,normal,140,5,8,\n" +
      "\"Legs\",\"5 Jan 2024, 18:00\",\"5 Jan 2024, 18:50\",\"\",\"Squat (Barbell)\",3,normal,,, ,\n"
    let r = WorkoutImport.parse(csv, assumeLb: false)!
    XCTAssertEqual(r.sessions.count, 1)
    XCTAssertEqual(r.sessions[0].sets.count, 1)
    XCTAssertEqual(r.sessions[0].sets[0].weightKg, 140, accuracy: 0.001)
    XCTAssertEqual(r.droppedSets, 1)
  }

  func testMatchCommonNames() {
    XCTAssertEqual(WorkoutImport.match("Squat (Barbell)")?.id, "back_squat")
    XCTAssertEqual(WorkoutImport.match("Bench Press (Barbell)")?.id, "barbell_bench")
    XCTAssertEqual(WorkoutImport.match("Lat Pulldown (Cable)")?.id, "lat_pulldown")
    XCTAssertEqual(WorkoutImport.match("Romanian Deadlift (Barbell)")?.id, "romanian_deadlift")
    XCTAssertEqual(WorkoutImport.match("Deadlift")?.id, "deadlift")
    XCTAssertEqual(WorkoutImport.match("Pull Ups")?.id, "pull_up")
    XCTAssertEqual(WorkoutImport.match("Seated Cable Row")?.id, "seated_cable_row")
    XCTAssertEqual(WorkoutImport.match("Triceps Pushdown")?.id, "tricep_pushdown")
  }

  func testMatchNonsenseAndUnmatchedReported() {
    XCTAssertNil(WorkoutImport.match("Flim Flam Inverted Wobble Press 9000"))
    let csv = "Date,Workout Name,Exercise Name,Set Order,Weight,Reps,Workout Notes,Duration\n" +
      "2024-03-01 10:00:00,Odd,Flim Flam Inverted Wobble Press 9000,1,40,8,,\n" +
      "2024-03-01 10:00:00,Odd,Flim Flam Inverted Wobble Press 9000,2,42.5,8,,\n" +
      "2024-03-01 10:00:00,Odd,Bench Press (Barbell),1,80,8,,\n"
    let r = WorkoutImport.parse(csv, assumeLb: false)!
    XCTAssertEqual(r.unmatchedNames, ["Flim Flam Inverted Wobble Press 9000"])
    XCTAssertEqual(r.droppedSets, 2)
    XCTAssertEqual(r.sessions[0].sets.count, 1)
  }
}
