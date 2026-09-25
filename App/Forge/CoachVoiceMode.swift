import SwiftUI

/// What Coach voice mode is doing; CoachView derives it from SpeechInput and the chat.
enum CoachVoicePhase: Equatable {
  case preparing, listening, transcribing, thinking, answered
  case failed(message: String, permission: Bool)
}

/// Top of the voice screen: the coach's portrait and name.
struct VoiceHeader: View {
  let name: String

  var body: some View {
    HStack(spacing: 10) {
      CoachAvatar(size: 32)
      Text(name)
        .font(.forge(17, .semibold))
        .foregroundStyle(Theme.text)
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
    .accessibilityElement(children: .combine)
    .accessibilityAddTraits(.isHeader)
  }
}

/// Left-aligned wrapping layout for transcript words.
struct WordFlow: Layout {
  var spacing: CGFloat = 9
  var lineSpacing: CGFloat = 2

  /// One wrapped line: member indices, total width, tallest member.
  private struct Line {
    var indices: [Int] = []
    var width: CGFloat = 0
    var height: CGFloat = 0
  }

  private func lines(_ subviews: Subviews, maxWidth: CGFloat?) -> [Line] {
    var lines: [Line] = []
    for index in subviews.indices {
      let size = subviews[index].sizeThatFits(
        maxWidth.map { ProposedViewSize(width: $0, height: nil) } ?? .unspecified)
      let fits: Bool
      if let maxWidth, let last = lines.last {
        fits = last.width + spacing + size.width <= maxWidth
      } else {
        fits = true
      }
      if fits, !lines.isEmpty {
        lines[lines.count - 1].indices.append(index)
        lines[lines.count - 1].width += spacing + size.width
        lines[lines.count - 1].height = max(lines[lines.count - 1].height, size.height)
      } else {
        lines.append(Line(indices: [index], width: size.width, height: size.height))
      }
    }
    return lines
  }

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let laid = lines(subviews, maxWidth: proposal.width)
    let height = laid.map(\.height).reduce(0, +) + lineSpacing * CGFloat(max(0, laid.count - 1))
    return CGSize(width: laid.map(\.width).max() ?? 0, height: height)
  }

  func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
    let maxWidth = proposal.width ?? bounds.width
    let subviewProposal = ProposedViewSize(width: maxWidth, height: nil)
    let laid = lines(subviews, maxWidth: maxWidth)
    var y = bounds.minY
    for (position, line) in laid.enumerated() {
      var x = bounds.minX
      for index in line.indices {
        let size = subviews[index].sizeThatFits(subviewProposal)
        subviews[index].place(
          at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
          anchor: .topLeading,
          proposal: subviewProposal)
        x += size.width + spacing
      }
      if position < laid.count - 1 {
        y += line.height + lineSpacing
      }
    }
  }
}

/// The live transcript: words land one by one, the pending tail stays secondary.
struct VoiceTranscript: View {
  let text: String
  let pending: String
  let placeholder: String
  let showsCursor: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var words: [Substring] { text.split(whereSeparator: \.isWhitespace) }

  private var confirmedCount: Int {
    max(0, words.count - pending.split(whereSeparator: \.isWhitespace).count)
  }

  var body: some View {
    Group {
      if words.isEmpty {
        WordFlow {
          ForEach(Array(placeholder.split(whereSeparator: \.isWhitespace).enumerated()), id: \.offset) { _, word in
            Text(word)
              .font(.forge(28, .semibold, relativeTo: .title))
              .tracking(-0.5)
              .foregroundStyle(Theme.textSecondary)
          }
          if showsCursor { VoiceCursor() }
        }
      } else {
        WordFlow {
          ForEach(Array(words.enumerated()), id: \.offset) { index, word in
            Text(String(word))
              .font(.forge(34, .semibold, relativeTo: .largeTitle))
              .tracking(-0.7)
              .foregroundStyle(index < confirmedCount ? Theme.text : Theme.textSecondary)
              .transition(landing)
          }
          if showsCursor { VoiceCursor() }
        }
        .animation(.easeOut(duration: 0.22), value: words.count)
        .animation(.easeOut(duration: 0.2), value: confirmedCount)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(words.isEmpty ? placeholder : text)
    .accessibilityAddTraits(.updatesFrequently)
    .accessibilityIdentifier("coach.voice.transcript")
  }

  private var landing: AnyTransition {
    reduceMotion
      ? .opacity
      : .asymmetric(
        insertion: .modifier(active: WordLanding(active: true), identity: WordLanding(active: false)),
        removal: .opacity)
  }
}

/// Insertion state of a landing word.
private struct WordLanding: ViewModifier {
  let active: Bool

  func body(content: Content) -> some View {
    content
      .opacity(active ? 0 : 1)
      .blur(radius: active ? 4 : 0)
      .offset(y: active ? 5 : 0)
  }
}

/// Blinking blue text cursor.
private struct VoiceCursor: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @ScaledMetric(relativeTo: .largeTitle) private var h: CGFloat = 36

  var body: some View {
    Group {
      if reduceMotion {
        bar.opacity(1)
      } else {
        TimelineView(.periodic(from: .now, by: 0.53)) { context in
          let tick = Int(context.date.timeIntervalSinceReferenceDate / 0.53)
          bar.opacity(tick % 2 == 0 ? 1 : 0)
        }
      }
    }
    .accessibilityHidden(true)
  }

  private var bar: some View {
    RoundedRectangle(cornerRadius: 1.25)
      .fill(Theme.accent)
      .frame(width: 2.5, height: h)
  }
}

/// Status line with an optional elapsed clock.
struct VoiceStatusLine: View {
  let title: String
  let since: Date?

