import ForgeCore
import Foundation
import SwiftData
import XCTest

@testable import Forge

/// Account provenance: one device, one owner.
///
/// `SyncEngine.prepareAccountActivation(userID:)` (`App/Forge/SyncEngine.swift:258-274`) is the only
/// gate that stops a second account from adopting a store that already holds someone else's
/// training data. It reads two witnesses — the `UserDefaults` key `forge.sync.storeOwner` and
/// `UserProfile.journeyBoundAccountID` — and throws `.differentLocalOwner` when either disagrees.
///
/// This test touches a process-wide singleton (`SyncEngine.shared`) and the standard
/// `UserDefaults`. It is safe because (a) `configure(container:)` is the only member it touches and
/// `prepareAccountActivation` never reaches the network (`sync()` is the only caller of the API and
/// it requires an auth token, which the test process does not have), and (b) the previous
/// `UserDefaults` value is restored in `tearDown`. Run it in its own class so a failure cannot
/// leave the defaults key behind for the other suites.
@MainActor
final class JourneyAccountProvenanceTests: XCTestCase {

  private var savedStoreOwner: String?

  override func setUpWithError() throws {
    savedStoreOwner = UserDefaults.standard.string(forKey: SyncEngine.storeOwnerKey)
    UserDefaults.standard.removeObject(forKey: SyncEngine.storeOwnerKey)
  }

  override func tearDownWithError() throws {
    if let savedStoreOwner {
      UserDefaults.standard.set(savedStoreOwner, forKey: SyncEngine.storeOwnerKey)
    } else {
      UserDefaults.standard.removeObject(forKey: SyncEngine.storeOwnerKey)
    }
  }

  func testSecondLocalOwnerIsRejectedAndTheFirstOwnerIsRemembered() throws {
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let profile = try JourneyTestStore.profile(in: context)
    SyncEngine.shared.configure(container: container)

    // A store with no owner witness yet adopts the first account, twice over: re-activating the
    // same owner is a no-op, not a conflict.
    try SyncEngine.shared.prepareAccountActivation(userID: "account-a")
    try SyncEngine.shared.prepareAccountActivation(userID: "account-a")
    XCTAssertEqual(UserDefaults.standard.string(forKey: SyncEngine.storeOwnerKey), "account-a")

    // A different owner is refused, and the stored witness is left untouched.
    XCTAssertThrowsError(try SyncEngine.shared.prepareAccountActivation(userID: "account-b")) {
      error in
      XCTAssertEqual(error as? AccountActivationError, .differentLocalOwner)
    }
    XCTAssertEqual(UserDefaults.standard.string(forKey: SyncEngine.storeOwnerKey), "account-a")

    // The profile is the second witness: even with the defaults key cleared, a store bound to a
    // different account cannot be re-bound.
    UserDefaults.standard.removeObject(forKey: SyncEngine.storeOwnerKey)
    profile.journeyBoundAccountID = "account-b"
    profile.updatedAt = .now
    try context.save()

    XCTAssertThrowsError(try SyncEngine.shared.prepareAccountActivation(userID: "account-c")) {
      error in
      XCTAssertEqual(error as? AccountActivationError, .differentLocalOwner)
    }
    XCTAssertNil(
      UserDefaults.standard.string(forKey: SyncEngine.storeOwnerKey),
      "a refused activation writes nothing")

    // Signing back into the bound account is still allowed, and re-writes the witness.
    try SyncEngine.shared.prepareAccountActivation(userID: "account-b")
    XCTAssertEqual(UserDefaults.standard.string(forKey: SyncEngine.storeOwnerKey), "account-b")

    // An account with no stable identifier never becomes an owner.
    XCTAssertThrowsError(try SyncEngine.shared.prepareAccountActivation(userID: "   ")) { error in
      XCTAssertEqual(error as? AccountActivationError, .invalidAccount)
    }
    XCTAssertEqual(UserDefaults.standard.string(forKey: SyncEngine.storeOwnerKey), "account-b")
  }

  func testActivationRecordsTheCanonicalOwnerForm() throws {
    let container = try JourneyTestStore.inMemory()
    SyncEngine.shared.configure(container: container)
    try JourneyTestStore.profile(in: container.mainContext)

    // A UUID account is folded to its uppercase canonical spelling, so the witness written here
    // matches the owner the Journey repository will derive for the same account.
    let lowercased = "3f2504e0-4f89-11d3-9a0c-0305e82c3301"
    try SyncEngine.shared.prepareAccountActivation(userID: lowercased)

    let stored = try XCTUnwrap(UserDefaults.standard.string(forKey: SyncEngine.storeOwnerKey))
    XCTAssertEqual(stored, JourneyEventID.canonicalOwner(lowercased))
    XCTAssertEqual(stored, "3F2504E0-4F89-11D3-9A0C-0305E82C3301")

    // The uppercase spelling is the same owner, so re-activating is idempotent.
    try SyncEngine.shared.prepareAccountActivation(userID: stored)
    XCTAssertEqual(UserDefaults.standard.string(forKey: SyncEngine.storeOwnerKey), stored)
  }

  func testOwnerWitnessSurvivesStoreReopenAndBlocksAnotherAccount() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent("forge-owner-(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appendingPathComponent("owner.store")

    do {
      let container = try JourneyTestStore.onDisk(at: url)
      let context = container.mainContext
      try JourneyTestStore.profile(in: context)
      context.insert(
        WorkoutSession(
          date: JourneyTestStore.date(2025, 6, 5), dayName: "Owner A", week: 1,
          completed: true))
      try context.save()
      SyncEngine.shared.configure(container: container)
      try SyncEngine.shared.prepareAccountActivation(userID: "account-a")
    }

    let reopened = try JourneyTestStore.onDisk(at: url)
    SyncEngine.shared.configure(container: reopened)
    XCTAssertThrowsError(try SyncEngine.shared.prepareAccountActivation(userID: "account-b")) {
      error in
      XCTAssertEqual(error as? AccountActivationError, .differentLocalOwner)
    }
    XCTAssertEqual(
      try reopened.mainContext.fetchCount(FetchDescriptor<WorkoutSession>()), 1,
      "a refused account switch must preserve the first owner's offline data")
    XCTAssertEqual(UserDefaults.standard.string(forKey: SyncEngine.storeOwnerKey), "account-a")
    try SyncEngine.shared.prepareAccountActivation(userID: "account-a")
  }

  func testGenuinelyUnboundLocalDataAdoptsTheFirstAccountOnce() throws {
    let container = try JourneyTestStore.inMemory()
    let context = container.mainContext
    let profile = try JourneyTestStore.profile(in: context)
    context.insert(
      WorkoutSession(
        date: JourneyTestStore.date(2025, 6, 5), dayName: "Local workout", week: 1,
        completed: true))
    try context.save()
    SyncEngine.shared.configure(container: container)

    try SyncEngine.shared.prepareAccountActivation(userID: "first-account")

    XCTAssertEqual(UserDefaults.standard.string(forKey: SyncEngine.storeOwnerKey), "first-account")
    XCTAssertEqual(try context.fetchCount(FetchDescriptor<WorkoutSession>()), 1)
    XCTAssertTrue(
      profile.journeyBoundAccountID.isEmpty,
      "JourneyRepository performs the one-time local Journey-record migration when first opened")
    XCTAssertThrowsError(try SyncEngine.shared.prepareAccountActivation(userID: "second-account")) {
      error in
      XCTAssertEqual(error as? AccountActivationError, .differentLocalOwner)
    }
  }
}
