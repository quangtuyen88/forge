import SwiftUI

/// Symbol on a 14 % tint of its color: 8 pt rounded square on rows, circle when `circle`.
struct IconBadge: View {
  let symbol: String
  var tint: Color = Theme.accent
  var size: CGFloat = 32
  var circle = false

  var body: some View {
    Image(systemName: symbol)
      .font(.system(size: size * 0.5, weight: .semibold))
      .foregroundStyle(tint)
      .frame(width: size, height: size)
      .background {
        if circle {
          Circle().fill(tint.opacity(0.14))
        } else {
          RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
            .fill(tint.opacity(0.14))
        }
      }
      .accessibilityHidden(true)
  }
}

/// Explore-style row: badge, title, optional subtitle, chevron. At least 62 pt tall, 14 pt side padding.
struct ProgressListRow: View {
  let symbol: String
  var tint: Color = Theme.accent
  let title: String
  var subtitle: String? = nil
  var showsChevron = true

  var body: some View {
    HStack(spacing: 12) {
      IconBadge(symbol: symbol, tint: tint)
      VStack(alignment: .leading, spacing: 3) {
        Text(title).forgeBodyStrong().fixedSize(horizontal: false, vertical: true)
        if let subtitle {
          Text(subtitle).forgeCaption().fixedSize(horizontal: false, vertical: true)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      if showsChevron {
        Image(systemName: "chevron.right")
          .font(.system(size: 13, weight: .semibold))
          .foregroundStyle(Theme.textTertiary)
          .accessibilityHidden(true)
      }
    }
    .frame(maxWidth: .infinity, minHeight: 62, alignment: .leading)
    .padding(.horizontal, 14)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
  }
}

/// Capsule status chip, e.g. "Scheduled" in `Theme.metricTime`, "Applied" in `Theme.positive`:
/// text in tint on `tint.opacity(0.12)`, 12 pt semibold, height 22–24.
struct StateChip: View {
  let text: String
  var tint: Color = Theme.metricTime

  var body: some View {
    Text(text)
      .forge(12, .semibold)
      .foregroundStyle(tint)
      .padding(.horizontal, 10)
      .padding(.vertical, 4)
      .background(Capsule().fill(tint.opacity(0.12)))
  }
}

/// Small lock + "Private" tag that never wraps: `lock.fill` 11 pt and "Private" 12 pt medium, `Theme.textSecondary`.
struct PrivateTag: View {
  var body: some View {
    HStack(spacing: 4) {
      Image(systemName: "lock.fill")
        .font(.system(size: 11, weight: .medium))
        .accessibilityHidden(true)
      Text("Private")
        .forge(12, .medium)
    }
    .foregroundStyle(Theme.textSecondary)
    .fixedSize()
  }
}

/// Capsule info pill with a symbol, e.g. timer + "56 min": 12 pt medium secondary on `Theme.innerSurface`, height 26.
struct InfoPill: View {
  let symbol: String
  let text: String

  var body: some View {
    HStack(spacing: 5) {
      Image(systemName: symbol)
        .font(.system(size: 12, weight: .semibold))
        .accessibilityHidden(true)
      Text(text)
        .forge(12, .medium)
    }
    .foregroundStyle(Theme.textSecondary)
    .padding(.horizontal, 10)
    .frame(height: 26)
    .background(Capsule().fill(Theme.innerSurface))
  }
}