  var body: some View {
    HStack(spacing: 0) {
      Text(title)
        .font(.forge(15, .semibold))
        .foregroundStyle(Theme.textSecondary)
      if let since {
        Text(" · ")
          .font(.forge(15, .semibold))
          .foregroundStyle(Theme.textSecondary)
        TimelineView(.periodic(from: since, by: 1)) { context in
          Text(Self.clock(context.date.timeIntervalSince(since)))
            .font(.forge(15, .semibold).monospacedDigit())
            .foregroundStyle(Theme.metricTime)
        }
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("coach.voice.status")
  }

  private static func clock(_ elapsed: TimeInterval) -> String {
    let s = max(0, Int(elapsed))
    return String(format: "%d:%02d", s / 60, s % 60)
  }
}

/// The big center control; its look follows the voice phase.
struct VoiceDisc: View {
  let phase: CoachVoicePhase
  let level: Double
  let label: String
  let action: () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// The four disc looks, without the failure message.
  private enum Look: Equatable {
    case bars, dots, mic, slashed
  }

  private static let barBases: [CGFloat] = [8, 18, 34, 47, 34, 18, 8]

  private var look: Look {
    switch phase {
    case .preparing, .listening: .bars
    case .transcribing, .thinking: .dots
    case .answered: .mic
    case .failed: .slashed
    }
  }

  private var isEnabled: Bool {
    switch phase {
    case .listening, .answered: true
    case .failed(_, let permission): !permission
    default: false
    }
  }

  private var discSize: CGFloat {
    look == .mic ? 74 : 112
  }

  private var discFill: Color {
    switch look {
    case .bars, .dots: Theme.accent
    case .mic, .slashed: Theme.innerSurface
    }
  }

  private var showsRing: Bool {
    look == .bars || look == .dots
  }

  private var ringScale: CGFloat {
    guard look == .bars, !reduceMotion else { return 1 }
    return 1 + 0.06 * CGFloat(level)
  }

  var body: some View {
    Button(action: action) {
      ZStack {
        Group {
          if showsRing {
            Circle()
              .strokeBorder(Theme.accent.opacity(0.28), lineWidth: 2.5)
              .frame(width: 138, height: 138)
              .scaleEffect(ringScale)
              .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: level)
          }
          Circle()
            .fill(discFill)
            .frame(width: discSize, height: discSize)
        }
        .animation(discAnimation, value: look)
        glyph
          .transition(glyphTransition)
          .id(look)
      }
      .animation(.timingCurve(0.2, 0, 0, 1, duration: 0.3), value: look)
      .frame(width: 138, height: 138)
      .contentShape(Circle())
    }
    .buttonStyle(ControlPressStyle())
    .disabled(!isEnabled)
    .accessibilityLabel(label)
    .accessibilityIdentifier("coach.voice.disc")
  }

  @ViewBuilder
  private var glyph: some View {
    switch look {
    case .bars: barsGlyph
    case .dots: dotsGlyph
    case .mic:
      Image(systemName: "mic")
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(Theme.text)
    case .slashed:
      Image(systemName: "mic.slash")
        .font(.system(size: 34, weight: .medium))
        .foregroundStyle(Theme.textSecondary)
    }
  }

  @ViewBuilder
  private var barsGlyph: some View {
    if reduceMotion {
      bars(Self.barBases.map { 6 + ($0 - 6) * 0.6 })
    } else if phase == .preparing {
      bars(Self.barBases.map { 6 + ($0 - 6) * 0.2 })
    } else {
      TimelineView(.animation(minimumInterval: 1.0 / 30, paused: phase != .listening)) { context in
        bars(barHeights(context.date.timeIntervalSinceReferenceDate))
      }
    }
  }

  @ViewBuilder
  private var dotsGlyph: some View {
    if reduceMotion {
      dots([1, 1, 1])
    } else {
      TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !(phase == .transcribing || phase == .thinking))) { context in
        dots(dotOpacities(context.date.timeIntervalSinceReferenceDate))
      }
    }
  }

