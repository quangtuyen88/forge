import Foundation
import ForgeCore

struct ProgressExportOptions: Equatable {
  enum Format: String, CaseIterable, Identifiable {
    case pdf, csv
    var id: String { rawValue }
  }

  var format: Format = .pdf
  var workouts = true
  var programChanges = true
  var records = true
  var bodyStats = false
  var notes = false
  var photos = false
}

/// A plain snapshot of what may be exported, so export code never queries the store itself.
struct ProgressExportSource {
  var sessions: [WorkoutSession]
  var decisions: [DecisionLogEntry]
  var measurements: [BodyMeasurement]
  var notes: [JourneyReflection]
  var photos: [ProgressPhoto]
  var profile: UserProfile?
}

struct ReportContent: Equatable {
  struct WeekBar: Equatable {
    let start: Date
    let volumeKg: Double
    let isCurrent: Bool
  }

  struct Workouts: Equatable {
    let sessions: Int
    let volumeText: String
    let weeks: [WeekBar]
  }

  struct Line: Equatable {
    let date: Date?
    let text: String
  }

  let title: String
  let rangeText: String
  let workouts: Workouts?
  let changes: [Line]?
  let records: [Line]?
  let bodyStats: [Line]?
  let notes: [Line]?
  let photos: Line?
  let withheldNotes: Bool
  let withheldPhotos: Bool
}

enum ProgressExport {

  @MainActor
  static func content(
    _ options: ProgressExportOptions, source: ProgressExportSource, now: Date = .now
  ) -> ReportContent {
    let usesLb = source.profile?.usesLb ?? false
    let unit = usesLb ? "lb" : "kg"
    let completed = source.sessions
      .filter { $0.completed && !$0.tombstoned }
      .sorted { $0.date < $1.date }

    let rangeText: String
    if let first = completed.first?.date, let last = completed.last?.date {
      let range = dateRange(first, last)
      let goal = source.profile.flatMap { Goal(rawValue: $0.goal) }?.name
      rangeText = goal.map { String(localized: "\(range) · \($0)", bundle: L10n.bundle) } ?? range
    } else {
      rangeText = String(localized: "No completed sessions yet", bundle: L10n.bundle)
    }

    var workouts: ReportContent.Workouts?
    if options.workouts {
      let calendar = TrainingMetrics.reportingCalendar()
      let current = TrainingMetrics.reportingWeek(containing: now, calendar: calendar).start
      let weeks: [ReportContent.WeekBar] = (0..<4).reversed().map { offset in
        let start = calendar.date(byAdding: .weekOfYear, value: -offset, to: current) ?? current
        let volume = completed
          .filter { TrainingMetrics.reportingWeek(containing: $0.date, calendar: calendar).start == start }
          .flatMap(\.sets)
          .reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
        return ReportContent.WeekBar(start: start, volumeKg: volume, isCurrent: offset == 0)
      }
      let volume = completed.flatMap(\.sets).reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
      workouts = ReportContent.Workouts(
        sessions: completed.count,
        volumeText: UnitFormat.weight(volume, usesLb: usesLb),
        weeks: weeks)
    }

    var changes: [ReportContent.Line]?
    if options.programChanges {
      changes = nilIfEmpty(
        source.decisions
          .filter { JourneyProgramChangePolicy.accepts($0.type) }
          .sorted { $0.date > $1.date }
          .prefix(10)
          .map { ReportContent.Line(date: $0.date, text: changeText($0, usesLb: usesLb)) })
    }

    var records: [ReportContent.Line]?
    if options.records {
      records = nilIfEmpty(
        bestEligibleSets(completed)
          .compactMap { best -> ReportContent.Line? in
            guard let exercise = ExerciseDB.find(best.set.exerciseID) else { return nil }
            return ReportContent.Line(
              date: best.set.loggedAt,
              text: String(
                localized: "\(exercise.localizedName) · \(UnitFormat.weight(best.e1rm, usesLb: usesLb))",
                bundle: L10n.bundle))
          }
          .prefix(5)
          .map { $0 })
    }

    var bodyStats: [ReportContent.Line]?
    if options.bodyStats {
      let weights = source.measurements
        .filter { !$0.tombstoned && $0.weightKg != nil }
        .sorted { $0.date < $1.date }
      if let latest = weights.last, let latestWeight = latest.weightKg {
        var lines = [
          ReportContent.Line(
            date: latest.date,
            text: String(
              localized: "\(Fmt.num(UnitFormat.plain(latestWeight, usesLb: usesLb))) \(unit)",
              bundle: L10n.bundle))
        ]
        if let first = weights.first, let firstWeight = first.weightKg, latest.date > first.date {
          let change = UnitFormat.plain(latestWeight - firstWeight, usesLb: usesLb)
            .formatted(
              .number.sign(strategy: .always()).precision(.fractionLength(0...1)).grouping(.never)
                .locale(L10n.locale))
          let since = exportDate("dMMM", first.date)
          lines.append(
            ReportContent.Line(
              date: nil,
              text: String(localized: "\(change) \(unit) since \(since)", bundle: L10n.bundle)))
        }
        bodyStats = lines
      }
    }

    var notes: [ReportContent.Line]?
    if options.notes {
      notes = nilIfEmpty(
        source.notes
          .filter { !$0.tombstoned }
          .sorted { ($0.day, $0.updatedAt) > ($1.day, $1.updatedAt) }
          .prefix(5)
          .map { ReportContent.Line(date: $0.day, text: String($0.text.prefix(200))) })
    }

    var photos: ReportContent.Line?
    if options.photos, let latest = source.photos.max(by: { $0.date < $1.date }) {
      photos = ReportContent.Line(
        date: latest.date,
        text: String(
          localized: "\(source.photos.count) progress photos · latest \(exportDate("dMMM", latest.date))",
          bundle: L10n.bundle))
    }

    return ReportContent(
      title: String(localized: "Regulift · Training summary", bundle: L10n.bundle),
      rangeText: rangeText,
      workouts: workouts,
      changes: changes,
      records: records,
      bodyStats: bodyStats,
      notes: notes,
      photos: photos,
      withheldNotes: !options.notes,
      withheldPhotos: !options.photos)
  }

