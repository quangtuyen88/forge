public enum Badge: String, CaseIterable, Sendable {
  case firstSession, tenSessions, fiftySessions, hundredSessions
  case fourWeekStreak, twelveWeekStreak
  case tonnage100k, tonnage1M
  case firstPR, tenPRs

  public var title: String {
    switch self {
    case .firstSession: return "First Session"
    case .tenSessions: return "Ten Sessions"
    case .fiftySessions: return "Fifty Sessions"
    case .hundredSessions: return "Hundred Sessions"
    case .fourWeekStreak: return "4-Week Streak"
    case .twelveWeekStreak: return "12-Week Streak"
    case .tonnage100k: return "100 Tonne Club"
    case .tonnage1M: return "Kilotonne Club"
    case .firstPR: return "First PR"
    case .tenPRs: return "Ten PRs"
    }
  }

  public var symbol: String {
    switch self {
    case .firstSession: return "figure.strengthtraining.functional"
    case .tenSessions: return "10.circle.fill"
    case .fiftySessions: return "50.circle.fill"
    case .hundredSessions: return "100.circle.fill"
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
    case .firstSession: return "You showed up. That's the hardest part."
    case .tenSessions: return "Ten sessions logged. Habit forming."
    case .fiftySessions: return "Fifty sessions logged. This is who you are now."
    case .hundredSessions: return "A hundred sessions logged. Legend."
    case .fourWeekStreak: return "Trained every week for a month."
    case .twelveWeekStreak: return "Trained every week for a full mesocycle-plus."
    case .tonnage100k: return "100,000 kg lifted in total."
    case .tonnage1M: return "One million kg lifted in total."
    case .firstPR: return "Your first personal record."
    case .tenPRs: return "Ten personal records set."
    }
  }

  public var rule: String {
    switch self {
    case .firstSession: return "Log one session."
    case .tenSessions: return "Log ten sessions."
    case .fiftySessions: return "Log fifty sessions."
    case .hundredSessions: return "Log a hundred sessions."
    case .fourWeekStreak: return "Train at least once a week for four weeks in a row."
    case .twelveWeekStreak: return "Train at least once a week for twelve weeks in a row."
    case .tonnage100k: return "Lift 100,000 kg in total."
    case .tonnage1M: return "Lift one million kg in total."
    case .firstPR: return "Set one personal record."
    case .tenPRs: return "Set ten personal records."
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
