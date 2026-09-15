import Foundation

public enum WorkoutImport {
  public enum Source: Equatable { case strong, hevy }

  public struct ImportedSet: Equatable {
    public let exerciseName: String
    public let setIndex: Int
    public let weightKg: Double
    public let reps: Int
    public let rpe: Double?
  }

  public struct ImportedSession: Equatable {
    public let date: Date
    public let name: String
    public let durationSeconds: Int?
    public let notes: String
    public let sets: [ImportedSet]
  }

  public struct Result: Equatable {
    public let source: Source
    public let sessions: [ImportedSession]
    public let unmatchedNames: [String]
    public let droppedSets: Int
    /// Unit the parsed weights were read as (explicit per-row/column units win; picker only fills gaps).
    public let unitIsLb: Bool
  }

  // MARK: CSV reader

  private struct Table {
    let header: [String]
    let data: [[String]]

    func index(_ name: String) -> Int? { header.firstIndex(of: name) }

    func cell(_ row: [String], _ name: String) -> String {
      guard let i = index(name), i < row.count else { return "" }
      return row[i].trimmingCharacters(in: .whitespaces)
    }
  }

  private static func table(_ csv: String) -> Table? {
    var s = csv
    if s.hasPrefix("﻿") { s.removeFirst() }
    s = s.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
    let newline = s.firstIndex(of: "\n") ?? s.endIndex
    let headerLine = s[..<newline]
    let semis = headerLine.filter { $0 == ";" }.count
    let commas = headerLine.filter { $0 == "," }.count
    let delim: Character = semis > commas ? ";" : ","
    let chars = Array(s)
    var rows: [[String]] = []
    var fields: [String] = []
    var field = ""
    var quoted = false
    var i = 0
    while i < chars.count {
      let c = chars[i]
      if quoted {
        if c == "\"" {
          if i + 1 < chars.count, chars[i + 1] == "\"" {
            field.append("\"")
            i += 2
            continue
          }
          quoted = false
        } else {
          field.append(c)
        }
      } else if c == "\"" {
        quoted = true
      } else if c == delim {
        fields.append(field)
        field = ""
      } else if c == "\n" {
        fields.append(field)
        field = ""
        rows.append(fields)
        fields = []
      } else {
        field.append(c)
      }
      i += 1
    }
    if !field.isEmpty || !fields.isEmpty { fields.append(field); rows.append(fields) }
    guard let header = rows.first, !header.isEmpty else { return nil }
    return Table(header: header.map { $0.lowercased().trimmingCharacters(in: .whitespaces) }, data: Array(rows.dropFirst()))
  }

  // MARK: detect / parse

  public static func detect(_ csv: String) -> Source? {
    guard let t = table(csv) else { return nil }
    if t.index("exercise_title") != nil || t.index("start_time") != nil { return .hevy }
    if t.index("workout name") != nil || t.index("set order") != nil { return .strong }
    return nil
  }

  public static func parse(_ csv: String, assumeLb: Bool) -> Result? {
    guard let t = table(csv) else { return nil }
    switch detect(csv) {
    case .strong: return parseStrong(t, assumeLb: assumeLb)
    case .hevy: return parseHevy(t)
    case nil: return nil
    }
  }

  private static func makeFormatter(_ format: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = format
    return f
  }

  private static let strongFormats = [makeFormatter("yyyy-MM-dd HH:mm:ss"), makeFormatter("yyyy-MM-dd HH:mm")]
  private static let hevyFormat = makeFormatter("d MMM yyyy, HH:mm")
  private static let isoFormat = ISO8601DateFormatter()
  private static let lbPerKg = 0.45359237

  private static func number(_ s: String) -> Double? {
    Double(s.replacingOccurrences(of: ",", with: "."))
  }

  private static func durationSeconds(_ raw: String) -> Int? {
    let s = raw.replacingOccurrences(of: " ", with: "").lowercased()
    guard !s.isEmpty else { return nil }
    if s.contains(":") {
      let parts = s.split(separator: ":").compactMap { Int($0) }
      guard parts.count == 3 else { return nil }
      return parts[0] * 3600 + parts[1] * 60 + parts[2]
    }
    var total = 0
    var found = false
    var num = ""
    for c in s {
      if c.isNumber {
        num.append(c)
      } else if let v = Int(num) {
        switch c {
        case "h": total += v * 3600; found = true
        case "m": total += v * 60; found = true
        case "s": total += v; found = true
        default: break
        }
        num = ""
      } else {
        num = ""
      }
    }
    return found ? total : nil
  }

  private final class Builder {
    let date: Date
    let name: String
    var sets: [ImportedSet] = []
    var notes = ""
    var durationSeconds: Int?
    init(date: Date, name: String) {
      self.date = date
      self.name = name
    }
  }

  private static func finish(_ source: Source, _ order: [String], _ groups: [String: Builder], unmatched: [String], dropped: Int, unitIsLb: Bool) -> Result {
    let sessions = order.compactMap { key -> ImportedSession? in
      guard let b = groups[key], !b.sets.isEmpty else { return nil }
      return ImportedSession(date: b.date, name: b.name, durationSeconds: b.durationSeconds, notes: b.notes, sets: b.sets)
    }
    return Result(source: source, sessions: sessions, unmatchedNames: unmatched, droppedSets: dropped, unitIsLb: unitIsLb)
  }

