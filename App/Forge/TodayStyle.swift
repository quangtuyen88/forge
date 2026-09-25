import SwiftUI

/// The Today sky page (DESIGN.md §12); fills the caller's frame.
struct TodayBackdrop: View {
  var body: some View {
    LinearGradient(
      stops: [
        .init(color: Theme.todaySkyTop, location: 0),
        .init(color: Theme.todaySkyTop, location: 0.28),
        .init(color: Theme.todaySkyMid, location: 0.46),
        .init(color: Theme.todaySkyLow, location: 0.68),
        .init(color: Theme.todayPage, location: 1),
      ],
      startPoint: .top,
      endPoint: .bottom)
    .allowsHitTesting(false)
  }
}

/// Legibility scrim over the next-up cover photo.
struct TodayPhotoScrim: View {
  var body: some View {
    LinearGradient(
      stops: [
        .init(color: .clear, location: 0.35),
        .init(color: Color.black.opacity(0.42), location: 1),
      ],
      startPoint: .top,
      endPoint: .bottom)
    .allowsHitTesting(false)
  }
}

extension View {
  /// Elevated Today card (DESIGN.md §12): shadow on the background shape only, never on text.
  func todayCard(padding: CGFloat = 16, fill: Color = Theme.card, tint: Color? = nil) -> some View {
    self
      .padding(padding)
      .background {
        ZStack {
          RoundedRectangle(cornerRadius: Theme.radiusToday, style: .continuous).fill(fill)
          if let tint {
            RoundedRectangle(cornerRadius: Theme.radiusToday, style: .continuous).fill(tint)
          }
        }
        .shadow(color: Theme.shadow, radius: 18, x: 0, y: 10)
      }
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusToday, style: .continuous)
          .strokeBorder(Theme.todayCardRing, lineWidth: 1))
  }

  /// Glass pill over the sky: ultra-thin material, translucent tint on top, hairline ring.
  func todayGlass<S: InsettableShape>(_ shape: S) -> some View {
    self
      .background {
        ZStack {
          shape.fill(.ultraThinMaterial)
          shape.fill(Theme.todayGlass)
        }
      }
      .overlay(shape.strokeBorder(Theme.todayCardRing, lineWidth: 1))
  }

  /// Tinted footer strip at the bottom of a Today card.
  func todayFooterStrip() -> some View {
    self
      .padding(.horizontal, 16)
      .frame(maxWidth: .infinity, minHeight: 50, alignment: .leading)
      .background(Theme.todayFooter)
  }
}

/// The Today sky as a fixed page background for screens with a pinned header (Progress,
/// DESIGN.md §12): the same gradient and placement Today shows at rest.
struct TodaySkyPage: View {
  var body: some View {
    Theme.todayPage
      .overlay(alignment: .top) {
        TodayBackdrop().frame(height: 1100).offset(y: -300)
      }
      .ignoresSafeArea()
  }
}

/// Soft gold celebration glow behind a record token (new-record sheet).
struct RecordGlow: View {
  private let size: CGFloat

  init(size: CGFloat) {
    self.size = size
  }

  var body: some View {
    ZStack {
      Circle().fill(RadialGradient(colors: [Theme.recordRing.opacity(0.30), Theme.recordRing.opacity(0)], center: .center, startRadius: 0, endRadius: size / 2))
      ForEach(0..<12, id: \.self) { i in
        Capsule().fill(Theme.recordRing.opacity(0.45))
          .frame(width: 4, height: size * 0.075)
          .offset(y: -size * 0.43)
          .rotationEffect(.degrees(Double(i) * 30 + 15))
      }
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }
}
