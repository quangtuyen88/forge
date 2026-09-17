import SwiftUI
import ForgeCore

struct SwapSheet: View {
  @Environment(\.dismiss) private var dismiss
  let current: Exercise
  let equipment: Set<Equipment>
  let pick: (Exercise) -> Void
  @State private var query = ""

  private var pool: [Exercise] {
    ExerciseDB.everything.filter { $0.primary == current.primary && equipment.contains($0.equipment) && $0.id != current.id }
  }

  private var filtered: [Exercise] {
    query.isEmpty ? pool : pool.filter { $0.localizedName.localizedCaseInsensitiveContains(query) }
  }

  var body: some View {
    NavigationStack {
      List(filtered) { exercise in
        Button {
          pick(exercise)
          dismiss()
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(exercise.localizedName).foregroundStyle(Theme.text).forgeBodyStrong()
            Text(exercise.equipment.rawValue.capitalized)
              .foregroundStyle(Theme.textSecondary).forgeCaption()
          }
        }
      }
      .searchable(text: $query)
      .navigationTitle("Swap exercise")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Cancel") { dismiss() } }
    }
  }
}

struct CoachSwapSheet: View {
  @Environment(\.dismiss) private var dismiss
  let planned: [Exercise]
  let equipment: Set<Equipment>
  let injuries: Set<InjuryFlag>
  let onPick: (Exercise, Exercise) -> Void

  var body: some View {
    NavigationStack {
      List(planned) { exercise in
        NavigationLink {
          replacementsList(from: exercise)
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(exercise.localizedName).foregroundStyle(Theme.text).forgeBodyStrong()
            Text(exercise.primary.a11yName)
              .foregroundStyle(Theme.textSecondary).forgeCaption()
          }
        }
      }
      .navigationTitle("Swap an exercise")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Cancel") { dismiss() } }
    }
  }

  private func replacementsList(from: Exercise) -> some View {
    let options = ExerciseDB.replacements(for: from, equipment: equipment, injuries: injuries)
    return List(options) { to in
      Button {
        onPick(from, to)
        dismiss()
      } label: {
        VStack(alignment: .leading, spacing: 2) {
          Text(to.localizedName).foregroundStyle(Theme.text).forgeBodyStrong()
          Text(reason(from: from, to: to))
            .foregroundStyle(Theme.textSecondary).forgeCaption()
        }
      }
    }
    .navigationTitle(from.localizedName)
    .navigationBarTitleDisplayMode(.inline)
  }

  private func reason(from: Exercise, to: Exercise) -> String {
    to.primary == from.primary ? "Same pattern · same muscle" : "Same pattern"
  }
}

struct PlatesSheet: View {
  @Environment(\.dismiss) private var dismiss
  let kg: Double
  let usesLb: Bool
  let bar: Double
  let plates: [Double]

  var body: some View {
    let target = usesLb ? Plates.kgToLb(kg) : kg
    let available = plates
    let result = Plates.perSide(target: target, bar: bar, available: available)
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.groupGap) {
          VStack(alignment: .leading, spacing: 12) {
            Text("Per side").forgeSection()
            Text(String(localized: "Target \(String(format: "%.1f", target)) \(usesLb ? "lb" : "kg") · bar \(String(format: "%.0f", bar))", bundle: L10n.bundle))
              .forgeLabel()
              .monospacedDigit()
            if let result {
              if result.isEmpty {
                Text("Bar only").forgeLabel()
              } else {
                barDrawing(result, available: available)
              }
            } else {
              Text("Not loadable with these plates").forgeLabel()
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
          .card()
          VStack(alignment: .leading, spacing: 12) {
            Text("Plates").forgeSection()
            // ponytail: LazyVGrid instead of a flow Layout — chips equalize width per row
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 8)], alignment: .leading, spacing: 8) {
              ForEach(available, id: \.self) { plate in
                Text(plateLabel(plate))
                  .forge(13, .medium)
                  .monospacedDigit()
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 8)
                  .background(Capsule().fill(Theme.track))
              }
            }
          }
          .card()
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 8)
      }
      .background(Theme.page)
      .navigationTitle("Plates")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Done") { dismiss() } }
    }
    .presentationDetents([.medium])
    .presentationBackground(Theme.page)
  }

  private func plateLabel(_ plate: Double) -> String {
    plate.formatted()
  }

  private func barDrawing(_ plates: [Double], available: [Double]) -> some View {
    let maxPlate = available.first ?? 1
    return HStack(alignment: .center, spacing: 3) {
      Capsule().fill(Theme.textSecondary).frame(width: 44, height: 8)
      ForEach(Array(plates.enumerated()), id: \.offset) { _, plate in
        let fraction = plate / maxPlate
        VStack(spacing: 4) {
          RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(Theme.ramp[min(4, max(1, Int(fraction * 3.99) + 1))])
            .frame(width: 12 + 12 * fraction, height: 36 + 64 * fraction)
          Text(plateLabel(plate))
            .forgeCaption()
            .monospacedDigit()
        }
      }
      Capsule().fill(Theme.textSecondary).frame(width: 18, height: 8)
    }
    .frame(maxWidth: .infinity, minHeight: 120, alignment: .leading)
  }
}

struct AddExerciseSheet: View {
  @Environment(\.dismiss) private var dismiss
  let equipment: Set<Equipment>
  let exclude: Set<String>
  let pick: (Exercise) -> Void
  @State private var query = ""
  @State private var showCreate = false

  private var filtered: [Exercise] {
    let pool = ExerciseDB.everything.filter { equipment.contains($0.equipment) && !exclude.contains($0.id) }
    return query.isEmpty ? pool : pool.filter { $0.localizedName.localizedCaseInsensitiveContains(query) }
  }

  private var groups: [(muscle: Muscle, exercises: [Exercise])] {
    Dictionary(grouping: filtered, by: \.primary)
      .sorted { $0.key.a11yName < $1.key.a11yName }
      .map { ($0.key, $0.value) }
  }

  var body: some View {
    NavigationStack {
      List {
        ForEach(groups, id: \.muscle) { group in
          Section {
            ForEach(group.exercises) { exercise in
              Button {
                pick(exercise)
                dismiss()
              } label: {
                VStack(alignment: .leading, spacing: 2) {
                  Text(exercise.localizedName).foregroundStyle(Theme.text).forgeBodyStrong()
                  Text(exercise.equipment.rawValue.capitalized)
                    .foregroundStyle(Theme.textSecondary).forgeCaption()
                }
              }
            }
          } header: {
            Text(group.muscle.a11yName).forgeLabel()
          }
        }
        Section {
          Button {
            showCreate = true
          } label: {
            Label("Create custom exercise…", systemImage: "plus.circle")
              .foregroundStyle(Theme.text).forgeBodyStrong()
          }
        }
      }
      .searchable(text: $query)
      .navigationTitle("Add exercise")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar { Button("Cancel") { dismiss() } }
      .sheet(isPresented: $showCreate) {
        CustomExerciseForm { exercise in
          pick(exercise)
          dismiss()
        }
      }
    }
  }
}

struct NoteSheet: View {
  @Environment(\.dismiss) private var dismiss
  let title: String
  @Binding var text: String

  var body: some View {
    NavigationStack {
      TextEditor(text: $text)
        .forgeBody()
        .frame(height: 160)
        .padding(.horizontal, Theme.margin)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Done") { dismiss() } }
    }
    .presentationDetents([.medium])
    .presentationBackground(Theme.page)
  }
}
