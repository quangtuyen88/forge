import SwiftUI
import SwiftData
import ForgeCore

enum UnitFormat {
  static func plain(_ kg: Double, usesLb: Bool) -> Double {
    usesLb ? Plates.kgToLb(kg) : kg
  }

  static func weight(_ kg: Double, usesLb: Bool) -> String {
    String(localized: "\(Int(plain(kg, usesLb: usesLb).rounded()).formatted()) \(usesLb ? "lb" : "kg")")
  }
}

private enum SessionMath {
  static func tonnageText(_ sessions: [WorkoutSession], usesLb: Bool) -> String {
    let kg = sessions.flatMap(\.sets).reduce(0.0) { $0 + $1.weightKg * Double($1.reps) }
    return Fmt.grouped(usesLb ? Plates.kgToLb(kg) : kg)
  }

  static func totalMinutes(_ sessions: [WorkoutSession]) -> Int {
    sessions.reduce(0) { total, session in
      let times = session.sets.map(\.loggedAt)
      guard let lo = times.min(), let hi = times.max(), hi > lo else { return total }
      return total + (Int(hi.timeIntervalSince(lo)) + 59) / 60
    }
  }
}

struct HistoryView: View {
  let usesLb: Bool
  @Query(sort: \WorkoutSession.date, order: .reverse) private var sessions: [WorkoutSession]
  @Query private var profiles: [UserProfile]

  private var months: [(date: Date, sessions: [WorkoutSession])] {
    let cal = Calendar.current
    let groups = Dictionary(grouping: sessions.filter { $0.completed && !$0.deleted }) {
      cal.dateInterval(of: .month, for: $0.date)?.start ?? $0.date
    }
    return groups
      .map { (date: $0.key, sessions: $0.value.sorted { $0.date > $1.date }) }
      .sorted { $0.date > $1.date }
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        WeekStrip(sessions: sessions, plannedDays: profiles.first?.daysPerWeek ?? 0)
          .padding(.horizontal, 6)
        ForEach(months, id: \.date) { month in
          VStack(alignment: .leading, spacing: 10) {
            Text(month.date, format: .dateTime.month(.wide).year()).forgeTitle()
            MonthTotalsRow(
              sessions: month.sessions.count,
              minutes: SessionMath.totalMinutes(month.sessions),
              sets: month.sessions.reduce(0) { $0 + $1.sets.count },
              tonnage: SessionMath.tonnageText(month.sessions, usesLb: usesLb),
              unit: usesLb ? "lb" : "kg")
            VStack(spacing: 0) {
              ForEach(Array(month.sessions.enumerated()), id: \.element.persistentModelID) { index, session in
                NavigationLink {
                  SessionDetailView(session: session, usesLb: usesLb)
                } label: {
                  SessionRow(
                    title: session.dayName,
                    value: SessionMath.tonnageText([session], usesLb: usesLb),
                    unit: usesLb ? "lb" : "kg",
                    trailing: String(localized: "\(session.date.formatted(.dateTime.month().day())) · \(session.sets.count) sets"))
                }
                .buttonStyle(RowPressStyle())
                if index < month.sessions.count - 1 { Divider().overlay(Theme.ring) }
              }
            }
            .card(padding: 10)
          }
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("History")
  }
}

struct SessionDetailView: View {
  let session: WorkoutSession
  let usesLb: Bool
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var editing = false
  @State private var confirmDelete = false
  @State private var editTracked = false

  private var orderedIDs: [String] {
    var seen: [String] = []
    for set in session.sets.sorted(by: { $0.setIndex < $1.setIndex }) where !seen.contains(set.exerciseID) {
      seen.append(set.exerciseID)
    }
    return seen
  }

  private var timeRange: String {
    let times = session.sets.sorted { $0.loggedAt < $1.loggedAt }.map(\.loggedAt)
    guard let first = times.first, let last = times.last else {
      return session.date.formatted(.dateTime.hour().minute())
    }
    if times.count == 1 { return first.formatted(.dateTime.hour().minute()) }
    return "\(first.formatted(.dateTime.hour().minute()))–\(last.formatted(.dateTime.hour().minute()))"
  }

  private var detailItems: [MetricItem] {
    var items = [
      MetricItem(String(localized: "Duration"), "\(SessionMath.totalMinutes([session]))", unit: "min"),
      MetricItem(String(localized: "Sets"), "\(session.sets.count)"),
      MetricItem(String(localized: "Tonnage"), SessionMath.tonnageText([session], usesLb: usesLb), unit: usesLb ? "lb" : "kg", color: Theme.accentValue),
      MetricItem(String(localized: "Exercises"), "\(orderedIDs.count)"),
    ]
    if !session.sets.isEmpty {
      items.append(MetricItem(String(localized: "Avg RPE"), Fmt.num(session.sets.reduce(0.0) { $0 + $1.rpe } / Double(session.sets.count))))
    }
    return items
  }

