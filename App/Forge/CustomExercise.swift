import ForgeCore
import Foundation
import SwiftData

@Model
final class CustomExercise {
  var remoteID: String
  var name: String
  var primary: String
  var synergists: [String] = []
  var equipment: String
  var isCompound: Bool
  var pattern: String = MovementPattern.isolation.rawValue
  var updatedAt: Date = Date.now
  @Attribute(originalName: "deleted") var tombstoned: Bool = false

  init(
    remoteID: String = UUID().uuidString, name: String, primary: Muscle, synergists: [Muscle],
    isCompound: Bool, pattern: MovementPattern = .isolation, equipment: Equipment
  ) {
    self.remoteID = remoteID
    self.name = name
    self.primary = primary.rawValue
    self.synergists = synergists.map(\.rawValue)
    self.equipment = equipment.rawValue
    self.isCompound = isCompound
    self.pattern = pattern.rawValue
  }

  var exercise: Exercise {
    Exercise(
      id: "custom_\(remoteID)",
      name: name,
      pattern: MovementPattern(rawValue: pattern) ?? .isolation,
      primary: Muscle(rawValue: primary) ?? .chest,
      synergists: synergists.compactMap(Muscle.init(rawValue:)),
      isCompound: isCompound,
      equipment: Equipment(rawValue: equipment) ?? .machine)
  }
}

enum CustomExerciseRegistry {
  static func reload(_ context: ModelContext) {
    let descriptor = FetchDescriptor<CustomExercise>(predicate: #Predicate { !$0.tombstoned })
    ExerciseDB.custom = ((try? context.fetch(descriptor)) ?? []).map(\.exercise)
  }
}
