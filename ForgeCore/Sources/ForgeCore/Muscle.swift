public enum Muscle: String, CaseIterable, Codable, Sendable {
  case chest, back, quads, hamstrings, glutes, sideDelts, rearDelts, frontDelts, triceps, biceps, calves, abs, forearms
}

public enum BodyRegion: String, CaseIterable, Sendable {
  case back, legs, chest, shoulders, arms, core
}

extension Muscle {
  public var region: BodyRegion {
    switch self {
    case .chest: return .chest
    case .back: return .back
    case .quads, .hamstrings, .glutes, .calves: return .legs
    case .frontDelts, .sideDelts, .rearDelts: return .shoulders
    case .biceps, .triceps, .forearms: return .arms
    case .abs: return .core
    }
  }
}

public enum BodyRegions {
  /// Regions with worked volume, most worked first; equal totals keep `BodyRegion.allCases` order.
  public static func worked(_ volume: [Muscle: Double]) -> [BodyRegion] {
    var totals: [BodyRegion: Double] = [:]
    for (muscle, value) in volume {
      totals[muscle.region, default: 0] += value
    }
    let worked = totals.filter { $0.value > 0 }
    return worked.keys.sorted { lhs, rhs in
      if worked[lhs]! != worked[rhs]! {
        return worked[lhs]! > worked[rhs]!
      }
      return BodyRegion.allCases.firstIndex(of: lhs)! < BodyRegion.allCases.firstIndex(of: rhs)!
    }
  }
}
