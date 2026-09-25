import XCTest

@testable import ForgeCore

final class EquipmentPassportTests: XCTestCase {

  private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

  // MARK: Conventions

  func testBarbellTotalIncludesBar() {
    let model = LoadModel.barbellTotalKG(id: "bb", barWeight: 20, now: epoch)
    XCTAssertEqual(model.convention, .totalIncludingBar)
    XCTAssertTrue(model.includesBar)
    // A plates-only reading is converted to a total by adding the bar.
    XCTAssertEqual(model.total(fromPlatesOutsideBar: 80)!, 100, accuracy: 0.0001)
  }

  // MARK: Comparison compatibility

  func testMachineRevisionChangeBreaksComparison() {
    let commercialA = EquipmentInstance(
      id: "machine.seatedrow", name: "Seated Row", kind: .machine, gymProfileID: "commercial",
      loadModel: LoadModel.machineStackKG(id: "m1", revision: 1, now: epoch),
      createdAt: epoch, updatedAt: epoch)
    let commercialB = EquipmentInstance(
      id: "machine.seatedrow", name: "Seated Row", kind: .machine, gymProfileID: "commercial",
      loadModel: LoadModel.machineStackKG(id: "m1", revision: 2, now: epoch),
      createdAt: epoch, updatedAt: epoch)
    XCTAssertEqual(
      commercialA.incompatibility(with: commercialB, exerciseID: "seated_row"),
      "Different load models")
    XCTAssertFalse(commercialA.isComparable(to: commercialB, exerciseID: "seated_row"))
  }

  func testDistinctEquipmentInstancesAreNotComparable() {
    let machineA = EquipmentInstance(
      id: "row.a", name: "Row A", kind: .machine, gymProfileID: "commercial",
      loadModel: LoadModel.machineStackKG(id: "a", now: epoch), createdAt: epoch, updatedAt: epoch)
    let machineB = EquipmentInstance(
      id: "row.b", name: "Row B", kind: .machine, gymProfileID: "commercial",
      loadModel: LoadModel.machineStackKG(id: "b", now: epoch), createdAt: epoch, updatedAt: epoch)
    XCTAssertEqual(
      machineA.incompatibility(with: machineB, exerciseID: "seated_row"),
      "Different equipment instances")

    // Even the exact same physical bar at two gyms is a different instance.
    let barHome = EquipmentInstance(
      id: "bar.home", name: "Bar", kind: .barbell, gymProfileID: "home",
      loadModel: LoadModel.barbellTotalKG(id: "bh", now: epoch), createdAt: epoch, updatedAt: epoch)
    let barCommercial = EquipmentInstance(
      id: "bar.commercial", name: "Bar", kind: .barbell, gymProfileID: "commercial",
      loadModel: LoadModel.barbellTotalKG(id: "bc", now: epoch), createdAt: epoch, updatedAt: epoch)
    XCTAssertFalse(barHome.isComparable(to: barCommercial, exerciseID: "barbell_bench"))
  }

  func testSameInstanceSameRevisionIsComparable() {
    let instance = EquipmentInstance(
      id: "bar.commercial", name: "Bar", kind: .barbell, gymProfileID: "commercial",
      loadModel: LoadModel.barbellTotalKG(id: "bc", now: epoch), createdAt: epoch, updatedAt: epoch)
    XCTAssertTrue(instance.isComparable(to: instance, exerciseID: "barbell_bench"))
    XCTAssertEqual(
      EquipmentPassport.explainIncompatibility(
        instance.comparisonContext(exerciseID: "barbell_bench"),
        instance.comparisonContext(exerciseID: "barbell_bench")),
      "Comparable: identical exercise, variant, equipment, revision and convention")
  }

  func testDifferentExercisesAndVariantsAreNotComparable() {
    let instance = EquipmentInstance(
      id: "bar.commercial", name: "Bar", kind: .barbell, gymProfileID: "commercial",
      loadModel: LoadModel.barbellTotalKG(id: "bc", now: epoch), createdAt: epoch, updatedAt: epoch)
    let a = instance.comparisonContext(exerciseID: "barbell_bench")
    let b = instance.comparisonContext(exerciseID: "back_squat")
    XCTAssertEqual(EquipmentPassport.explainIncompatibility(a, b), "Different exercises")
    let c = instance.comparisonContext(exerciseID: "barbell_bench", variantID: "close_grip")
    XCTAssertEqual(
      EquipmentPassport.explainIncompatibility(a, c), "Different exercise variants")
  }