  static func csv(_ options: ProgressExportOptions, source: ProgressExportSource) -> String {
    let iso: ISO8601DateFormatter = {
      let formatter = ISO8601DateFormatter()
      formatter.formatOptions = [.withInternetDateTime]
      return formatter
    }()
    let day: DateFormatter = {
      let formatter = DateFormatter()
      formatter.locale = Locale(identifier: "en_US_POSIX")
      formatter.dateFormat = "yyyy-MM-dd"
      return formatter
    }()
    let numbers = Locale(identifier: "en_US_POSIX")
    func num(_ value: Double) -> String {
      value.formatted(.number.precision(.fractionLength(0...3)).grouping(.never).locale(numbers))
    }
    func num1(_ value: Double) -> String {
      value.formatted(.number.precision(.fractionLength(1)).grouping(.never).locale(numbers))
    }
    func exerciseName(_ exerciseID: String) -> String {
      ExerciseDB.find(exerciseID)?.localizedName ?? exerciseID
    }
    func field(_ raw: String) -> String {
      let quoted = raw.contains { $0 == "," || $0 == "\"" || $0 == "\r" || $0 == "\n" }
      return quoted ? "\"" + raw.replacingOccurrences(of: "\"", with: "\"\"") + "\"" : raw
    }

    let completed = source.sessions
      .filter { $0.completed && !$0.tombstoned }
      .sorted { $0.date < $1.date }

    var table: [[String]] = []
    if options.workouts {
      for session in completed {
        for set in session.sets.sorted(by: { $0.setIndex < $1.setIndex }) {
          table.append([
            "workout_set", iso.string(from: set.loggedAt), set.exerciseID,
            exerciseName(set.exerciseID), String(set.setIndex + 1), num(set.weightKg),
            String(set.reps), set.effortReported ? num(set.rpe) : "", "", "", session.dayName,
          ])
        }
      }
    }
    if options.programChanges {
      for entry in source.decisions.filter({ JourneyProgramChangePolicy.accepts($0.type) })
        .sorted(by: { $0.date < $1.date })
      {
        let value = entry.toValue.map(num) ?? ""
        table.append([
          "program_change", iso.string(from: entry.date), entry.exerciseID ?? "",
          entry.exerciseID.map(exerciseName) ?? "", "", "", "", "", value,
          entry.type == "load_change" && !value.isEmpty ? "kg" : "", entry.humanSummary,
        ])
      }
    }
    if options.records {
      for best in bestEligibleSets(completed) {
        table.append([
          "record", iso.string(from: best.set.loggedAt), best.set.exerciseID,
          exerciseName(best.set.exerciseID), "", num(best.set.weightKg), String(best.set.reps),
          "", num1(best.e1rm), "kg", "",
        ])
      }
    }
    if options.bodyStats {
      for measurement in source.measurements.filter({ !$0.tombstoned }).sorted(by: { $0.date < $1.date }) {
        if let weight = measurement.weightKg {
          table.append([
            "body_stat", iso.string(from: measurement.date), "", "", "", "", "", "", num(weight),
            "kg", "body_weight",
          ])
        }
        if let bodyFat = measurement.bodyFatPercent {
          table.append([
            "body_stat", iso.string(from: measurement.date), "", "", "", "", "", "", num(bodyFat),
            "%", "body_fat_percent",
          ])
        }
        for tape in measurement.tape.sorted(by: { $0.key < $1.key }) {
          table.append([
            "body_stat", iso.string(from: measurement.date), "", "", "", "", "", "", num(tape.value),
            "cm", "tape_\(tape.key)",
          ])
        }
      }
    }
    if options.notes {
      for note in source.notes.filter({ !$0.tombstoned }).sorted(by: { ($0.day, $0.updatedAt) < ($1.day, $1.updatedAt) }) {
        table.append(["note", day.string(from: note.day), "", "", "", "", "", "", "", "", note.text])
      }
    }
    if options.photos {
      for photo in source.photos.sorted(by: { $0.date < $1.date }) {
        table.append(["photo", iso.string(from: photo.date), "", "", "", "", "", "", "", "", photo.pose])
      }
    }

    let header = "record_type,date,exercise_id,exercise,set,weight_kg,reps,rpe,value,unit,detail"
    let lines = [header] + table.map { $0.map(field).joined(separator: ",") }
    return lines.joined(separator: "\n") + "\n"
  }

