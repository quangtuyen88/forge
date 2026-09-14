import SwiftUI
import SwiftData
import ForgeCore

struct SettingsView: View {
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Environment(Store.self) private var store
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @State private var apiKeyInput = ""
  @State private var keyPresent = Keychain.get("anthropic-api-key") != nil
  @State private var confirmDelete = false

  var body: some View {
    NavigationStack {
      Form {
        if let p = profiles.first {
          @Bindable var profile = p
          Section("Units") {
            Picker("Weight units", selection: $profile.usesLb) {
              Text("kg").tag(false)
              Text("lb").tag(true)
            }
            .pickerStyle(.segmented)
          }
          Section("Rest timer") {
            Stepper(value: $profile.restCompoundSeconds, in: 60...300, step: 15) {
              HStack {
                Text("Compounds")
                Spacer()
                Text(mmss(profile.restCompoundSeconds)).monospacedDigit().foregroundStyle(.secondary)
              }
            }
            Stepper(value: $profile.restIsolationSeconds, in: 30...180, step: 15) {
              HStack {
                Text("Isolation")
                Spacer()
                Text(mmss(profile.restIsolationSeconds)).monospacedDigit().foregroundStyle(.secondary)
              }
            }
          }
          Section("Training") {
            Stepper("Days per week: \(profile.daysPerWeek)", value: $profile.daysPerWeek, in: 3...6)
            Picker("Session length", selection: sessionBinding(profile)) {
              ForEach(SessionLength.allCases, id: \.self) { Text("\($0.rawValue) min").tag($0) }
            }
            .pickerStyle(.segmented)
            ForEach(Equipment.allCases, id: \.self) { item in
              Toggle(item.rawValue.capitalized, isOn: equipmentBinding(profile, item))
            }
            ForEach(InjuryFlag.allCases, id: \.self) { flag in
              Toggle(flag.rawValue.capitalized, isOn: injuryBinding(profile, flag))
            }
            Toggle("I sleep under 6 h or life stress is high", isOn: $profile.recoveryReduced)
            Text("Changes apply from your next workout.")
              .font(.footnote)
              .foregroundStyle(.secondary)
          }
          Section("Coach") {
            if keyPresent {
              HStack {
                Text("Anthropic API key · Saved")
                Spacer()
                Button("Remove", role: .destructive) {
                  Keychain.delete("anthropic-api-key")
                  keyPresent = false
                }
              }
            } else {
              HStack {
                SecureField("Anthropic API key", text: $apiKeyInput)
                Button("Save") {
                  Keychain.set(apiKeyInput, for: "anthropic-api-key")
                  apiKeyInput = ""
                  keyPresent = true
                }
                .disabled(apiKeyInput.isEmpty)
              }
            }
          }
          Section("Data") {
            ShareLink(item: csvURL) {
              Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            Button("Delete all training data", role: .destructive) {
              confirmDelete = true
            }
          }
          Section("Subscription") {
            if let trial = profile.trialStartedAt {
              Text("Forge Pro · Trial started \(trial.formatted(date: .abbreviated, time: .omitted))")
            } else {
              Text("Not subscribed")
            }
            Button("Restore purchases") {
              Task { await store.restore() }
            }
          }
          Section("About") {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1")
          }
        }
      }
      .navigationTitle("Settings")
      .toolbar { Button("Done") { dismiss() }.bold() }
      .confirmationDialog("Delete all training data?", isPresented: $confirmDelete, titleVisibility: .visible) {
        Button("Delete all training data", role: .destructive) {
          try? modelContext.delete(model: WorkoutSession.self)
          try? modelContext.delete(model: CheckIn.self)
        }
      }
    }
  }

  private func mmss(_ seconds: Int) -> String {
    String(format: "%d:%02d", seconds / 60, seconds % 60)
  }

  private func sessionBinding(_ profile: UserProfile) -> Binding<SessionLength> {
    Binding(
      get: { SessionLength(rawValue: profile.sessionMinutes) ?? .m60 },
      set: { profile.sessionMinutes = $0.rawValue })
  }

  private func equipmentBinding(_ profile: UserProfile, _ item: Equipment) -> Binding<Bool> {
    Binding(
      get: { profile.equipment.contains(item.rawValue) },
      set: { on in
        var set = Set(profile.equipment)
        if on { set.insert(item.rawValue) } else { set.remove(item.rawValue) }
        profile.equipment = set.sorted()
      })
  }

  private func injuryBinding(_ profile: UserProfile, _ flag: InjuryFlag) -> Binding<Bool> {
    Binding(
      get: { profile.injuryFlags.contains(flag.rawValue) },
      set: { on in
        var set = Set(profile.injuryFlags)
        if on { set.insert(flag.rawValue) } else { set.remove(flag.rawValue) }
        profile.injuryFlags = set.sorted()
      })
  }

  private var csvURL: URL {
    let rows = sessions
      .sorted { $0.date < $1.date }
      .flatMap { session in
        session.sets
          .sorted { $0.setIndex < $1.setIndex }
          .map { "\(session.date.description),\($0.exerciseID),\($0.setIndex),\($0.weightKg),\($0.reps),\($0.rpe)" }
      }
    let csv = (["date,exercise,set,weight_kg,reps,rpe"] + rows).joined(separator: "\n")
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("forge-export.csv")
    try? csv.write(to: url, atomically: true, encoding: .utf8)
    return url
  }
}
