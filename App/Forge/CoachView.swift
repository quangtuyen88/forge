import SwiftUI
import SwiftData
import ForgeCore

struct CoachView: View {
  struct Turn: Identifiable {
    let id = UUID()
    let role: String
    let text: String
    var citations: [String] = []
  }

  @Query private var profiles: [UserProfile]
  @Query private var checkIns: [CheckIn]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @AppStorage("coachMode") private var coachMode = "server"
  @AppStorage("coachServerURL") private var coachServerURL = "https://forge-coach.quangtuyen88.workers.dev"
  @State private var apiKey = Keychain.get("anthropic-api-key") ?? ""
  @State private var keyInput = ""
  @State private var turns: [Turn] = []
  @State private var input = ""
  @State private var thinking = false
  @State private var errorText: String?

  private let suggestions = ["Why did my weight drop?", "Swap an exercise", "Explain my deload"]

  private let prompts: [(symbol: String, title: String, hint: String)] = [
    ("arrow.down.right.circle", "Why did my weight drop?", "Compare this week to last"),
    ("arrow.triangle.2.circlepath", "Swap an exercise", "Find a variant for today"),
    ("moon.zzz", "Explain my deload", "What a deload does for you"),
  ]

  var body: some View {
    NavigationStack {
      Group {
        if connected { chat } else { keyForm }
      }
      .background(Color(.systemGroupedBackground))
      .navigationTitle("Coach")
    }
  }

  private var connected: Bool {
    coachMode == "server"
      ? !(Keychain.get("forge-app-secret") ?? "").isEmpty
      : !apiKey.isEmpty
  }

  private var keyForm: some View {
    VStack(spacing: 16) {
      Spacer()
      Illustration(name: "coach-wave", height: 240)
      Text("Meet Nova, your coach").font(.headline)
      if coachMode == "server" {
        Text("Enter the app secret from Settings to start.")
          .font(.subheadline).foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
      } else {
        Text("Paste an Anthropic API key. Stored in your keychain.")
          .font(.subheadline).foregroundStyle(.secondary)
          .multilineTextAlignment(.center)
        SecureField("Anthropic API key", text: $keyInput)
          .textFieldStyle(.roundedBorder)
          .padding(.horizontal, 16)
          .onSubmit { saveKey() }
        Button("Save") { saveKey() }
          .buttonStyle(PillButtonStyle())
          .disabled(keyInput.isEmpty)
      }
      Spacer()
      Spacer()
    }
    .padding(16)
  }

  private func saveKey() {
    guard !keyInput.isEmpty else { return }
    Keychain.set(keyInput, for: "anthropic-api-key")
    apiKey = keyInput
  }

