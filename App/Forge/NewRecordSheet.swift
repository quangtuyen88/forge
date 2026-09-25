import SwiftUI
import SwiftData
import ForgeCore

/// Spec E — the "New record" celebration sheet: one page per PR, gold token with
/// ring, glow and trophy badge, and the approved appear animation (DESIGN.md §12).
struct NewRecordSheet: View {
  struct Item: Identifiable {
    let exercise: Exercise
    let weightKg: Double
    let reps: Int
    let e1rm: Double
    let previousE1RM: Double?
    var id: String { exercise.id }
  }

  let items: [Item]
  let usesLb: Bool
  var onDone: () -> Void

  @Query private var profiles: [UserProfile]
  @State private var index = 0
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  // Appear-animation state; play() resets it and refires per page.
  @State private var chipOn = false
  @State private var token = false
  @State private var nameOn = false
  @State private var valueOn = false
  @State private var chipsOn = false
  @State private var captionOn = false
  @State private var footerOn = false
  @State private var glow = false
  @State private var badgeOn = false
  @State private var ring: CGFloat = 0

  private var item: Item { items[index] }
  private var isLast: Bool { index == items.count - 1 }
  /// Per-exercise units, the same rule PRSheet and the summary use.
  private var isLb: Bool { profiles.first?.isLb(for: item.exercise.id) ?? usesLb }
  private var unit: String { isLb ? "lb" : "kg" }
  private var weightText: String { Fmt.num(isLb ? Plates.kgToLb(item.weightKg) : item.weightKg) }
  private var e1rmText: String { Fmt.num(isLb ? Plates.kgToLb(item.e1rm) : item.e1rm) }
  private var deltaText: String {
    guard let previous = item.previousE1RM else { return "" }
    return Fmt.num(isLb ? Plates.kgToLb(item.e1rm - previous) : item.e1rm - previous)
  }

  private var shareText: String {
    String(
      localized:
        "New record: \(item.exercise.localizedName) \(weightText) \(unit) × \(item.reps) (estimated max \(e1rmText) \(unit)) — Regulift",
      bundle: L10n.bundle)
  }

  var body: some View {
    VStack(spacing: 0) {
      page(item)
        .id(index)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Theme.card)
    .presentationDetents([.fraction(0.82)])
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.card)
    // Rise only: the reset (true→false) must not re-fire the haptic.
    .sensoryFeedback(.success, trigger: badgeOn) { _, on in on }
    .onAppear { play() }
    .onChange(of: index) { _, _ in play() }
  }

  private func page(_ item: Item) -> some View {
    ScrollView(.vertical, showsIndicators: false) {
      VStack(spacing: 0) {
      SkyPill(String(localized: "New record", bundle: L10n.bundle), symbol: "trophy.fill", style: .gold)
        .modifier(Enter(on: chipOn, reduce: reduceMotion))
        .padding(.top, 20)

      ZStack {
        RecordGlow(size: 272)
          .opacity(glow ? 1 : 0)
          .scaleEffect(reduceMotion ? 1 : (glow ? 1 : 0.92))
        LiftToken(exercise: item.exercise, size: 176)
          .opacity(token ? 1 : 0)
          .scaleEffect(reduceMotion ? 1 : (token ? 1 : 0.9))
          .blur(radius: reduceMotion ? 0 : (token ? 0 : 4))
        Circle()
          .trim(from: 0, to: ring)
          .stroke(Theme.recordRing, style: StrokeStyle(lineWidth: 6, lineCap: .round))
          .rotationEffect(.degrees(-90))
          .frame(width: 170, height: 170)
        Circle()
          .fill(Theme.recordRing)
          .frame(width: 52, height: 52)
          .overlay(Circle().strokeBorder(Theme.card, lineWidth: 3))
          .overlay(
            Image(systemName: "trophy.fill")
              .font(.system(size: 24))
              .foregroundStyle(.white))
          .offset(x: 62, y: 62)
          .scaleEffect(reduceMotion ? 1 : (badgeOn ? 1 : 0.25))
          .opacity(badgeOn ? 1 : 0)
          .blur(radius: reduceMotion ? 0 : (badgeOn ? 0 : 4))
      }
      .frame(width: 272, height: 272)
      .padding(.top, 12)

      Text(item.exercise.localizedName)
        .forge(28, .bold)
        .foregroundStyle(Theme.text)
        .multilineTextAlignment(.center)
        .modifier(Enter(on: nameOn, reduce: reduceMotion))
        .padding(.top, 20)

      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(weightText).forge(48, .bold).foregroundStyle(Theme.text)
        Text(unit).forge(28, .semibold).foregroundStyle(Theme.textSecondary)
        Text("×").forge(28, .semibold).foregroundStyle(Theme.textSecondary)
        Text("\(item.reps)").forge(48, .bold).foregroundStyle(Theme.text)
      }
      .monospacedDigit()
      .modifier(Enter(on: valueOn, reduce: reduceMotion))
      .accessibilityElement(children: .ignore)
      .accessibilityLabel("\(weightText) \(unit) times \(item.reps)")
      .padding(.top, 6)

      HStack(spacing: 8) {
        Text("Estimated max \(e1rmText) \(unit)")
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(Capsule().fill(Theme.innerSurface))
        if item.previousE1RM != nil {
          SkyPill("\(deltaText) \(unit)", symbol: "arrow.up", style: .green)
        }
      }
      .modifier(Enter(on: chipsOn, reduce: reduceMotion))
      .padding(.top, 18)

      Text("Your best on this lift so far.")
        .forge(15, .regular)
        .foregroundStyle(Theme.textSecondary)
        .modifier(Enter(on: captionOn, reduce: reduceMotion))
        .padding(.top, 8)

      if items.count > 1 {
        HStack(spacing: 8) {
          ForEach(items.indices, id: \.self) { i in
            Circle()
              .fill(i == index ? Theme.accent : Theme.track)
              .frame(width: 8, height: 8)
          }
        }
        .modifier(Enter(on: footerOn, reduce: reduceMotion))
        .padding(.top, 16)
      }

      }
    }
    .scrollBounceBehavior(.basedOnSize)
    .safeAreaInset(edge: .bottom) {
      HStack(spacing: 12) {
        ShareLink(item: shareText) {
          Label("Share", systemImage: "square.and.arrow.up")
        }
        .buttonStyle(PillSecondaryButtonStyle())
        Button(
          isLast
            ? String(localized: "Close", bundle: L10n.bundle)
            : String(localized: "Next record", bundle: L10n.bundle)
        ) {
          if isLast {
            onDone()
          } else {
            withAnimation(.easeOut(duration: 0.25)) { index += 1 }
          }
        }
        .buttonStyle(PillButtonStyle())
        .accessibilityIdentifier("record.next")
      }
      .modifier(Enter(on: footerOn, reduce: reduceMotion))
      .padding(.horizontal, 20)
      .padding(.bottom, 16)
      .background(Theme.card)
    }
  }

  /// Reset with no animation, then fire on the next run-loop tick. Firing in the
  /// same tick would leave every flag at true→true — no render diff, no replay.
  private func play() {
    chipOn = false
    token = false
    nameOn = false
    valueOn = false
    chipsOn = false
    captionOn = false
    footerOn = false
    glow = false
    badgeOn = false
    ring = 0
    Task { @MainActor in
      await Task.yield()
      fire()
    }
  }

  private func fire() {
    if reduceMotion {
      // Final state at once; Enter() has already dropped offsets, blur and scale.
      withAnimation(.easeOut(duration: 0.2)) {
        chipOn = true
        token = true
        nameOn = true
        valueOn = true
        chipsOn = true
        captionOn = true
        footerOn = true
        glow = true
        badgeOn = true
        ring = 1
      }
      return
    }
    withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.4).delay(0.00)) { chipOn = true }
    withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.45).delay(0.10)) { token = true }
    withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.4).delay(0.20)) { nameOn = true }
    withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.4).delay(0.30)) { valueOn = true }
    withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.4).delay(0.40)) { chipsOn = true }
    withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.4).delay(0.50)) { captionOn = true }
    withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.4).delay(0.60)) { footerOn = true }
    withAnimation(.timingCurve(0.77, 0, 0.175, 1, duration: 0.6).delay(0.22)) { ring = 1 }
    withAnimation(.timingCurve(0.23, 1, 0.32, 1, duration: 0.6).delay(0.72)) { glow = true }
    withAnimation(.spring(duration: 0.3, bounce: 0).delay(0.80)) { badgeOn = true }
  }
}

