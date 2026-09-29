import PDFKit
import SwiftUI

/// "Training report" share sheet (Overview v3): a one-page PDF preview with share actions.
/// The PDF and CSV are written to temp files by the caller before presentation.
struct TrainingReportSheet: View {
  let reportURL: URL
  let csvURL: URL

  @Environment(\.dismiss) private var dismiss
  @Environment(\.colorScheme) private var colorScheme

  var body: some View {
    ScrollView {
      VStack(spacing: 0) {
        header
        preview
          .padding(.top, 8)
        Text(
          String(
            localized: "One page: sessions, best lifts and weekly sets.", bundle: L10n.bundle)
        )
        .forge(14, .regular)
        .foregroundStyle(Theme.textSecondary)
        .multilineTextAlignment(.center)
        .padding(.horizontal, 24)
        .padding(.top, 12)
        ShareLink(item: reportURL, preview: SharePreview(String(localized: "Training report", bundle: L10n.bundle))) {
          Label(
            String(localized: "Share PDF", bundle: L10n.bundle),
            systemImage: "square.and.arrow.up")
        }
        .buttonStyle(PillButtonStyle())
        .padding(.top, 16)
        ShareLink(item: csvURL) {
          Label(String(localized: "Export CSV", bundle: L10n.bundle), systemImage: "tablecells")
        }
        .buttonStyle(PillSecondaryButtonStyle())
        .accessibilityLabel(String(localized: "Export CSV", bundle: L10n.bundle))
        .padding(.top, 10)
      }
      .padding(.horizontal, 16)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .presentationDetents([.medium, .large])
  }

  private var header: some View {
    ZStack {
      Text(String(localized: "Training report", bundle: L10n.bundle))
        .forge(17, .semibold)
        .foregroundStyle(Theme.text)
      HStack {
        Spacer()
        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(Theme.text)
            .frame(width: 32, height: 32)
            .todayGlass(Circle())
        }
        .accessibilityLabel(String(localized: "Close", bundle: L10n.bundle))
      }
    }
    .frame(height: 44)
    .padding(.top, 12)
  }

  /// First PDF page rendered as an image on a band surface, outlined 1 pt (mock .pv/.pw).
  private var preview: some View {
    Group {
      if let page = PDFDocument(url: reportURL)?.page(at: 0) {
        Image(uiImage: page.thumbnail(of: CGSize(width: 420, height: 594), for: .mediaBox))
          .resizable()
          .scaledToFit()
          .frame(maxHeight: 294)
      } else {
        Rectangle()
          .fill(Theme.card)
          .aspectRatio(595 / 842, contentMode: .fit)
          .frame(maxHeight: 294)
      }
    }
    .frame(maxWidth: .infinity)
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
        .strokeBorder(Theme.ring, lineWidth: 1))
    .padding(10)
    .padding(.vertical, 6)
    .background(
      RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
        .fill(colorScheme == .dark ? Theme.card : Theme.pageGrey))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(String(localized: "One-page report preview", bundle: L10n.bundle))
  }
}
