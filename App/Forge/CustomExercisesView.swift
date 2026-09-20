import ForgeCore
import SwiftData
import SwiftUI

struct CustomExercisesView: View {
  @Environment(\.modelContext) private var modelContext
  @Query(filter: #Predicate<CustomExercise> { !$0.tombstoned }, sort: \CustomExercise.name)
  private var exercises: [CustomExercise]
  @State private var showAdd = false
  @State private var editing: CustomExercise?

  var body: some View {
    List {
      if exercises.isEmpty {
        Text("Add lifts Regulift doesn't know. They count toward the muscle you pick.")
          .forgeLabel()
      }
      ForEach(exercises) { custom in
        Button {
          editing = custom
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text(custom.name).foregroundStyle(Theme.text).forgeBodyStrong()
            Text(
              "\(custom.exercise.primary.a11yName) · \(Equipment(rawValue: custom.equipment)?.name ?? custom.equipment.capitalized)"
            )
            .foregroundStyle(Theme.textSecondary).forgeCaption()
          }
        }
      }
      .onDelete { indexes in
        for index in indexes {
          exercises[index].tombstoned = true
          exercises[index].updatedAt = .now
        }
        try? modelContext.save()
        CustomExerciseRegistry.reload(modelContext)
        Task { await SyncEngine.shared.sync() }
      }
    }
    .navigationTitle("Custom exercises")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        Button {
          showAdd = true
        } label: {
          Image(systemName: "plus")
        }
      }
    }
    .sheet(isPresented: $showAdd) { CustomExerciseForm() }
    .sheet(item: $editing) { custom in CustomExerciseForm(existing: custom) }
  }
}

struct CustomExerciseForm: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  let existing: CustomExercise?
  var onSaved: ((Exercise) -> Void)? = nil

  @State private var name = ""
  @State private var primary: Muscle = .chest
  @State private var synergists: Set<Muscle> = []
  @State private var equipment: Equipment = .machine
  @State private var isCompound = false

  init(existing: CustomExercise? = nil, onSaved: ((Exercise) -> Void)? = nil) {
    self.existing = existing
    self.onSaved = onSaved
    if let existing {
      _name = State(initialValue: existing.name)
      _primary = State(initialValue: Muscle(rawValue: existing.primary) ?? .chest)
      _synergists = State(initialValue: Set(existing.synergists.compactMap(Muscle.init(rawValue:))))
      _equipment = State(initialValue: Equipment(rawValue: existing.equipment) ?? .machine)
      _isCompound = State(initialValue: existing.isCompound)
    }
  }

  var body: some View {
    NavigationStack {
      Form {
        Section {
          TextField("Name", text: $name)
            .forgeBody()
            .onChange(of: name) { _, _ in name = String(name.prefix(40)) }
        } header: {
          Text("Name (required, 40 max)").forgeLabel()
        }
        Section {
          Picker("Primary muscle", selection: $primary) {
            ForEach(Muscle.allCases, id: \.self) { muscle in
              Text(muscle.a11yName).tag(muscle)
            }
          }
          .forgeBody()
        } header: {
          Text("Primary muscle").forgeLabel()
        }
        Section {
          LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], alignment: .leading, spacing: 8
          ) {
            ForEach(Muscle.allCases.filter { $0 != primary }, id: \.self) { muscle in
              let selected = synergists.contains(muscle)
              Button {
                if selected {
                  synergists.remove(muscle)
                } else if synergists.count < 2 {
                  synergists.insert(muscle)
                }
              } label: {
                Text(muscle.a11yName)
                  .forge(13, .medium)
                  .foregroundColor(selected ? Theme.onAccent : Theme.text)
                  .frame(maxWidth: .infinity)
                  .padding(.vertical, 8)
                  .background(Capsule().fill(selected ? Theme.accent : Theme.track))
              }
            }
          }
        } header: {
          Text("Synergists · up to two").forgeLabel()
        }
        Section {
          Picker("Equipment", selection: $equipment) {
            ForEach(Equipment.allCases, id: \.self) { item in
              Text(item.name).tag(item)
            }
          }
          .forgeBody()
        } header: {
          Text("Equipment").forgeLabel()
        }
        Section {
          Toggle("Compound", isOn: $isCompound).forgeBody()
        }
      }
      .navigationTitle(existing == nil ? "New exercise" : "Edit exercise")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Save", action: save)
            .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      }
    }
  }

  private func save() {
    let trimmed = String(name.trimmingCharacters(in: .whitespaces).prefix(40))
    let saved: CustomExercise
    if let existing {
      existing.name = trimmed
      existing.primary = primary.rawValue
      existing.synergists = synergists.map(\.rawValue).sorted()
      existing.equipment = equipment.rawValue
      existing.isCompound = isCompound
      existing.updatedAt = .now
      saved = existing
    } else {
      let custom = CustomExercise(
        name: trimmed, primary: primary, synergists: Array(synergists), isCompound: isCompound,
        equipment: equipment)
      modelContext.insert(custom)
      Analytics.track("custom_exercise_created")
      saved = custom
    }
    try? modelContext.save()
    CustomExerciseRegistry.reload(modelContext)
    Task { await SyncEngine.shared.sync() }
    onSaved?(saved.exercise)
    dismiss()
  }
}
