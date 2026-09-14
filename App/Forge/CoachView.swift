import SwiftUI
import SwiftData
import ForgeCore

struct CoachView: View {
  struct Turn: Identifiable {
    let id = UUID()
    let role: String
    let text: String
    var citations: [String] = []
    let time = Date.now
  }

  @Query private var profiles: [UserProfile]
  @Query private var checkIns: [CheckIn]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @AppStorage("coachServerURL") private var coachServerURL = "https://forge-coach.quangtuyen88.workers.dev"
  @State private var turns: [Turn] = []
  @State private var input = ""
  @State private var thinking = false
  @State private var errorText: String?
  @State private var warmingUp = false
  @State private var revealedID: UUID?
  @FocusState private var inputFocused: Bool
  @AppStorage(Coach.storageKey) private var coachID = Coach.nova.rawValue
  @AppStorage("coachConsent") private var coachConsent = false
  @State private var showConsent = false
  @State private var pendingText: String?

  private var coach: Coach { Coach.from(coachID) }

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
      .background(Theme.page)
      .navigationTitle("Coach")
      .toolbar {
        ToolbarItem(placement: .topBarTrailing) { CoachAvatar(size: 32) }
        ToolbarItemGroup(placement: .keyboard) {
          Spacer()
          Button("Done") { inputFocused = false }
        }
      }
      .sheet(isPresented: $showConsent) { consentSheet }
    }
  }

  private var consentSheet: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.groupGap) {
        CoachAvatar(size: 56)
        Text("Before you ask \(coach.name)").forgeTitle()
        Text("Your question, your training log and your profile are sent to Forge's coach server, which uses Cloudflare Workers AI to write the answer. Nothing from Apple Health is sent. You can turn this off any time in Settings.")
          .forgeBody()
        Text("\(coach.name) is an AI coach for training programming, not medical advice.")
          .forgeLabel()
        Link("Privacy Policy", destination: Theme.privacyPolicyURL)
          .forgeLabel()
      }
      .padding(Theme.margin)
    }
    .safeAreaInset(edge: .bottom) {
      VStack(spacing: 8) {
        Button("Agree and continue") {
          coachConsent = true
          showConsent = false
          if let t = pendingText {
            pendingText = nil
            send(t)
          }
        }
        .buttonStyle(PillButtonStyle())
        Button("Not now") {
          showConsent = false
          pendingText = nil
        }
        .buttonStyle(PillSecondaryButtonStyle())
      }
      .padding(.horizontal, Theme.margin)
      .padding(.vertical, 10)
      .background(Theme.page.opacity(0.92))
      .background(.ultraThinMaterial)
    }
    .presentationDetents([.medium])
    .presentationBackground(Theme.page)
  }

  private var connected: Bool {
    AppSecret.value != nil
  }

  private var keyForm: some View {
    VStack(spacing: Theme.groupGap) {
      Spacer()
      CoachPhoto(name: coach.wave, height: 240)
      Text("Meet \(coach.name), your coach").forgeTitle()
      Text("The coach server isn't configured in this build.")
        .forgeLabel()
        .multilineTextAlignment(.center)
      Spacer()
      Spacer()
    }
    .padding(.horizontal, Theme.margin)
  }

  private var chat: some View {
    VStack(spacing: 8) {
      GeometryReader { geo in
        ScrollViewReader { proxy in
          ScrollView {
            if turns.isEmpty && !thinking {
              VStack(spacing: Theme.groupGap) {
                Spacer()
                CoachPhoto(name: coach.wave, height: 220)
                Text("Ask \(coach.name)").forgeTitle()
                Text("Swap an exercise, understand a deload, or ask why a lift stalled. AI coach, not medical advice.")
                  .forgeLabel()
                  .multilineTextAlignment(.center)
                VStack(spacing: 12) {
                  ForEach(prompts, id: \.title) { prompt in
                    Button {
                      send(prompt.title)
                    } label: {
                      HStack(spacing: 12) {
                        Image(systemName: prompt.symbol)
                          .font(.system(size: 15, weight: .semibold))
                          .foregroundColor(Theme.accent)
                          .frame(width: 36, height: 36)
                          .background(Circle().fill(Theme.accent.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 2) {
                          Text(prompt.title).forgeBodyStrong()
                          Text(prompt.hint).forgeCaption()
                        }
                        Spacer()
                      }
                      .frame(maxWidth: 480)
                      .card(padding: 14)
                      .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                  }
                }
                Spacer()
              }
              .padding(.horizontal, Theme.margin)
              .frame(maxWidth: .infinity)
              .frame(minHeight: geo.size.height)
            } else {
              LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(turns) { turn in
                  bubble(turn, maxWidth: geo.size.width * 0.8)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                if thinking {
                  HStack(alignment: .bottom, spacing: 8) {
                    CoachAvatar(size: 28)
                    Image(systemName: "ellipsis")
                      .font(.system(size: 18, weight: .bold))
                      .foregroundStyle(Theme.textSecondary)
                      .symbolEffect(.variableColor.iterative.dimInactiveLayers, options: .repeating)
                      .padding(12)
                      .background(Theme.card)
                      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                      .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1))
                  }
                  .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                Color.clear.frame(height: 0).id("bottom")
              }
              .padding(.horizontal, Theme.margin)
            }
          }
          .onChange(of: turns.count) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
          .onChange(of: thinking) { _ in proxy.scrollTo("bottom", anchor: .bottom) }
          .scrollDismissesKeyboard(.interactively)
          .onTapGesture { inputFocused = false }
        }
      }
      ScrollView(.horizontal, showsIndicators: false) {
        HStack {
          ForEach(suggestions, id: \.self) { chip in
            Button(chip) { send(chip) }
              .forge(13, .medium)
              .foregroundColor(Theme.text)
              .padding(.horizontal, 14)
              .padding(.vertical, 8)
              .background(
                RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
                  .fill(Theme.card))
              .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
                  .strokeBorder(Theme.ring, lineWidth: 1))
          }
        }
        .padding(.horizontal, Theme.margin)
      }
      if warmingUp {
        HStack(spacing: 10) {
          Image(systemName: "sparkles")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.accent)
          VStack(alignment: .leading, spacing: 2) {
            Text("\(coach.name) is warming up").forgeBodyStrong()
            Text("Coaching goes live once the backend is connected.").forgeCaption()
          }
          Spacer()
        }
        .innerSurface()
        .padding(.horizontal, Theme.margin)
        .transition(.move(edge: .bottom).combined(with: .opacity))
      }
      if let errorText {
        Text(errorText).foregroundStyle(Theme.negative).forgeCaption()
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.horizontal, Theme.margin)
      }
      HStack(alignment: .bottom, spacing: 8) {
        TextField("Ask your coach", text: $input, axis: .vertical)
          .lineLimit(1...5)
          .focused($inputFocused)
          .forgeBody()
          .padding(.horizontal, 12)
          .padding(.vertical, 10)
          .background(
            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
              .fill(Theme.card))
          .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusControl, style: .continuous)
              .strokeBorder(Theme.ring, lineWidth: 1))
        Button { send(input) } label: {
          Image(systemName: "arrow.up")
            .font(.system(size: 15, weight: .bold))
            .foregroundColor(.white)
            .frame(width: 36, height: 36)
            .background(Circle().fill(canSend ? Theme.accent : Theme.track))
        }
        .disabled(!canSend)
        .scaleEffect(canSend ? 1 : 0.9)
        .animation(.snappy, value: canSend)
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 8)
    }
  }

  private var canSend: Bool {
    !thinking && !input.trimmingCharacters(in: .whitespaces).isEmpty
  }

  private func bubble(_ turn: Turn, maxWidth: CGFloat) -> some View {
    let isUser = turn.role == "user"
    let bubble = Group {
      if isUser {
        Text(turn.text).foregroundStyle(.white)
      } else {
        Text(turn.text)
      }
    }
    .forgeBody()
    .textSelection(.enabled)
    .padding(12)
    .background(isUser ? Theme.accent : Theme.card)
    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .strokeBorder(Theme.ring, lineWidth: isUser ? 0 : 1))
    .fixedSize(horizontal: false, vertical: true)
    return Group {
      if isUser {
        VStack(alignment: .trailing, spacing: 4) {
          bubble
          if revealedID == turn.id {
            Text(turn.time, style: .time).forgeCaption()
          }
        }
        .frame(maxWidth: maxWidth, alignment: .trailing)
      } else {
        HStack(alignment: .bottom, spacing: 8) {
          CoachAvatar(size: 28)
          VStack(alignment: .leading, spacing: 4) {
            bubble
            if !turn.citations.isEmpty {
              Text(turn.citations.joined(separator: " · "))
                .forgeCaption()
            }
            if revealedID == turn.id {
              Text(turn.time, style: .time).forgeCaption()
            }
          }
        }
        .frame(maxWidth: maxWidth, alignment: .leading)
      }
    }
    .onLongPressGesture(minimumDuration: 0.3) {
      withAnimation(.snappy) { revealedID = revealedID == turn.id ? nil : turn.id }
    }
  }

  private func send(_ text: String) {
    let prompt = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !prompt.isEmpty, !thinking, connected else { return }
    if !coachConsent {
      pendingText = prompt
      showConsent = true
      return
    }
    input = ""
    errorText = nil
    warmingUp = false
    withAnimation(.snappy) {
      turns.append(Turn(role: "user", text: prompt))
      thinking = true
    }
    Task { await request() }
  }

  private func request() async {
    if turns.count > 20 { turns.removeFirst(turns.count - 20) }
    while turns.first?.role != "user" { turns.removeFirst() }
    await requestServer()
    if (errorText != nil || warmingUp), let last = turns.last, last.role == "user" {
      turns.removeLast()
      input = last.text
    }
    withAnimation(.snappy) { thinking = false }
  }

  private func requestServer() async {
    let base = coachServerURL == Theme.legacyCoachServer || coachServerURL.isEmpty ? Theme.coachServer : coachServerURL
    guard let url = URL(string: base)?.appending(path: "coach"),
          let secret = AppSecret.value else {
      errorText = "Check server settings"
      return
    }
    let body: [String: Any] = [
      "question": turns.last?.text ?? "",
      "context": dataBlock,
      "coach": coach.name,
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
        withAnimation(.snappy) { turns.append(Turn(role: "assistant", text: reply.answer, citations: reply.citations ?? [])) }
      } else if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let message = obj["error"] as? String {
        if message.contains("no model key") {
          warmingUp = true
        } else {
          errorText = message
        }
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

  private var dataBlock: String {
    var head: [String] = []
    if let p = profiles.first {
      head.append("Profile: goal \(p.goal), \(p.daysPerWeek) days/week, week \(p.currentWeek) of 6, injuries: \(p.injuryFlags.isEmpty ? "none" : p.injuryFlags.joined(separator: ", ")).")
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

private struct CoachReply: Decodable {
  let answer: String
  let refused: Bool?
  let citations: [String]?
}
