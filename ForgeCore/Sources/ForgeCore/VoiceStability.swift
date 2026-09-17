import Foundation

public extension VoiceCommand {
  /// `fastLogging` is the lifter's opt-in: valid sets log straight away with an Undo.
  public func consequence(fastLogging: Bool) -> VoiceConsequence {
    switch self {
    case .logSet, .completeSet:
      return fastLogging ? .undoable : .confirm
    case .changeWeight, .changeReps, .changeRPE:
      return .undoable
    case .startRest, .skipRest, .nextExercise, .confirm, .cancel, .undo, .askCoach, .unrecognised:
      return .immediate
    case .swapExercise:
      return .confirm
    }
  }

  /// Stable identity for one intended action: same command, same numbers, same fingerprint.
  public var fingerprint: String {
    switch self {
    case .logSet(let p):
      return "logSet:\(p.exerciseID):\(p.weightKg):\(p.reps):\(p.rpe.map { String($0) } ?? "-")"
    case .completeSet:
      return "completeSet"
    case .startRest(let seconds):
      return "startRest:\(seconds.map { String($0) } ?? "-")"
    case .skipRest:
      return "skipRest"
    case .changeWeight(let deltaKg):
      return "changeWeight:\(deltaKg)"
    case .changeReps(let to, let delta):
      return "changeReps:\(to.map { String($0) } ?? "-"):\(delta.map { String($0) } ?? "-")"
    case .changeRPE(let rpe):
      return "changeRPE:\(rpe)"
    case .nextExercise:
      return "nextExercise"
    case .askCoach(let q):
      return "askCoach:\(q)"
    case .swapExercise(let exerciseID):
      return "swapExercise:\(exerciseID)"
    case .confirm:
      return "confirm"
    case .cancel:
      return "cancel"
    case .undo:
      return "undo"
    case .unrecognised(let raw):
      return "unrecognised:\(raw)"
    }
  }
}

/// Stops a partial transcript and its final form from committing the same action twice.
public struct VoiceCommitLog: Sendable {
  private struct Entry: Sendable {
    let utteranceID: UUID
    let fingerprint: String
  }

  private let window: Int
  private var entries: [Entry] = []

  public init(window: Int = 8) {
    self.window = window
  }

  /// False when this exact command was already committed for this utterance.
  public mutating func shouldCommit(_ command: VoiceCommand, utteranceID: UUID) -> Bool {
    let fingerprint = command.fingerprint
    if entries.contains(where: { $0.utteranceID == utteranceID && $0.fingerprint == fingerprint }) {
      return false
    }
    entries.append(Entry(utteranceID: utteranceID, fingerprint: fingerprint))
    if entries.count > window {
      entries.removeFirst(entries.count - window)
    }
    return true
  }
}

/// Holds a spoken command until it has looked the same several times in a row or
/// held steady, so a mid-sentence transcript never fires an action early.
public struct VoiceStabilizer: Sendable {
  private let repeatsRequired: Int
  private let holdFor: TimeInterval
  private var streak = 0
  private var lastCandidate: VoiceCandidate?
  private var firstSeenAt: Date?

  public init(repeatsRequired: Int = 2, holdFor: TimeInterval = 0.35) {
    self.repeatsRequired = repeatsRequired
    self.holdFor = holdFor
  }

  public mutating func offer(_ candidate: VoiceCandidate?, at now: Date) -> VoiceCommand? {
    guard let candidate, candidate.isComplete else {
      // Incomplete (or nothing): break the run but keep the last complete candidate.
      streak = 0
      firstSeenAt = nil
      return nil
    }

    if lastCandidate == candidate {
      streak += 1
    } else {
      lastCandidate = candidate
      streak = 1
      firstSeenAt = now
    }

    let heldSteady = firstSeenAt.map { now.timeIntervalSince($0) >= holdFor } ?? false
    if streak >= repeatsRequired || heldSteady {
      streak = 0
      firstSeenAt = nil
      return candidate.command
    }
    return nil
  }

  public mutating func reset() {
    streak = 0
    lastCandidate = nil
    firstSeenAt = nil
  }
}

/// Endpointing and timing policy owned by the engine so the numbers are testable in one place.
public enum VoiceTiming {
  public static let minSpeech: TimeInterval = 0.25
  public static let silenceToFinalize: TimeInterval = 0.7
  public static let commandHardCap: TimeInterval = 6
  public static let askCoachHardCap: TimeInterval = 20
  public static let preRoll: TimeInterval = 0.4
}