  private var discAnimation: Animation {
    reduceMotion ? .easeOut(duration: 0.2) : .spring(response: 0.4, dampingFraction: 1)
  }

  private var glyphTransition: AnyTransition {
    reduceMotion
      ? .opacity
      : .modifier(active: GlyphSwap(active: true), identity: GlyphSwap(active: false))
  }

  private func barHeights(_ t: TimeInterval) -> [CGFloat] {
    Self.barBases.enumerated().map { index, base in
      let wave = 0.72 + 0.28 * sin(t * 19 + Double(index) * 1.7)
      let f = min(1, max(0, 0.2 + 0.8 * level * wave))
      return 6 + (base - 6) * CGFloat(f)
    }
  }

  private func dotOpacities(_ t: TimeInterval) -> [Double] {
    (0..<3).map { index in
      0.45 + 0.55 * (0.5 + 0.5 * sin(t * 9 - Double(index) * 1.1))
    }
  }

  private func bars(_ heights: [CGFloat]) -> some View {
    HStack(spacing: 5) {
      ForEach(heights.indices, id: \.self) { index in
        Capsule()
          .fill(Theme.onAccent)
          .frame(width: 6, height: heights[index])
      }
    }
  }

  private func dots(_ opacities: [Double]) -> some View {
    HStack(spacing: 7) {
      ForEach(opacities.indices, id: \.self) { index in
        Circle()
          .fill(Theme.onAccent)
          .frame(width: 7, height: 7)
          .opacity(opacities[index])
      }
    }
  }
}

/// Swap state of the disc glyph group.
private struct GlyphSwap: ViewModifier {
  let active: Bool

  func body(content: Content) -> some View {
    content
      .opacity(active ? 0 : 1)
      .scaleEffect(active ? 0.25 : 1)
      .blur(radius: active ? 4 : 0)
  }
}

/// Bottom control row: close left, keyboard right, center control between.
struct VoiceControlRow<Center: View>: View {
  let closeLabel: String
  let keyboardLabel: String
  let onClose: () -> Void
  let onKeyboard: () -> Void
  @ViewBuilder let center: () -> Center

  var body: some View {
    ZStack {
      center()
      HStack {
        circleButton(symbol: "xmark", label: closeLabel, action: onClose)
          .accessibilityIdentifier("coach.voice.close")
        Spacer()
        circleButton(symbol: "keyboard", label: keyboardLabel, action: onKeyboard)
          .accessibilityIdentifier("coach.voice.keyboard")
      }
      .padding(.horizontal, 28)
    }
    .frame(height: 138)
  }

  private func circleButton(symbol: String, label: String, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 20, weight: .medium))
        .foregroundStyle(Theme.text)
        .frame(width: 56, height: 56)
        .background(Circle().fill(Theme.innerSurface))
        .contentShape(Circle())
    }
    .buttonStyle(ControlPressStyle())
    .accessibilityLabel(label)
  }
}

/// Failure notice: red mic-slash capsule with message and optional action.
struct VoiceFailureNotice: View {
  let title: String
  let message: String?
  let actionTitle: String?
  let action: (() -> Void)?

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 8) {
        Image(systemName: "mic.slash.fill")
          .font(.system(size: 17, weight: .semibold))
          .foregroundStyle(Theme.negative)
        Text(title)
          .font(.forge(17, .semibold))
          .foregroundStyle(Theme.negative)
      }
      .padding(.horizontal, 16)
      .frame(minHeight: 44)
      .background(Capsule().fill(Theme.negative.opacity(0.14)))
      if let message {
        Text(message)
          .font(.forge(17, .regular))
          .foregroundStyle(Theme.textSecondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let actionTitle, let action {
        Button(actionTitle, action: action)
          .buttonStyle(PillButtonStyle())
          .frame(maxWidth: 220)
          .padding(.top, 12)
          .accessibilityIdentifier("coach.voice.failure.action")
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("coach.voice.failure")
  }
}
