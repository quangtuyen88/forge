import SwiftUI
import ForgeCore

/// Share Cards v2 — the composer and its renderer.
///
/// The card is a snapshot: it is built from one coherent saved source, rendered into a
/// fixed canvas, and the image the lifter approves is the image that is handed off. It
/// reads training data and writes none: opening, editing, cancelling or failing an export
/// cannot change a workout, a plan or an award.
struct ShareCardComposer: View {
  let document: CardDocument
  var onClose: () -> Void

  @State private var format: ShareCardFormat
  @State private var disclosure: ShareDisclosure
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  /// The content the card was built from, kept so a toggle rebuilds the document rather
  /// than editing the rendered image.
  private let source: ShareCardSource

  init(source: ShareCardSource, onClose: @escaping () -> Void) {
    self.source = source
    self.onClose = onClose
    _format = State(initialValue: source.format)
    _disclosure = State(initialValue: .safeDefaults)
    document = source.document(format: source.format, disclosure: .safeDefaults)
  }

  private var current: CardDocument {
    source.document(format: format, disclosure: disclosure)
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: Theme.groupGap) {
          // The preview is the template at display scale; the export renders the same
          // view into the fixed canvas, so what is approved is what is delivered.
          ShareCardView(document: current)
            .frame(maxWidth: .infinity)
            .accessibilityIdentifier("share.preview")
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Self.accessibilityText(current))

          picker
          details
        }
        .padding(Theme.margin)
      }
      .background(Theme.page)
      .navigationTitle(String(localized: "Share workout", bundle: L10n.bundle))
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button(String(localized: "Close", bundle: L10n.bundle), action: onClose)
            .accessibilityIdentifier("share.close")
        }
      }
      .safeAreaInset(edge: .bottom) {
        VStack(spacing: 8) {
          ShareLink(
            item: ShareCardRenderer.image(current),
            preview: SharePreview(current.title)
          ) {
            Text(String(localized: "Share…", bundle: L10n.bundle))
          }
          .buttonStyle(PillButtonStyle())
          .accessibilityIdentifier("share.export")
          Text(
            String(
              localized: "Sharing hands the finished image to another app. Regulift does not post it for you.",
              bundle: L10n.bundle)
          )
          .forgeCaption()
          .multilineTextAlignment(.center)
        }
        .padding(.horizontal, Theme.barMargin)
        .padding(.vertical, 10)
        .background(Theme.page.opacity(0.92))
        .background(.ultraThinMaterial)
      }
    }
    .presentationBackground(Theme.page)
  }

  private var picker: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(String(localized: "Format", bundle: L10n.bundle)).forgeSection()
      Picker(String(localized: "Format", bundle: L10n.bundle), selection: $format) {
        Text(String(localized: "Square", bundle: L10n.bundle)).tag(ShareCardFormat.square)
        Text(String(localized: "Story", bundle: L10n.bundle)).tag(ShareCardFormat.story)
      }
      .pickerStyle(.segmented)
      .accessibilityIdentifier("share.format")
    }
    .card()
  }

  /// Every detail is off until the lifter turns it on, and turning one off removes it from
  /// the image, the caption and the accessibility description together.
  private var details: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(String(localized: "Details", bundle: L10n.bundle)).forgeSection()
      Toggle(String(localized: "RPE", bundle: L10n.bundle), isOn: $disclosure.showsRPE)
        .accessibilityIdentifier("share.detail.rpe")
      Toggle(String(localized: "Date", bundle: L10n.bundle), isOn: $disclosure.showsDate)
        .accessibilityIdentifier("share.detail.date")
      if source.hasNextTarget {
        Toggle(
          String(localized: "Next session target", bundle: L10n.bundle),
          isOn: $disclosure.showsNextTarget
        )
        .accessibilityIdentifier("share.detail.nextTarget")
        Text(String(localized: "Planned — not completed", bundle: L10n.bundle))
          .forgeCaption()
      }
    }
    .tint(Theme.metricSets)
    .card()
  }

  /// The same visible information, in text. Mandatory qualifiers survive here too.
  static func accessibilityText(_ document: CardDocument) -> String {
    ShareCardBuilder.caption(
      for: document,
      line: { highlight in
        var line = highlight.exerciseName
        if let load = highlight.load {
          line += " " + Fmt.num(load.value) + " " + load.unit.rawValue
        }
        line += " × \(highlight.reps)"
        if let rpe = highlight.rpeTenths { line += " RPE \(Double(rpe) / 10)" }
        return line
      },
      qualifierText: Self.qualifierText)
  }

  static func qualifierText(_ key: String) -> String {
    switch key {
    case ShareCardQualifier.planned:
      return String(localized: "Planned — not completed", bundle: L10n.bundle)
    case ShareCardQualifier.unverified:
      return String(localized: "Unverified", bundle: L10n.bundle)
    case ShareCardQualifier.selectedSubset:
      return String(localized: "Selected top sets", bundle: L10n.bundle)
    default:
      return key
    }
  }
}

/// The content a card is built from, captured once from a saved source.
struct ShareCardSource {
  let title: String
  let date: Date
  let highlights: [ShareHighlight]
  let totalExerciseCount: Int
  let aggregates: [ShareAggregate]
  let nextTarget: ShareNextTarget?
  var format: ShareCardFormat = .square
  var look: ShareCardLook = .clean

  var hasNextTarget: Bool { nextTarget != nil }

  func document(format: ShareCardFormat, disclosure: ShareDisclosure) -> CardDocument {
    let result = ShareCardBuilder.topSets(
      title: title, date: date, highlights: highlights,
      totalExerciseCount: totalExerciseCount, aggregates: aggregates,
      nextTarget: nextTarget, disclosure: disclosure, format: format, look: look,
      dateText: { $0.formatted(date: .abbreviated, time: .omitted) })
    if case .ready(let document) = result { return document }
    // An empty state is still a document: the composer shows "nothing eligible", never a
    // card with invented content.
    return CardDocument(
      template: .topSets, format: format, look: look, title: title, subtitle: nil,
      highlights: [], aggregates: [], nextTarget: nil, subsetLabel: nil,
      mandatoryQualifiers: [])
  }
}
