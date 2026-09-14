import SwiftUI
import SwiftData
import ForgeCore

struct SettingsView: View {
  @Query private var profiles: [UserProfile]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Environment(Store.self) private var store
  @Environment(\.modelContext) private var modelContext
  @Environment(\.dismiss) private var dismiss
  @AppStorage("coachServerURL") private var coachServerURL = "https://forge-coach.quangtuyen88.workers.dev"
  @State private var secretInput = ""
  @State private var secretPresent = Keychain.get("forge-app-secret") != nil
  @State private var confirmDelete = false
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @AppStorage("coachConsent") private var coachConsent = false

  private var coach: Coach { Coach.from(coachID) }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: Theme.groupGap) {
          if let p = profiles.first {
            @Bindable var profile = p

            section("Units") {
              Picker("Weight units", selection: $profile.usesLb) {
                Text("kg").tag(false)
                Text("lb").tag(true)
              }
              .pickerStyle(.segmented)
            }

            section("Rest timer") {
              Stepper(value: $profile.restCompoundSeconds, in: 60...300, step: 15) {
                HStack {
                  Text("Compounds").forgeBody()
                  Spacer()
                  Text(mmss(profile.restCompoundSeconds)).forgeLabel().monospacedDigit()
                }
              }
              Divider().overlay(Theme.ring)
              Stepper(value: $profile.restIsolationSeconds, in: 30...180, step: 15) {
                HStack {
                  Text("Isolation").forgeBody()
                  Spacer()
                  Text(mmss(profile.restIsolationSeconds)).forgeLabel().monospacedDigit()
                }
              }
              if !profile.restOverrides.isEmpty {
                Divider().overlay(Theme.ring)
                Button("Reset per-exercise timers") {
                  profile.restOverrides = [:]
                }
                .foregroundStyle(Theme.negative)
                .forgeBodyStrong()
                .frame(minHeight: 44)
              }
            }

            section("Training") {
              Stepper(value: $profile.daysPerWeek, in: 3...6) {
                HStack {
                  Text("Days per week").forgeBody()
                  Spacer()
                  Text("\(profile.daysPerWeek)").forgeLabel().monospacedDigit()
                }
              }
              Divider().overlay(Theme.ring)
              Picker("Session length", selection: sessionBinding(profile)) {
                ForEach(SessionLength.allCases, id: \.self) { Text("\($0.rawValue) min").tag($0) }
              }
              .pickerStyle(.segmented)
              ForEach(Equipment.allCases, id: \.self) { item in
                Divider().overlay(Theme.ring)
                Toggle(item.rawValue.capitalized, isOn: equipmentBinding(profile, item))
                  .tint(Theme.accent)
                  .forgeBody().padding(.vertical, 6)
              }
              ForEach(InjuryFlag.allCases, id: \.self) { flag in
                Divider().overlay(Theme.ring)
                Toggle(flag.rawValue.capitalized, isOn: injuryBinding(profile, flag))
                  .tint(Theme.accent)
                  .forgeBody().padding(.vertical, 6)
              }
              Divider().overlay(Theme.ring)
              Toggle("I sleep under 6 h or life stress is high", isOn: $profile.recoveryReduced)
                .tint(Theme.accent)
                .forgeBody().padding(.vertical, 6)
            }

            section("Coach") {
              HStack(spacing: 12) {
                ForEach(Coach.allCases) { c in
                  Button {
                    withAnimation(.snappy) { coachID = c.rawValue }
                  } label: {
                    HStack(spacing: 8) {
                      Image(c.avatar).resizable().scaledToFill()
                        .frame(width: 32, height: 32)
                        .clipShape(Circle())
                      Text(c.name).forgeBodyStrong()
                      Spacer()
                    }
                    .padding(10)
                    .background(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).fill(coach == c ? Theme.accent.opacity(0.12) : Theme.innerSurface))
                    .overlay(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous).strokeBorder(coach == c ? Theme.accent : .clear, lineWidth: 1.5))
                  }
                  .buttonStyle(.plain)
                }
              }
              Divider().overlay(Theme.ring)
              Toggle("Share training data with the coach", isOn: $coachConsent)
                .tint(Theme.accent)
                .forgeBody().padding(.vertical, 6)
              Divider().overlay(Theme.ring)
              Link("Privacy Policy", destination: Theme.privacyPolicyURL)
                .forgeBody()
                .frame(minHeight: 44)
              Divider().overlay(Theme.ring)
              Link("Terms", destination: Theme.termsURL)
                .forgeBody()
                .frame(minHeight: 44)
              if AppSecret.bundled != nil {
                Divider().overlay(Theme.ring)
                HStack {
                  Text("Coach server").forgeBody()
                  Spacer()
                  Text("Connected").forgeLabel()
                }
                .frame(minHeight: 44)
              } else {
                Divider().overlay(Theme.ring)
                TextField("Server URL", text: $coachServerURL)
                  .keyboardType(.URL)
                  .textInputAutocapitalization(.never)
                  .autocorrectionDisabled()
                  .forgeBody()
                  .padding(10)
                  .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
                if secretPresent {
                  Divider().overlay(Theme.ring)
                  HStack {
                    Text("App secret · Saved").forgeBody()
                    Spacer()
                    Button("Remove") {
                      Keychain.delete("forge-app-secret")
                      secretPresent = false
                    }
                    .foregroundStyle(Theme.negative)
                    .forgeBodyStrong()
                  }
                  .frame(minHeight: 44)
                } else {
                  Divider().overlay(Theme.ring)
                  HStack {
                    SecureField("App secret", text: $secretInput)
                      .forgeBody()
                      .padding(10)
                      .background(RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous).fill(Theme.innerSurface))
                    Button("Save") {
                      Keychain.set(secretInput, for: "forge-app-secret")
                      secretInput = ""
                      secretPresent = true
                    }
                    .disabled(secretInput.isEmpty)
                    .foregroundStyle(Theme.accent)
                    .forgeBodyStrong()
                  }
                }
              }
            }

            section("Data") {
              ShareLink(item: csvURL) {
                Label("Export CSV", systemImage: "square.and.arrow.up").forgeBody()
              }
              .frame(minHeight: 44)
              Divider().overlay(Theme.ring)
              Button("Delete all training data") {
                confirmDelete = true
              }
              .foregroundStyle(Theme.negative)
              .forgeBody()
              .frame(minHeight: 44)
            }

            section("Subscription") {
              HStack {
                Text("Forge Pro").forgeBody()
                Spacer()
                if let trial = profile.trialStartedAt {
                  Text("Trial started \(trial.formatted(date: .abbreviated, time: .omitted))").forgeLabel()
                } else {
                  Text("Not subscribed").forgeLabel()
                }
              }
              .frame(minHeight: 44)
              Divider().overlay(Theme.ring)
              Button("Restore purchases") {
                Task { await store.restore() }
              }
              .foregroundStyle(Theme.accent)
              .forgeBodyStrong()
              .frame(minHeight: 44)
            }

            section("About") {
              HStack {
                Text("Version").forgeBody()
                Spacer()
                Text(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1").forgeLabel()
              }
              .frame(minHeight: 44)
            }
          }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 8)
        .padding(.bottom, 24)
      }
      .background(Theme.page)
      .navigationTitle("Settings")
      .toolbar { Button("Done") { dismiss() }.bold() }
      .onAppear { if coachServerURL == Theme.legacyCoachServer { coachServerURL = Theme.coachServer } }
      .confirmationDialog("Delete all training data?", isPresented: $confirmDelete, titleVisibility: .visible) {
        Button("Delete all training data", role: .destructive) {
          try? modelContext.delete(model: WorkoutSession.self)
          try? modelContext.delete(model: CheckIn.self)
        }
      }
    }
  }

  private func section<Rows: View>(_ title: String, @ViewBuilder rows: () -> Rows) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(title).forgeSection().padding(.bottom, 10)
      rows()
    }
    .card()
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