  // MARK: Resolution

  func testResolvePrefersGymSpecificInstance() {
    let passport = EquipmentPassport(instances: [
      EquipmentInstance(
        id: "band.any", name: "Band", kind: .bands, gymProfileID: nil,
        loadModel: LoadModel(id: "band", domain: .bodyweight, convention: .notApplicable,
          unit: .kilograms, increment: 0, normalizationStatus: .verified,
          createdAt: epoch, updatedAt: epoch),
        createdAt: epoch, updatedAt: epoch),
      EquipmentInstance(
        id: "band.home", name: "Home Band", kind: .bands, gymProfileID: "home",
        loadModel: LoadModel(id: "bandh", domain: .bodyweight, convention: .notApplicable,
          unit: .kilograms, increment: 0, normalizationStatus: .verified,
          createdAt: epoch, updatedAt: epoch),
        createdAt: epoch, updatedAt: epoch),
    ])
    XCTAssertEqual(passport.resolve(kind: .bands, forGymProfile: "home").instance?.id, "band.home")
    // Falls back to the gym-independent global instance for another gym.
    XCTAssertEqual(passport.resolve(kind: .bands, forGymProfile: "hotel").instance?.id, "band.any")
  }

  func testResolveDoesNotLeakMachinesAcrossGyms() {
    let passport = EquipmentPassport(instances: [
      EquipmentInstance(
        id: "row.commercial", name: "Seated Row", kind: .machine, gymProfileID: "commercial",
        loadModel: LoadModel.machineStackKG(id: "c", now: epoch), createdAt: epoch, updatedAt: epoch)
    ])
    let resolution = passport.resolve(kind: .machine, forGymProfile: "hotel")
    XCTAssertEqual(resolution, .unavailable)
    XCTAssertTrue(resolution.explanation.contains("Unavailable"))
  }

  func testResolveIsAmbiguousWithMultipleSameGymMachines() {
    let passport = EquipmentPassport(instances: [
      EquipmentInstance(
        id: "row.a", name: "Row A", kind: .machine, gymProfileID: "commercial",
        loadModel: LoadModel.machineStackKG(id: "a", now: epoch), createdAt: epoch, updatedAt: epoch),
      EquipmentInstance(
        id: "row.b", name: "Row B", kind: .machine, gymProfileID: "commercial",
        loadModel: LoadModel.machineStackKG(id: "b", now: epoch), createdAt: epoch, updatedAt: epoch),
    ])
    XCTAssertEqual(
      passport.resolve(kind: .machine, forGymProfile: "commercial"),
      .ambiguous(candidateIDs: ["row.a", "row.b"]))
  }

  func testResolveIgnoresRetiredInstances() {
    let passport = EquipmentPassport(instances: [
      EquipmentInstance(
        id: "old.bar", name: "Old Bar", kind: .barbell, gymProfileID: "commercial",
        loadModel: LoadModel.barbellTotalKG(id: "ob", now: epoch),
        createdAt: epoch, updatedAt: epoch, isRetired: true),
      EquipmentInstance(
        id: "new.bar", name: "New Bar", kind: .barbell, gymProfileID: "commercial",
        loadModel: LoadModel.barbellTotalKG(id: "nb", now: epoch),
        createdAt: epoch, updatedAt: epoch),
    ])
    XCTAssertEqual(passport.resolve(kind: .barbell, forGymProfile: "commercial").instance?.id, "new.bar")
  }

  // MARK: Migration / legacy import

  func testLegacyMigrationIDsAreDeterministic() {
    let record = LegacyEquipmentRecord(name: "Chest Press", kind: "machine", gymProfileID: "Hotel Gym")
    let first = EquipmentPassportMigration.migrate(record, now: epoch)
    let second = EquipmentPassportMigration.migrate(record, now: epoch)
    XCTAssertEqual(first.instance.id, second.instance.id)
    XCTAssertEqual(first.instance.id, "legacy.chest-press.hotel-gym")
    XCTAssertEqual(EquipmentInstance.stableID(name: nil, gymProfileID: nil), "legacy.unknown")
  }
}