  var body: some View {
    ScrollView {
      VStack(spacing: Theme.groupGap) {
        SessionHeader(symbol: "dumbbell.fill", title: session.dayName, subtitle: timeRange, caption: "Week \(session.week)")
        VStack(alignment: .leading, spacing: 10) {
          Text("Workout details").forgeSection()
          MetricGrid(items: detailItems)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card()
        if !session.notes.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Notes").forgeSection()
            Text(session.notes).forgeLabel()
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()
        }
        ForEach(orderedIDs, id: \.self) { id in
          if let exercise = ExerciseDB.find(id) {
            exerciseCard(exercise, sets: session.sets.filter { $0.exerciseID == id }.sorted { $0.setIndex < $1.setIndex })
          }
        }
        if editing {
          Button(role: .destructive) {
            confirmDelete = true
          } label: {
            Text("Delete session")
              .forgeBody()
              .frame(maxWidth: .infinity, minHeight: 44)
          }
          .foregroundStyle(Theme.negative)
          .buttonStyle(.plain)
          .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(Theme.innerSurface))
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle(session.dayName)
    .navigationBarTitleDisplayMode(.inline)
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button(editing ? String(localized: "Done") : String(localized: "Edit")) {
          if editing { editTracked = false }
          editing.toggle()
        }
        .bold()
      }
    }
    .confirmationDialog("Delete this session?", isPresented: $confirmDelete, titleVisibility: .visible) {
      Button("Delete session", role: .destructive) {
        Analytics.track("session_deleted")
        Task { await deleteSession() }
      }
    }
  }

  private func touch() {
    session.updatedAt = .now
    try? modelContext.save()
    if !editTracked {
      Analytics.track("set_edited")
      editTracked = true
    }
  }

  private func deleteSet(_ set: LoggedSet) {
    session.sets.removeAll { $0.persistentModelID == set.persistentModelID }
    modelContext.delete(set)
    touch()
  }

  @MainActor private func deleteSession() async {
    if AuthClient.shared.user != nil {
      session.deleted = true
      session.updatedAt = .now
      try? modelContext.save()
      await SyncEngine.shared.sync()
    }
    dismiss()
    modelContext.delete(session)
    try? modelContext.save()
  }

  private func exerciseCard(_ exercise: Exercise, sets: [LoggedSet]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(exercise.name).forgeBodyStrong()
        Spacer()
        if let best = sets.map({ Strength.epley(weightKg: $0.weightKg, reps: $0.reps) }).max() {
          HStack(spacing: 4) {
            Text("e1RM").forgeCaption()
            MetricValue(value: Fmt.num(UnitFormat.plain(best, usesLb: usesLb)), unit: usesLb ? "lb" : "kg", size: 16, color: Theme.accentValue)
          }
        }
      }
      ForEach(sets, id: \.persistentModelID) { set in
        if editing {
          EditSetRow(set: set, usesLb: usesLb, onChange: touch, onDelete: deleteSet)
        } else {
          HStack(spacing: 8) {
            Text("\(Int(UnitFormat.plain(set.weightKg, usesLb: usesLb).rounded())) × \(set.reps) @ \(set.rpe, specifier: "%g")")
              .forgeLabel()
              .monospacedDigit()
            if set.variant != "straight", let label = SetVariant(rawValue: set.variant)?.label {
              Text(label)
                .forge(11, .semibold)
                .foregroundColor(Theme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(RoundedRectangle(cornerRadius: Theme.radiusChip).fill(Theme.accent.opacity(0.12)))
            }
            Spacer()
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }
}

private struct EditSetRow: View {
  let set: LoggedSet
  let usesLb: Bool
  let onChange: () -> Void
  let onDelete: (LoggedSet) -> Void

  @State private var weightText = ""

  var body: some View {
    HStack(spacing: 10) {
      TextField("Weight", text: Binding(
        get: { weightText },
        set: { text in
          weightText = text
          // ponytail: comma→dot parse only, no locale-aware grouping handling
          if let v = Double(text.replacingOccurrences(of: ",", with: ".")), v > 0 {
            set.weightKg = usesLb ? Plates.lbToKg(v) : v
            onChange()
          }
        }))
        .keyboardType(.decimalPad)
        .multilineTextAlignment(.center)
        .frame(width: 64)
        .innerSurface(padding: 8)
        .forgeLabel()
      Text(usesLb ? "lb" : "kg").forgeCaption()
      Stepper(value: Binding(
        get: { set.reps },
        set: { set.reps = $0; onChange() }), in: 1...50) {
        Text("\(set.reps) reps").forgeLabel().monospacedDigit().fixedSize()
      }
      Menu {
        ForEach([6.0, 6.5, 7, 7.5, 8, 8.5, 9, 9.5, 10], id: \.self) { rpe in
          Button(Fmt.num(rpe)) {
            set.rpe = rpe
            onChange()
          }
        }
      } label: {
        Text("RPE \(Fmt.num(set.rpe))")
          .forgeLabel()
          .monospacedDigit()
          .innerSurface(padding: 8)
      }
      Button {
        onDelete(set)
      } label: {
        Image(systemName: "trash")
          .foregroundStyle(Theme.negative)
          .frame(width: 32, height: 32)
      }
    }
    .onAppear {
      if weightText.isEmpty { weightText = Fmt.num(UnitFormat.plain(set.weightKg, usesLb: usesLb)) }
    }
  }
}
