public enum Badge: String, CaseIterable, Sendable {
  case firstSession, tenSessions, fiftySessions, hundredSessions
  case fourWeekStreak, twelveWeekStreak
  case tonnage100k, tonnage1M
  case firstPR, tenPRs

  public var title: String {
    switch self {
    case .firstSession: return String(localized: "First Session", bundle: .module)
    case .tenSessions: return String(localized: "Ten Sessions", bundle: .module)
    case .fiftySessions: return String(localized: "Fifty Sessions", bundle: .module)
    case .hundredSessions: return String(localized: "Hundred Sessions", bundle: .module)
    case .fourWeekStreak: return String(localized: "4-Week Streak", bundle: .module)
    case .twelveWeekStreak: return String(localized: "12-Week Streak", bundle: .module)
    case .tonnage100k: return String(localized: "100 Tonne Club", bundle: .module)
    case .tonnage1M: return String(localized: "Kilotonne Club", bundle: .module)
    case .firstPR: return String(localized: "First PR", bundle: .module)
    case .tenPRs: return String(localized: "Ten PRs", bundle: .module)
    }
  }

  public var symbol: String {
    switch self {
    case .firstSession: return "figure.strengthtraining.functional"
    case .tenSessions: return "10.circle.fill"
    case .fiftySessions: return "50.circle.fill"
    case .hundredSessions: return "medal.fill"
    case .fourWeekStreak: return "flame.fill"
    case .twelveWeekStreak: return "flame"
    case .tonnage100k: return "scalemass.fill"
    case .tonnage1M: return "trophy.fill"
    case .firstPR: return "arrow.up.circle.fill"
    case .tenPRs: return "arrow.up.to.line.circle.fill"
    }
  }

  public var detail: String {
    switch self {
    case .firstSession: return String(localized: "You showed up. That's the hardest part.", bundle: .module)
    case .tenSessions: return String(localized: "Ten sessions logged. Habit forming.", bundle: .module)
    case .fiftySessions: return String(localized: "Fifty sessions logged. This is who you are now.", bundle: .module)
    case .hundredSessions: return String(localized: "A hundred sessions logged. Legend.", bundle: .module)
    case .fourWeekStreak: return String(localized: "Trained every week for a month.", bundle: .module)
    case .twelveWeekStreak: return String(localized: "Trained every week for a full mesocycle-plus.", bundle: .module)
    case .tonnage100k: return String(localized: "100,000 kg lifted in total.", bundle: .module)
    case .tonnage1M: return String(localized: "One million kg lifted in total.", bundle: .module)
    case .firstPR: return String(localized: "Your first personal record.", bundle: .module)
    case .tenPRs: return String(localized: "Ten personal records set.", bundle: .module)
    }
  }

  public var rule: String {
    switch self {
    case .firstSession: return String(localized: "Log one session.", bundle: .module)
    case .tenSessions: return String(localized: "Log ten sessions.", bundle: .module)
    case .fiftySessions: return String(localized: "Log fifty sessions.", bundle: .module)
    case .hundredSessions: return String(localized: "Log a hundred sessions.", bundle: .module)
    case .fourWeekStreak: return String(localized: "Train at least once a week for four weeks in a row.", bundle: .module)
    case .twelveWeekStreak: return String(localized: "Train at least once a week for twelve weeks in a row.", bundle: .module)
    case .tonnage100k: return String(localized: "Lift 100,000 kg in total.", bundle: .module)
    case .tonnage1M: return String(localized: "Lift one million kg in total.", bundle: .module)
    case .firstPR: return String(localized: "Set one personal record.", bundle: .module)
    case .tenPRs: return String(localized: "Set ten personal records.", bundle: .module)
    }
  }
}

public struct BadgeProgress: Identifiable, Sendable {
  public let badge: Badge
  public let progress: Int
  public let target: Int
  public var id: String { badge.rawValue }
  public var fraction: Double { min(1, Double(progress) / Double(max(target, 1))) }
}

extension Badges {
  public static func progress(sessions: Int, streakWeeks: Int, tonnageKg: Double, prCount: Int) -> [BadgeProgress] {
    func entry(_ badge: Badge, _ progress: Int, _ target: Int) -> BadgeProgress {
      BadgeProgress(badge: badge, progress: min(progress, target), target: target)
    }
    return [
      entry(.firstSession, sessions, 1),
      entry(.tenSessions, sessions, 10),
      entry(.fiftySessions, sessions, 50),
      entry(.hundredSessions, sessions, 100),
      entry(.fourWeekStreak, streakWeeks, 4),
      entry(.twelveWeekStreak, streakWeeks, 12),
      entry(.tonnage100k, Int(tonnageKg / 1000), 100),
      entry(.tonnage1M, Int(tonnageKg / 1000), 1000),
      entry(.firstPR, prCount, 1),
      entry(.tenPRs, prCount, 10),
    ]
  }
}

public enum Badges {
  public static func earned(sessions: Int, streakWeeks: Int, tonnageKg: Double, prCount: Int) -> [Badge] {
    Badge.allCases.filter { badge in
      switch badge {
      case .firstSession: return sessions >= 1
      case .tenSessions: return sessions >= 10
      case .fiftySessions: return sessions >= 50
      case .hundredSessions: return sessions >= 100
      case .fourWeekStreak: return streakWeeks >= 4
      case .twelveWeekStreak: return streakWeeks >= 12
      case .tonnage100k: return tonnageKg >= 100_000
      case .tonnage1M: return tonnageKg >= 1_000_000
      case .firstPR: return prCount >= 1
      case .tenPRs: return prCount >= 10
      }
    }
  }
}
