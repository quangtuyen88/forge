import XCTest
@testable import ForgeCore

final class CoachContextTests: XCTestCase {
  func testHealthKitFieldWithheldAndNeverRendered() {
    let fields = [
      ContextField(key: "bodyweight", value: "82 kg", source: .healthKit),
      ContextField(key: "goal", value: "strength", source: .app),
      ContextField(key: "note", value: "feeling good", source: .user),
    ]
    let packet = CoachContextBuilder.packet(fields: fields, decisions: [])
    XCTAssertEqual(packet.withheld, ["bodyweight"])
    let rendered = packet.rendered()
    XCTAssertFalse(rendered.contains("82 kg"))
    XCTAssertFalse(rendered.contains("bodyweight"))
    XCTAssertTrue(rendered.contains("goal: strength"))
    XCTAssertTrue(rendered.contains("note: feeling good"))
  }

  func testRenderedExcludesHealthKitEvenIfConstructedDirectly() {
    let packet = CoachContextPacket(
      fields: [ContextField(key: "heartRate", value: "61 bpm", source: .healthKit),
               ContextField(key: "goal", value: "hypertrophy", source: .app)],
      decisions: [], withheld: [])
    let rendered = packet.rendered()
    XCTAssertFalse(rendered.contains("61 bpm"))
    XCTAssertTrue(rendered.contains("goal: hypertrophy"))
  }
}
