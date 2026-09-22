import SwiftUI
import ForgeCore

/// The Top Sets template, Clean look.
///
/// Layout is template-driven and bounded: mandatory qualifiers, load conventions and the
/// subset label are laid out before anything is allowed to shrink, because none of them
/// may be dropped to make a name fit.
struct ShareCardView: View {
  let document: CardDocument

  private var isStory: Bool { document.format == .story }

  var body: some View {
    VStack(alignment: .leading, spacing: isStory ? 22 : 18) {
      header
      VStack(alignment: .leading, spacing: isStory ? 18 : 14) {
        ForEach(document.highlights, id: \.exerciseID) { highlight in
          VStack(alignment: .leading, spacing: 4) {
            Text(highlight.exerciseName)
              .forge(isStory ? 15 : 13, .semibold)
              .foregroundStyle(.white.opacity(0.65))
              .lineLimit(2)
              .minimumScaleFactor(0.8)
            Text(line(highlight))
              .forge(isStory ? 30 : 25, .bold, tracking: -0.6)
              .monospacedDigit()
              .foregroundStyle(.white)
            if let qualifier = highlight.qualifier {
              Text(ShareCardComposer.qualifierText(qualifier))
                .forge(isStory ? 12 : 11, .medium)
                .foregroundStyle(Theme.shareAccent)
            }
          }
        }
      }
      if !document.aggregates.isEmpty {
        Text(document.aggregates.map(aggregate).joined(separator: " · "))
          .forge(isStory ? 15 : 13, .medium)
          .monospacedDigit()
          .foregroundStyle(.white.opacity(0.7))
      }
      if let target = document.nextTarget {
        nextTargetBlock(target)
      }
      Spacer(minLength: 0)
      footer
    }
    .frame(
      width: CGFloat(document.format.pixelSize.width) / 3,
      height: CGFloat(document.format.pixelSize.height) / 3,
      alignment: .topLeading)
    .padding(isStory ? 32 : 24)
    .background(Theme.shareSurface)
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      if !document.title.isEmpty {
        Text(document.title)
          .forge(isStory ? 30 : 24, .bold, tracking: -0.6)
          .foregroundStyle(.white)
      }
      if let subsetLabel = document.subsetLabel {
        Text(ShareCardComposer.qualifierText(subsetLabel))
          .forge(isStory ? 13 : 11, .semibold)
          .foregroundStyle(Theme.metricSets)
      }
      if let subtitle = document.subtitle {
        Text(subtitle)
          .forge(isStory ? 13 : 12, .medium)
          .foregroundStyle(.white.opacity(0.6))
      }
    }
  }

  /// The planned target, never without its label — the label is why the number is honest.
  private func nextTargetBlock(_ target: ShareNextTarget) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(String(localized: "Next \(target.exerciseName) target", bundle: L10n.bundle))
        .forge(isStory ? 13 : 11, .semibold)
        .foregroundStyle(.white.opacity(0.55))
      Text(targetLine(target))
        .forge(isStory ? 22 : 18, .bold)
        .monospacedDigit()
        .foregroundStyle(.white)
      Text(ShareCardComposer.qualifierText(ShareCardQualifier.planned))
        .forge(isStory ? 12 : 11, .medium)
        .foregroundStyle(Theme.shareAccent)
    }
  }

  private var footer: some View {
    HStack(spacing: 6) {
      Image(systemName: "flame.fill").font(.system(size: isStory ? 13 : 11, weight: .bold))
      Text("REGULIFT").forge(isStory ? 13 : 11, .medium, tracking: 3)
    }
    .foregroundStyle(.white.opacity(0.6))
  }

  private func line(_ highlight: ShareHighlight) -> String {
    var text = ""
    if let load = highlight.load {
      text += Fmt.num(load.value) + " " + load.unit.rawValue + " × "
    }
    text += "\(highlight.reps)"
    if let rpe = highlight.rpeTenths {
      text += " @ RPE " + Fmt.num(Double(rpe) / 10)
    }
    return text
  }

  private func targetLine(_ target: ShareNextTarget) -> String {
    var text = ""
    if let load = target.load { text += Fmt.num(load.value) + " " + load.unit.rawValue + " × " }
    text += "\(target.minimumReps)–\(target.maximumReps)"
    return text
  }

  private func aggregate(_ value: ShareAggregate) -> String {
    [value.value, value.scopeLabel].compactMap { $0 }.joined(separator: " ")
  }
}

/// Renders a card into its fixed canvas.
///
/// A screenshot of a screen would capture buttons, bars and notifications; this draws the
/// template alone into 1080×1080 or 1080×1920 at sRGB.
enum ShareCardRenderer {
  @MainActor
  static func uiImage(_ document: CardDocument) -> UIImage? {
    let points = CGSize(
      width: CGFloat(document.format.pixelSize.width) / 3,
      height: CGFloat(document.format.pixelSize.height) / 3)
    let renderer = ImageRenderer(
      content:
        ShareCardView(document: document)
        // `ImageRenderer` builds a detached hierarchy: it inherits nothing from the view
        // tree it was called from. The in-app language switcher is a bundle override, so
        // the locale has to be handed over explicitly or a Vietnamese lifter exports an
        // English card with English decimal separators.
        .environment(\.locale, L10n.locale)
        // A card is a poster for other people. The author's text-size setting must not
        // change the exported artifact — their own need is served by the accessibility
        // description, which is built from the same document.
        .environment(\.dynamicTypeSize, .large)
        .frame(width: points.width, height: points.height)
        .clipped())
    // The content is laid out at a third of the canvas, so scale 3 lands exactly on 1080.
    // `proposedSize` is a proposal the content may refuse, hence the frame + clip above:
    // one unbreakable exercise name would otherwise widen the export and get cropped by
    // whatever receives it.
    renderer.proposedSize = ProposedViewSize(points)
    renderer.scale = 3
    renderer.isOpaque = true
    return renderer.uiImage
  }

  @MainActor
  static func image(_ document: CardDocument) -> Image {
    Image(uiImage: uiImage(document) ?? UIImage())
  }
}