  private static func parseStrong(_ t: Table, assumeLb: Bool) -> Result {
    var dropped = 0
    var unmatched: [String] = []
    var order: [String] = []
    var groups: [String: Builder] = [:]
    var lbUnitRows = 0
    var unitRows = 0

    for row in t.data {
      guard Int(t.cell(row, "set order")) != nil else { continue }
      let exerciseName = t.cell(row, "exercise name")
      guard !exerciseName.isEmpty else { continue }
      let dateStr = t.cell(row, "date")
      let workout = t.cell(row, "workout name")
      guard let date = strongFormats.lazy.compactMap({ $0.date(from: dateStr) }).first ?? isoFormat.date(from: dateStr) else { continue }
      let weightStr = t.cell(row, "weight")
      let repsStr = t.cell(row, "reps")
      guard match(exerciseName) != nil else {
        if !unmatched.contains(exerciseName) { unmatched.append(exerciseName) }
        dropped += 1
        continue
      }
      if weightStr.isEmpty && repsStr.isEmpty { dropped += 1; continue }
      let unit = t.cell(row, "weight unit")
      let lb = unit.isEmpty ? assumeLb : unit.lowercased().contains("lb")
      if !unit.isEmpty {
        unitRows += 1
        if lb { lbUnitRows += 1 }
      }
      let rpeStr = t.cell(row, "rpe")
      let key = dateStr + "\u{0}" + workout
      if groups[key] == nil {
        order.append(key)
        groups[key] = Builder(date: date, name: workout.isEmpty ? "Workout" : workout)
      }
      let b = groups[key]!
      b.sets.append(ImportedSet(
        exerciseName: exerciseName,
        setIndex: Int(t.cell(row, "set order")) ?? b.sets.count + 1,
        weightKg: (number(weightStr) ?? 0) * (lb ? lbPerKg : 1),
        reps: Int(repsStr) ?? Int(number(repsStr) ?? 0),
        rpe: rpeStr.isEmpty ? nil : number(rpeStr)))
      if b.notes.isEmpty { b.notes = t.cell(row, "workout notes") }
      if b.durationSeconds == nil, !t.cell(row, "duration").isEmpty {
        b.durationSeconds = durationSeconds(t.cell(row, "duration"))
      }
    }
    return finish(.strong, order, groups, unmatched: unmatched, dropped: dropped, unitIsLb: unitRows > 0 ? lbUnitRows * 2 >= unitRows : assumeLb)
  }

  private static func parseHevy(_ t: Table) -> Result {
    var dropped = 0
    var unmatched: [String] = []
    var order: [String] = []
    var groups: [String: Builder] = [:]
    let lbColumn = t.index("weight_lbs") != nil
    let weightColumn = lbColumn ? "weight_lbs" : "weight_kg"

    for row in t.data {
      if t.cell(row, "set_type").lowercased() == "warmup" { continue }
      let exerciseName = t.cell(row, "exercise_title")
      guard !exerciseName.isEmpty else { continue }
      let title = t.cell(row, "title")
      let startStr = t.cell(row, "start_time")
      guard let date = hevyFormat.date(from: startStr) ?? isoFormat.date(from: startStr) else { continue }
      let weightStr = t.cell(row, weightColumn)
      let repsStr = t.cell(row, "reps")
      guard match(exerciseName) != nil else {
        if !unmatched.contains(exerciseName) { unmatched.append(exerciseName) }
        dropped += 1
        continue
      }
      if weightStr.isEmpty && repsStr.isEmpty { dropped += 1; continue }
      let key = title + "\u{0}" + startStr
      if groups[key] == nil {
        order.append(key)
        groups[key] = Builder(date: date, name: title.isEmpty ? "Workout" : title)
      }
      let b = groups[key]!
      let rpeStr = t.cell(row, "rpe")
      b.sets.append(ImportedSet(
        exerciseName: exerciseName,
        setIndex: Int(t.cell(row, "set_index")) ?? b.sets.count + 1,
        weightKg: (number(weightStr) ?? 0) * (lbColumn ? lbPerKg : 1),
        reps: Int(repsStr) ?? Int(number(repsStr) ?? 0),
        rpe: rpeStr.isEmpty ? nil : number(rpeStr)))
      if b.notes.isEmpty { b.notes = t.cell(row, "description") }
      if b.durationSeconds == nil {
        let endStr = t.cell(row, "end_time")
        if let end = hevyFormat.date(from: endStr) ?? isoFormat.date(from: endStr) {
          b.durationSeconds = max(0, Int(end.timeIntervalSince(date)))
        }
      }
    }
    return finish(.hevy, order, groups, unmatched: unmatched, dropped: dropped, unitIsLb: lbColumn)
  }

  // MARK: name matching