  private var chat: some View {
    VStack(spacing: 8) {
      GeometryReader { geo in
        ScrollViewReader { proxy in
          ScrollView {
            if turns.isEmpty && !thinking {
              VStack(spacing: 16) {
                Spacer()
                Illustration(name: "coach-wave", height: 200)
                VStack(spacing: 8) {
                  ForEach(prompts, id: \.title) { prompt in
                    Button {
                      send(prompt.title)
                    } label: {
                      HStack(spacing: 12) {
                        Image(systemName: prompt.symbol)
                          .font(.headline)
                          .foregroundStyle(Theme.accent)
                        VStack(alignment: .leading, spacing: 2) {
                          Text(prompt.title).font(.headline).foregroundStyle(.primary)
                          Text(prompt.hint).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                      }
                      .frame(maxWidth: 480)
                      .card()
                      .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                  }
                }
                Spacer()
              }
              .frame(maxWidth: .infinity)
              .frame(minHeight: geo.size.height)
            } else {
              LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(turns) { turn in
                  bubble(turn, maxWidth: geo.size.width * 0.8)
                }
                if thinking {
                  HStack(alignment: .bottom, spacing: 8) {
                    CoachAvatar(size: 28)
                    ProgressView()
                      .padding(12)
                      .background(Color(.secondarySystemGroupedBackground))
                      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                  }
                }
                Color.clear.frame(height: 0).id("bottom")
              }
              .padding(16)
            }
          }
          .onChange(of: turns.count) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
          .onChange(of: thinking) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
        }
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack {
          ForEach(suggestions, id: \.self) { chip in
            Button(chip) { send(chip) }.buttonStyle(.bordered).buttonBorderShape(.capsule)
          }
        }
        .padding(.horizontal, 16)
      }
      if let errorText {
        Text(errorText).font(.footnote).foregroundStyle(.red)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, 16)
      }
      HStack(alignment: .bottom, spacing: 8) {
        TextField("Ask your coach", text: $input, axis: .vertical)
          .lineLimit(1...5)
          .textFieldStyle(.roundedBorder)
        Button { send(input) } label: {
          Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 32))
            .foregroundStyle(canSend ? Theme.accent : Color(.tertiaryLabel))
        }
        .disabled(!canSend)
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 8)
    }
  }

  private var canSend: Bool {
    !thinking && !input.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func bubble(_ turn: Turn, maxWidth: CGFloat) -> some View {
    let isUser = turn.role == "user"
    let bubble = Text(turn.text)
      .textSelection(.enabled)
      .padding(12)
      .background(
        isUser
          ? Theme.accent.opacity(0.15)
          : Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .fixedSize(horizontal: false, vertical: true)
    return Group {
      if isUser {
        bubble.frame(maxWidth: maxWidth, alignment: .trailing)
      } else {
        HStack(alignment: .bottom, spacing: 8) {
          CoachAvatar(size: 28)
          VStack(alignment: .leading, spacing: 4) {
            bubble
            if !turn.citations.isEmpty {
              Text(turn.citations.joined(separator: " · "))
                .font(.caption2)
                .foregroundStyle(.tertiary)
            }
          }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
      }
    }
  }

  private func send(_ text: String) {
    let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty, !thinking, connected else { return }
    input = ""
    errorText = nil
    turns.append(Turn(role: "user", text: prompt))
    thinking = true
    Task { await request() }
  }

  private func request() async {
    if turns.count > 20 { turns.removeFirst(turns.count - 20) }
    while turns.first?.role != "user" { turns.removeFirst() }
    if coachMode == "server" {
      await requestServer()
    } else {
      await requestAnthropic()
    }
    if errorText != nil, let last = turns.last, last.role == "user" {
      turns.removeLast()
      input = last.text
    }
    thinking = false
  }

  private func requestAnthropic() async {
    let body: [String: Any] = [
      "model": "claude-sonnet-5",
      "max_tokens": 600,
      "system": systemPrompt,
      "messages": turns.map { ["role": $0.role, "content": $0.text] }]
    var req = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
    req.httpMethod = "POST"
    req.setValue(apiKey, forHTTPHeaderField: "x-api-key")
    req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    do {
      let (data, _) = try await URLSession.shared.data(for: req)
      if let text = (try? JSONDecoder().decode(Reply.self, from: data))?.content.compactMap(\.text).first {
        turns.append(Turn(role: "assistant", text: text))
      } else {
        errorText = errorHint(data)
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func requestServer() async {
    let base = coachServerURL == Theme.legacyCoachServer || coachServerURL.isEmpty ? Theme.coachServer : coachServerURL
    guard let url = URL(string: base)?.appending(path: "coach"),
          let secret = Keychain.get("forge-app-secret") else {
      errorText = "Check server settings"
      return
    }
    let body: [String: Any] = [
      "question": turns.last?.text ?? "",
      "context": dataBlock,
      "history": turns.dropLast().map { ["role": $0.role, "content": $0.text] }]
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "content-type")
    req.setValue(secret, forHTTPHeaderField: "x-forge-secret")
    req.httpBody = try? JSONSerialization.data(withJSONObject: body)
    do {
      let (data, response) = try await URLSession.shared.data(for: req)
      let status = (response as? HTTPURLResponse)?.statusCode ?? 0
      if status == 401 {
        errorText = "Wrong app secret"
      } else if let reply = try? JSONDecoder().decode(CoachReply.self, from: data) {
        turns.append(Turn(role: "assistant", text: reply.answer, citations: reply.citations ?? []))
      } else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let message = obj["error"] as? String {
        errorText = message
      } else {
        errorText = "\(status)"
      }
    } catch {
      errorText = error.localizedDescription
    }
  }

  private func errorHint(_ data: Data) -> String {
    if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
       let err = obj["error"] as? [String: Any], let message = err["message"] as? String {
      return message
    }
    return "No reply"
  }

  private var systemPrompt: String { persona + "\n" + dataBlock }

  private let persona = "You are Forge, a strength coach. Answer only about the user's training: programming, load/volume, exercise swaps, deloads, fatigue. Refuse medical, injury-rehab, nutrition-for-conditions and supplement-dosing questions with one sentence pointing to a professional. Be concise."

  private var dataBlock: String {
    var head: [String] = []
    if let p = profiles.first {
      head.append("Profile: goal \(p.goal), \(p.daysPerWeek) days/week, week \(p.currentWeek) of 6, injuries: \(p.injuryFlags.isEmpty ? "none" : p.injuryFlags.joined(separator: ", ")).")
    }
    if let f = fatigueNow(profile: profiles.first, sessions: sessions, checkIns: checkIns) {
      head.append("Today's fatigue score: \(f.score)/100.")
    }
    let plateauedNames = plateauedExerciseIDs(sessions: sessions)
      .sorted()
      .compactMap { ExerciseDB.find($0)?.name }
    if !plateauedNames.isEmpty {
      head.append("Plateaued lifts: \(plateauedNames.joined(separator: ", ")).")
    }
    var history = sessionLines()
    let tail = bestLines()
    func joined() -> String { (head + history + tail).joined(separator: "\n") }
    var out = joined()
    while out.count > 3000, !history.isEmpty {
      history.removeFirst()
      out = joined()
    }
    return out
  }

  private func sessionLines() -> [String] {
    let cutoff = Date.now.addingTimeInterval(-28 * 86400)
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd"
    let usesLb = profiles.first?.usesLb ?? false
    return sessions
      .filter { $0.completed && $0.date > cutoff }
      .sorted { $0.date < $1.date }
      .map { s in
        let parts = Dictionary(grouping: s.sets, by: \.exerciseID).compactMap { id, sets -> String? in
          guard let ex = ExerciseDB.find(id),
                let best = sets.max(by: { Strength.epley(weightKg: $0.weightKg, reps: $0.reps) < Strength.epley(weightKg: $1.weightKg, reps: $1.reps) }) else { return nil }
          let w = usesLb ? Plates.kgToLb(best.weightKg) : best.weightKg
          return String(format: "%@ %.1f×%d @%.1f (e1RM %.0f)", ex.name, w, best.reps, best.rpe, Strength.epley(weightKg: best.weightKg, reps: best.reps))
        }.sorted()
        return "\(df.string(from: s.date)) \(s.dayName): " + parts.joined(separator: "; ")
      }
  }

  private func bestLines() -> [String] {
    var bests: [String: Double] = [:]
    for s in sessions.filter(\.completed) {
      for set in s.sets {
        let e = Strength.epley(weightKg: set.weightKg, reps: set.reps)
        if e > bests[set.exerciseID] ?? 0 { bests[set.exerciseID] = e }
      }
    }
    return bests
      .sorted { $0.key < $1.key }
      .map { String(format: "Best %@: %.0f e1RM", ExerciseDB.find($0.key)?.name ?? $0.key, $0.value) }
  }
}

private struct Reply: Decodable {
  struct Block: Decodable { let text: String? }
  let content: [Block]
}

private struct CoachReply: Decodable {
  let answer: String
  let refused: Bool?
  let citations: [String]?
}