  /// Writes the chosen format to the temporary directory ("Regulift progress.pdf" / ".csv") and returns its URL.
  @MainActor
  static func fileURL(
    _ options: ProgressExportOptions, source: ProgressExportSource, now: Date = .now
  ) -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("Regulift progress.\(options.format.rawValue)")
    switch options.format {
    case .pdf:
      try? ReportPDF.data(content(options, source: source, now: now)).write(to: url)
    case .csv:
      try? csv(options, source: source).write(to: url, atomically: true, encoding: .utf8)
    }
    return url
  }

  /// "1–24 Sep 2026" in the reader's own date order.
  private static func dateRange(_ first: Date, _ last: Date) -> String {
    let formatter = DateIntervalFormatter()
    formatter.locale = L10n.locale
    formatter.dateTemplate = "dMMMyyyy"
    return formatter.string(from: first, to: last)
  }

  /// A date from a skeleton ("dMMM"), ordered the way the reader's locale writes it.
  private static func exportDate(_ template: String, _ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = L10n.locale
    formatter.setLocalizedDateFormatFromTemplate(template)
    return formatter.string(from: date)
  }

  /// `Dumbbell Calf Raise · 40 kg → 43 kg`, or the ledger's own sentence when the decision
  /// names no exercise the catalogue knows.
  private static func changeText(_ entry: DecisionLogEntry, usesLb: Bool) -> String {
    let unit = usesLb ? "lb" : "kg"
    func load(_ kg: Double) -> String {
      String(localized: "\(Fmt.num(UnitFormat.plain(kg, usesLb: usesLb))) \(unit)", bundle: L10n.bundle)
    }
    guard let id = entry.exerciseID, let exercise = ExerciseDB.find(id) else {
      return entry.humanSummary
    }
    switch (entry.fromValue, entry.toValue) {
    case let (from?, to?):
      return String(
        localized: "\(exercise.localizedName) · \(load(from)) → \(load(to))", bundle: L10n.bundle)
    case let (from?, nil):
      return String(localized: "\(exercise.localizedName) · \(load(from))", bundle: L10n.bundle)
    case let (nil, to?):
      return String(localized: "\(exercise.localizedName) · \(load(to))", bundle: L10n.bundle)
    default:
      return exercise.localizedName
    }
  }

  /// The PR board rule: over completed sessions, the trusted set with the highest Epley e1RM
  /// per exercise; an earlier set wins ties.
  private static func bestEligibleSets(_ sessions: [WorkoutSession]) -> [(set: LoggedSet, e1rm: Double)] {
    var bests: [String: (set: LoggedSet, e1rm: Double)] = [:]
    for session in sessions where session.completed {
      for set in session.trustedSets {
        let e1rm = Strength.epley(weightKg: set.weightKg, reps: set.reps)
        if e1rm > bests[set.exerciseID]?.e1rm ?? 0 {
          bests[set.exerciseID] = (set: set, e1rm: e1rm)
        }
      }
    }
    return bests.values.sorted { $0.e1rm > $1.e1rm }
  }

  private static func nilIfEmpty(_ lines: [ReportContent.Line]) -> [ReportContent.Line]? {
    lines.isEmpty ? nil : lines
  }
}
