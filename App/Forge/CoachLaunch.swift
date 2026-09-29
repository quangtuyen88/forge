import Foundation

/// What a Today entry point asks the coach: open voice mode listening, or send a known question.
struct CoachLaunch: Identifiable, Equatable {
  let id = UUID()
  var question: String? = nil
  var evidence: CoachEvidenceKind? = nil
}

/// Evidence card shown under the coach's answer for Today questions.
enum CoachEvidenceKind: String, Equatable { case todayPlan, lastWorkout }
