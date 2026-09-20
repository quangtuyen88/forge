import XCTest

@testable import ForgeCore

final class EquipmentPassportTests: XCTestCase {

  private let epoch = Date(timeIntervalSince1970: 1_700_000_000)

  // MARK: Units / kg-lb

  func testKilogramAndPoundModelsNormalizeToKilograms() {
    let kg = LoadModel.barbellTotalKG(id: "bb.kg", now: epoch)
    XCTAssertEqual(kg.incrementKg!, 2.5, accuracy: 0.0001)

    let lb = LoadModel.barbellTotalLB(id: "bb.lb", now: epoch)
    XCTAssertEqual(lb.unit, .pounds)
    XCTAssertEqual(lb.incrementKg!, 5 * LoadUnit.poundsToKilograms, accuracy: 0.0001)
    XCTAssertEqual(lb.barWeight!, 45)

    // Unspecified units never fabricate a conversion.
    let unknownUnit = LoadModel(
      id: "u", domain: .externalMass, convention: .unknown, unit: .unspecified, increment: 5,
      normalizationStatus: .ambiguous, createdAt: epoch, updatedAt: epoch)
    XCTAssertNil(unknownUnit.incrementKg)
    XCTAssertNil(unknownUnit.unit.toKilograms(100))
  }

  func testUnitParseIsLenientAndNeverAssumesKilograms() {
    XCTAssertEqual(LoadUnit.parse("KG"), .kilograms)
    XCTAssertEqual(LoadUnit.parse(" lbs "), .pounds)
    XCTAssertEqual(LoadUnit.parse("stone"), .unspecified)
    XCTAssertEqual(LoadUnit.parse(nil), .unspecified)
    XCTAssertEqual(LoadUnit.parse(""), .unspecified)
  }

  // MARK: Conventions

  func testBarbellTotalIncludesBar() {
    let model = LoadModel.barbellTotalKG(id: "bb", barWeight: 20, now: epoch)
    XCTAssertEqual(model.convention, .totalIncludingBar)
    XCTAssertTrue(model.includesBar)
    // A plates-only reading is converted to a total by adding the bar.
    XCTAssertEqual(model.total(fromPlatesOutsideBar: 80)!, 100, accuracy: 0.0001)
  }

  func testPlatesOnlyKeepsBarSeparate() {
    let model = LoadModel.platesOnlyKG(id: "bb.plates", barWeight: 20, now: epoch)
    XCTAssertEqual(model.convention, .platesOnly)
    XCTAssertFalse(model.includesBar)
    // Two instances of the same physical bar with different conventions are NOT comparable.
    let total = LoadModel.barbellTotalKG(id: "bb.total", barWeight: 20, now: epoch)
    XCTAssertNotNil(
      EquipmentInstance(
        id: "a", name: "Bar", kind: .barbell, gymProfileID: "g1",
        loadModel: model, createdAt: epoch, updatedAt: epoch
      ).incompatibility(
        with: EquipmentInstance(
          id: "b", name: "Bar", kind: .barbell, gymProfileID: "g1",
          loadModel: total, createdAt: epoch, updatedAt: epoch),
        exerciseID: "barbell_bench"))
  }

  func testPerHandIsDistinctFromCombined() {
    let left = LoadModel.perHandKG(id: "db", increment: 2, now: epoch)
    XCTAssertEqual(left.convention, .perHand)
    let combined = LoadModel(
      id: "cb", domain: .externalMass, convention: .combined, unit: .kilograms, increment: 2.5,
      normalizationStatus: .verified, createdAt: epoch, updatedAt: epoch)
    XCTAssertNotEqual(left.convention, combined.convention)
  }

  func testAssistanceUsesAssistanceDomain() {
    let model = LoadModel.assistanceKG(id: "assist", now: epoch)
    XCTAssertEqual(model.domain, .assistance)
    XCTAssertEqual(model.convention, .assistanceDisplayed)
    // Assistance is not external mass; a domain-mismatched reading never compares verified.
    let external = LoadModel.barbellTotalKG(id: "bb", now: epoch)
    XCTAssertNotEqual(model.domain, external.domain)
  }