extension NewRecordSheet.Item {
  /// nil when the producing call site has no record set (older PRRecord producers).
  init?(_ pr: PRRecord) {
    guard let weightKg = pr.weightKg, let reps = pr.reps else { return nil }
    self.init(
      exercise: pr.exercise, weightKg: weightKg, reps: reps,
      e1rm: pr.e1rm, previousE1RM: pr.previous)
  }

  init(_ record: ProgressData.Record) {
    self.init(
      exercise: record.exercise, weightKg: record.weightKg, reps: record.reps,
      e1rm: record.e1rm, previousE1RM: record.previousE1RM)
  }
}

/// The shared enter treatment for text groups: fade, 12 pt rise, blur-in.
/// Reduce Motion keeps the fade but drops the motion.
private struct Enter: ViewModifier {
  let on: Bool
  let reduce: Bool

  func body(content: Content) -> some View {
    content
      .opacity(on ? 1 : 0)
      .offset(y: reduce ? 0 : (on ? 0 : 12))
      .blur(radius: reduce ? 0 : (on ? 0 : 4))
  }
}

/// DEBUG demo hook for simulator checks and E2E: present the sheet once on appear
/// when any process argument contains "demo-record" (Maestro passes arguments in
/// a different shape). Release builds return the content unchanged.
struct NewRecordDemo: ViewModifier {
  let records: [ProgressData.Record]
  let usesLb: Bool
  @State private var shown = false
  /// Once per launch. The overview is rebuilt on every Overview/Timeline switch, so view state
  /// would forget and present the sheet again.
  @MainActor private static var presented = false

  func body(content: Content) -> some View {
    #if DEBUG
    content
      .sheet(isPresented: $shown) {
        NewRecordSheet(items: demoItems, usesLb: usesLb) { shown = false }
      }
      .onAppear {
        guard !Self.presented, !demoItems.isEmpty,
          ProcessInfo.processInfo.arguments.contains(where: { $0.contains("demo-record") })
        else { return }
        Self.presented = true
        shown = true
      }
    #else
    content
    #endif
  }

  /// The newest record per exercise, at most 2 items.
  private var demoItems: [NewRecordSheet.Item] {
    Dictionary(grouping: records, by: { $0.exercise.id })
      .values
      .compactMap { $0.max(by: { $0.date < $1.date }) }
      .sorted { $0.date > $1.date }
      .prefix(2)
      .map(NewRecordSheet.Item.init)
  }
}