  static func normalise(_ name: String) -> String {
    var s = name.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    if let open = s.lastIndex(of: "("), s.hasSuffix(")") {
      let inner = String(s[s.index(after: open)..<s.index(before: s.endIndex)])
      s = inner + " " + String(s[..<open])
    }
    var collapsed = ""
    for c in s {
      collapsed.append((c.isLetter || c.isNumber) ? c : " ")
    }
    return collapsed.split(separator: " ").joined(separator: " ")
  }

  public static func match(_ name: String) -> Exercise? {
    let key = normalise(name)
    guard !key.isEmpty else { return nil }
    // ponytail: name map rebuilt per call — custom exercises must be visible; cache only if import volume ever matters
    var byName: [String: Exercise] = [:]
    for e in ExerciseDB.everything where byName[normalise(e.name)] == nil { byName[normalise(e.name)] = e }
    if let exact = byName[key] { return exact }
    if let id = aliases[key], let e = ExerciseDB.find(id) { return e }
    let words = Set(key.split(separator: " ").map(String.init))
    guard !words.isEmpty else { return nil }
    var best: (Exercise, Double)?
    for e in ExerciseDB.everything {
      let dbWords = Set(normalise(e.name).split(separator: " ").map(String.init))
      let j = Double(words.intersection(dbWords).count) / Double(words.union(dbWords).count)
      if j >= 0.6, j > (best?.1 ?? 0) { best = (e, j) }
    }
    return best?.0
  }

  // ponytail: alias list covers the common Strong/Hevy names; Jaccard fallback handles the long tail
  private static let aliases: [String: String] = [
    "squat": "back_squat", "barbell squat": "back_squat", "squats": "back_squat",
    "bench": "barbell_bench", "bench press": "barbell_bench", "flat bench press": "barbell_bench",
    "dumbbell bench press": "flat_db_bench_press", "db bench press": "flat_db_bench_press",
    "deadlift": "deadlift", "barbell deadlift": "deadlift",
    "overhead press": "overhead_press", "barbell overhead press": "overhead_press", "ohp": "overhead_press",
    "military press": "overhead_press", "shoulder press": "overhead_press",
    "dumbbell shoulder press": "seated_db_press", "dumbbell press": "seated_db_press",
    "bent over row": "bent_row", "barbell bent over row": "bent_row", "barbell row": "bent_row",
    "romanian deadlift": "romanian_deadlift", "barbell romanian deadlift": "romanian_deadlift", "rdl": "romanian_deadlift",
    "dumbbell romanian deadlift": "db_romanian_deadlift",
    "lat pulldown": "lat_pulldown", "cable lat pulldown": "lat_pulldown", "pull down": "lat_pulldown",
    "seated row": "seated_cable_row", "cable row": "seated_cable_row",
    "pull up": "pull_up", "pull ups": "pull_up", "pullup": "pull_up", "pullups": "pull_up",
    "chin up": "chin_up", "chin ups": "chin_up", "chinup": "chin_up", "chinups": "chin_up",
    "dip": "dips", "triceps dip": "dips", "chest dip": "weighted_chest_dip",
    "leg curl": "leg_curl", "hamstring curl": "leg_curl",
    "hip thrust": "hip_thrust",
    "dumbbell bulgarian split squat": "bulgarian_split_squat",
    "lunge": "lunge", "lunges": "lunge", "dumbbell lunge": "lunge",
    "lateral raise": "lateral_raise", "side lateral raise": "lateral_raise", "db lateral raise": "lateral_raise",
    "cable face pull": "face_pull",
    "curl": "barbell_curl", "curls": "barbell_curl", "bicep curl": "barbell_curl", "biceps curl": "barbell_curl",
    "dumbbell curl": "seated_db_curl", "dumbbell hammer curl": "hammer_curl",
    "triceps pushdown": "tricep_pushdown", "cable pushdown": "tricep_pushdown", "rope pushdown": "tricep_pushdown",
    "tricep pulldown": "tricep_pushdown",
    "skull crusher": "skullcrusher", "skull crushers": "skullcrusher", "lying triceps extension": "skullcrusher",
    "incline bench": "incline_barbell_press", "incline bench press": "incline_barbell_press",
    "barbell incline bench press": "incline_barbell_press", "incline press": "incline_barbell_press",
    "dumbbell incline press": "incline_db_press", "incline db press": "incline_db_press",
    "calf raise": "standing_calf_raise", "calf raises": "standing_calf_raise",
    "crunch": "cable_crunch", "crunches": "cable_crunch", "planks": "plank",
    "shrug": "barbell_shrug", "shrugs": "barbell_shrug",
    "cable crossover": "cable_fly", "cable chest fly": "cable_fly", "chest fly": "db_fly", "butterfly": "pec_deck",
    "pec deck fly": "pec_deck",
    "upright row": "barbell_upright_row",
    "preacher curl": "ez_bar_preacher_curl",
    "glute bridges": "glute_bridge",
    "push up": "push_up", "push ups": "push_up", "pushup": "push_up", "pushups": "push_up",
    "tricep extension": "overhead_db_extension", "triceps extension": "overhead_db_extension",
    "dumbbell tricep extension": "overhead_db_extension", "overhead tricep extension": "overhead_db_extension",
  ]
}
