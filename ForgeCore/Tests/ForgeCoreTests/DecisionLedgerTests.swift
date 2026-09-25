import XCTest
@testable import ForgeCore

final class DecisionLedgerTests: XCTestCase {
  private func record(id: String, date: Date, exerciseID: String?, from: Double?, to: Double?,
                      codes: [String] = [], evidence: [String] = [], type: String = "load_change") -> DecisionRecord {
    DecisionRecord(id: id, date: date, type: type, exerciseID: exerciseID, muscle: nil,
                   fromValue: from, toValue: to, reasonCodes: codes, evidence: evidence, humanSummary: "")
  }

  func testLoadChangeRecordRoundTripsThroughPayload() {
    let d = Decision(subject: .exercise(id: "barbell_bench"),
                     action: .increaseLoad(fromKg: 64, toKg: 65),
                     causes: [DecisionCause(signal: .completedAllSets, evidence: "80 kg × 8 @ 7.5"),
                              DecisionCause(signal: .rpeBelowTarget, evidence: "+2.1%")],
                     overridable: true)
    let rec = DecisionRecord.from(d, date: Date(timeIntervalSince1970: 1_700_000_000),
                                  name: "Barbell Bench Press", weight: { "\($0) kg" })
    XCTAssertEqual(rec.type, "load_change")
    XCTAssertEqual(rec.exerciseID, "barbell_bench")
    XCTAssertEqual(rec.fromValue, 64)
    XCTAssertEqual(rec.toValue, 65)
    XCTAssertEqual(rec.reasonCodes, ["completed_all_sets", "rpe_below_target"])
    XCTAssertEqual(rec.evidence, ["80 kg × 8 @ 7.5", "+2.1%"])

    let json = DecisionLedger.payload([rec])
    let decoded = try! JSONDecoder().decode([DecisionRecord].self, from: json.data(using: .utf8)!)
    XCTAssertEqual(decoded, [rec])
  }

  func testPayloadNewestFirstAndLimited() {
    let a = record(id: "a", date: Date(timeIntervalSince1970: 100), exerciseID: "x", from: 1, to: 2)
    let b = record(id: "b", date: Date(timeIntervalSince1970: 300), exerciseID: "x", from: 2, to: 3)
    let c = record(id: "c", date: Date(timeIntervalSince1970: 200), exerciseID: "x", from: 3, to: 4)
    let json = DecisionLedger.payload([a, b, c], limit: 2)
    let decoded = try! JSONDecoder().decode([DecisionRecord].self, from: json.data(using: .utf8)!)
    XCTAssertEqual(decoded.map(\.id), ["b", "c"])
  }

  func testLatestForExercise() {
    let older = record(id: "a", date: Date(timeIntervalSince1970: 100), exerciseID: "barbell_bench", from: 60, to: 62)
    let newer = record(id: "b", date: Date(timeIntervalSince1970: 200), exerciseID: "barbell_bench", from: 62, to: 64)
    let other = record(id: "c", date: Date(timeIntervalSince1970: 300), exerciseID: "back_squat", from: 100, to: 105)
    XCTAssertEqual(DecisionLedger.latest(for: "barbell_bench", in: [older, newer, other])?.id, "b")
    XCTAssertNil(DecisionLedger.latest(for: "deadlift", in: [older, newer, other]))
  }

  func testMuscleAndSwapType() {
    let vol = Decision(subject: .muscle(.biceps), action: .addSets(1),
                       causes: [DecisionCause(signal: .volumeBelowMEV, evidence: "")], overridable: true)
    let rec = DecisionRecord.from(vol, date: Date(), name: "Biceps", weight: { "\($0) kg" })
    XCTAssertEqual(rec.type, "volume_change")
    XCTAssertEqual(rec.muscle, "biceps")
    XCTAssertNil(rec.exerciseID)

    let swap = Decision(subject: .exercise(id: "barbell_bench"), action: .swapExercise(fromID: "barbell_bench", toID: "db_bench_neutral"),
                        causes: [DecisionCause(signal: .plateau, evidence: "")], overridable: true)
    let swapRec = DecisionRecord.from(swap, date: Date(), name: "Bench", weight: { "\($0) kg" })
    XCTAssertEqual(swapRec.type, "plateau")
  }
}
