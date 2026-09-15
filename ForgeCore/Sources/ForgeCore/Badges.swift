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