  func testMachineStackLoadUsesBaseAndIncrement() {
    let model = LoadModel.machineStackKG(id: "stack", stackBaseWeight: 5, stackIncrement: 10, now: epoch)
    XCTAssertEqual(model.domain, .machineScale)
    XCTAssertEqual(model.stackLoad(steps: 0)!, 5, accuracy: 0.0001)
    XCTAssertEqual(model.stackLoad(steps: 3)!, 35, accuracy: 0.0001)
    XCTAssertEqual(model.increment, 10)
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

  // MARK: Codable round trip

  func testPassportCodableRoundTrip() throws {
    let passport = EquipmentPassport(instances: [
      EquipmentInstance(
        id: "bar.commercial", name: "Bar", kind: .barbell, gymProfileID: "commercial",
        loadModel: LoadModel.barbellTotalKG(id: "bc", revision: 3, now: epoch),
        createdAt: epoch, updatedAt: epoch),
      EquipmentInstance(
        id: "row.commercial", name: "Seated Row", kind: .machine, gymProfileID: "commercial",
        loadModel: LoadModel.machineStackKG(id: "r", revision: 2, now: epoch),
        createdAt: epoch, updatedAt: epoch),
    ])
    let data = try JSONEncoder().encode(passport)
    let decoded = try JSONDecoder().decode(EquipmentPassport.self, from: data)
    XCTAssertEqual(decoded, passport)
    XCTAssertEqual(decoded.instances[0].loadModel.revision, 3)
  }

  func testLoadDescriptorRoundTripPreservesAmbiguity() throws {
    let descriptor = LoadDescriptor(
      originalValue: "100", originalUnit: "lb", domain: .externalMass, convention: .unknown,
      equipmentInstanceID: "legacy.bar", loadModelRevision: 0, side: .unspecified,
      normalizationStatus: .ambiguous)
    let decoded = try JSONDecoder().decode(
      LoadDescriptor.self, from: JSONEncoder().encode(descriptor))
    XCTAssertEqual(decoded, descriptor)
    XCTAssertEqual(decoded.normalizationStatus, .ambiguous)
  }

  // MARK: Migration / legacy import

  func testLegacyMigrationPreservesUnknownSemantics() {
    let result = EquipmentPassportMigration.migrate(
      LegacyEquipmentRecord(name: "Chest Press", kind: "not-a-real-kind",
        gymProfileID: "hotel", unit: "stone", lastWeight: 55),
      now: epoch)

    XCTAssertEqual(result.instance.kind, .unknown)
    XCTAssertEqual(result.instance.loadModel.unit, .unspecified)
    XCTAssertEqual(result.instance.loadModel.convention, .unknown)
    XCTAssertEqual(result.instance.loadModel.normalizationStatus, .ambiguous)
    XCTAssertEqual(result.descriptor.originalUnit, "stone")
    XCTAssertEqual(result.descriptor.originalValue, "55")
    XCTAssertEqual(result.descriptor.normalizationStatus, .ambiguous)
    XCTAssertFalse(result.warnings.isEmpty)

    // Unknown convention means no comparison is ever possible against a verified passport.
    let verified = EquipmentInstance(
      id: "row.commercial", name: "Row", kind: .machine, gymProfileID: "commercial",
      loadModel: LoadModel.machineStackKG(id: "r", now: epoch), createdAt: epoch, updatedAt: epoch)
    XCTAssertEqual(
      result.instance.incompatibility(with: verified, exerciseID: "chest_press"),
      "Load meaning is not verified")
  }

  func testLegacyMigrationNeverAssumesBarbellTotalOrPlates() {
    // A kg barbell reading with an explicit weight still must not be assumed to include the bar.
    let result = EquipmentPassportMigration.migrate(
      LegacyEquipmentRecord(name: "Back Squat", kind: "barbell", gymProfileID: "home",
        unit: "kg", barWeight: 20, lastWeight: 100),
      now: epoch)
    XCTAssertEqual(result.instance.kind, .barbell)
    XCTAssertEqual(result.instance.loadModel.unit, .kilograms)
    XCTAssertEqual(result.instance.loadModel.convention, .unknown)
    XCTAssertEqual(result.instance.loadModel.normalizationStatus, .ambiguous)
    XCTAssertEqual(result.instance.loadModel.barWeight, 20)
    XCTAssertFalse(result.descriptor.normalizationStatus == .verified)
  }

  func testLegacyMigrationIDsAreDeterministic() {
    let record = LegacyEquipmentRecord(name: "Chest Press", kind: "machine", gymProfileID: "Hotel Gym")
    let first = EquipmentPassportMigration.migrate(record, now: epoch)
    let second = EquipmentPassportMigration.migrate(record, now: epoch)
    XCTAssertEqual(first.instance.id, second.instance.id)
    XCTAssertEqual(first.instance.id, "legacy.chest-press.hotel-gym")
    XCTAssertEqual(EquipmentInstance.stableID(name: nil, gymProfileID: nil), "legacy.unknown")
  }

  func testLegacyMigrationFromJSON() throws {
    let json = Data(
      #"{"name":"Leg press","kind":"machine","gymProfileID":"commercial","lastWeight":120}"#.utf8)
    let result = try EquipmentPassportMigration.migrate(json: json, now: epoch)
    XCTAssertEqual(result.instance.name, "Leg press")
    XCTAssertEqual(result.instance.gymProfileID, "commercial")
    XCTAssertEqual(result.instance.loadModel.normalizationStatus, .ambiguous)
    XCTAssertEqual(result.descriptor.originalUnit, "")
  }

  func testLegacyUnknownModelFactory() {
    let model = LoadModel.legacyUnknown(id: "m", now: epoch)
    XCTAssertEqual(model.convention, .unknown)
    XCTAssertEqual(model.unit, .unspecified)
    XCTAssertEqual(model.normalizationStatus, .ambiguous)
    XCTAssertNil(model.incrementKg)
  }
}
