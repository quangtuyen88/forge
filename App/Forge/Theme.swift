import SwiftUI

enum Theme {
  static let accent = Color(red: 0.94, green: 0.40, blue: 0.13)
  static let radiusCard: CGFloat = 16
  static let radiusControl: CGFloat = 10
  static let unit: CGFloat = 8
}

extension View {
  /// Grouped card: 16pt padding, secondarySystemGroupedBackground, continuous 16pt corners.
  func card() -> some View {
    padding(16)
      .background(Color(.secondarySystemGroupedBackground))
      .clipShape(RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous))
  }
}

struct PillButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity, minHeight: 52)
      .background(Capsule().fill(Theme.accent))
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct PillSecondaryButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.headline)
      .foregroundStyle(.primary)
      .frame(maxWidth: .infinity, minHeight: 52)
      .background(Capsule().fill(Color(.tertiarySystemFill)))
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}

struct SelectCard: View {
  let title: String
  var subtitle: String? = nil
  let symbol: String
  let selected: Bool
  let action: () -> Void
  var badge: String? = nil

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: symbol)
          .font(.headline)
          .foregroundStyle(selected ? Theme.accent : Color.secondary)
          .frame(width: 40, height: 40)
          .background(Circle().fill(selected ? Theme.accent.opacity(0.1) : Color(.tertiarySystemFill)))
        VStack(alignment: .leading, spacing: 2) {
          HStack(spacing: 8) {
            Text(title)
              .font(.headline)
              .foregroundStyle(.primary)
            if let badge {
              Text(badge)
                .font(.caption2.bold())
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Capsule().fill(Theme.accent))
            }
          }
          if let subtitle {
            Text(subtitle)
              .font(.subheadline)
              .foregroundStyle(.secondary)
          }
        }
        Spacer()
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .foregroundStyle(selected ? Theme.accent : Color(.tertiaryLabel))
      }
      .padding(16)
      .background(selected ? Theme.accent.opacity(0.1) : Color(.secondarySystemGroupedBackground))
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .stroke(selected ? Theme.accent : .clear, lineWidth: 2))
      .contentShape(Rectangle())
    }
    .buttonStyle(CardPressStyle())
    .sensoryFeedback(.selection, trigger: selected)
  }
}

struct Illustration: View {
  let name: String
  var height: CGFloat = 160
  var body: some View {
    Image(name).resizable().scaledToFit()
      .frame(maxWidth: .infinity).frame(height: height)
      .accessibilityHidden(true)
  }
}

struct CoachAvatar: View {
  var size: CGFloat = 40
  var body: some View {
    Image("coach-avatar").resizable().scaledToFill()
      .frame(width: size, height: size).clipShape(Circle())
      .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
      .accessibilityHidden(true)
  }
}

/// Rounded speech bubble (radius 16 continuous, secondarySystemGroupedBackground) with a small tail on the leading edge.
struct SpeechBubble<Content: View>: View {
  @ViewBuilder var content: () -> Content
  var body: some View {
    content()
      .padding(12)
      .background(Theme.accent.opacity(0.12))
      .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
      .overlay(alignment: .leading) {
        Circle().fill(Theme.accent.opacity(0.12))
          .frame(width: 12, height: 12)
          .offset(x: -5, y: 6)
      }
  }
}

private struct CardPressStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .scaleEffect(configuration.isPressed ? 0.97 : 1)
      .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
  }
}
