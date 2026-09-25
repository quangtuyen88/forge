import ForgeCore
import SwiftData
import SwiftUI

/// Share progress sheet: pick PDF or CSV, choose what to include, preview it, share the file.
struct ShareProgressSheet: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(AuthClient.self) private var auth

  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query(sort: \DecisionLogEntry.date, order: .reverse) private var decisions: [DecisionLogEntry]
  @Query(sort: \BodyMeasurement.date, order: .reverse) private var measurements: [BodyMeasurement]
  @Query(sort: \JourneyReflection.day, order: .reverse) private var reflections: [JourneyReflection]
  @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
  @Query private var profiles: [UserProfile]

  @AppStorage("shareProgressFormat") private var storedFormat = ProgressExportOptions.Format.pdf.rawValue

  @State private var options = ProgressExportOptions()
  @State private var fileURL: URL?
  @State private var reportContent: ReportContent?
  @State private var csvPreviewLines: [String] = []

  private let previewScale: CGFloat = 176 / 523

  /// The timeline's owner rule: the signed-in account id when present, else the local one.
  private var noteOwnerID: String {
    let account = JourneyEventID.canonicalOwner(auth.user?.id ?? "")
    let local = JourneyEventID.canonicalOwner(profiles.first?.journeyLocalOwnerID ?? "")
    return !account.isEmpty ? account : local
  }

  private var source: ProgressExportSource {
    let owner = noteOwnerID
    return ProgressExportSource(
      sessions: sessions,
      decisions: decisions,
      measurements: measurements,
      notes: owner.isEmpty
        ? [] : reflections.filter { JourneyEventID.canonicalOwner($0.ownerID) == owner },
      photos: photos,
      profile: profiles.first)
  }

  private var anyOn: Bool {
    options.workouts || options.programChanges || options.records
      || options.bodyStats || options.notes || options.photos
  }

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 10) {
          formatSection
          includeSection
          previewSection
          shareButton
          if !anyOn {
            Text("Turn on at least one item to share.")
              .forge(12, .medium)
              .foregroundStyle(Theme.textSecondary)
              .frame(maxWidth: .infinity, alignment: .center)
          }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.vertical, 12)
      }
      .background(Theme.page)
      .navigationTitle("Share progress")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
        }
      }
    }
    .presentationDragIndicator(.visible)
    .presentationBackground(Theme.page)
    .onAppear {
      if let format = ProgressExportOptions.Format(rawValue: storedFormat),
        format != options.format
      {
        options.format = format
      } else {
        regenerate()
      }
    }
    .onChange(of: options) { _, _ in
      regenerate()
    }
  }

  /// One pass per option change: page content, preview lines and file, so `body` reads state only.
  private func regenerate() {
    let source = source
    reportContent = ProgressExport.content(options, source: source)
    csvPreviewLines = ProgressExport.csv(options, source: source)
      .split(separator: "\n", omittingEmptySubsequences: true)
      .map(String.init)
    fileURL = ProgressExport.fileURL(options, source: source)
  }

  private var formatSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Format").forge(13, .semibold).foregroundStyle(Theme.textSecondary)
      LazyVGrid(
        columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible())],
        spacing: 12
      ) {
        formatCard(.pdf)
        formatCard(.csv)
      }
    }
  }

  private func formatCard(_ format: ProgressExportOptions.Format) -> some View {
    let selected = options.format == format
    return Button {
      options.format = format
      storedFormat = format.rawValue
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        if format == .pdf { pdfGlyph } else { csvGlyph }
        VStack(alignment: .leading, spacing: 2) {
          Text(
            format == .pdf
              ? String(localized: "PDF summary", bundle: L10n.bundle)
              : String(localized: "CSV data", bundle: L10n.bundle)
          )
          .forge(15, .semibold)
          .foregroundStyle(Theme.text)
          Text(
            format == .pdf
              ? String(localized: "One-page report", bundle: L10n.bundle)
              : String(localized: "For spreadsheets", bundle: L10n.bundle)
          )
          .forge(12, .medium)
          .foregroundStyle(Theme.textSecondary)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(14)
      .background(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .fill(selected ? Theme.accent.opacity(0.08) : Theme.innerSurface))
      .overlay(alignment: .topTrailing) {
        Image(systemName: selected ? "checkmark.circle.fill" : "circle")
          .font(.system(size: 20))
          .foregroundStyle(selected ? Theme.accent : Theme.textTertiary)
          .padding(10)
          .accessibilityHidden(true)
      }
      .overlay(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .strokeBorder(selected ? Theme.accent : Theme.ring, lineWidth: selected ? 2 : 1))
    }
    .buttonStyle(RowPressStyle())
    .accessibilityLabel(
      format == .pdf
        ? String(localized: "PDF summary, one-page report", bundle: L10n.bundle)
        : String(localized: "CSV data, for spreadsheets", bundle: L10n.bundle)
    )
    .accessibilityAddTraits(selected ? .isSelected : [])
    .accessibilityIdentifier("share.progress.format.\(format.rawValue)")
  }

  private var pdfGlyph: some View {
    VStack(alignment: .leading, spacing: 4) {
      Capsule()
        .fill(Theme.text)
        .frame(width: 30, height: 4)
      HStack(alignment: .bottom, spacing: 3) {
        glyphBar(11, current: false)
        glyphBar(16, current: false)
        glyphBar(20, current: false)
        glyphBar(15, current: true)
      }
      .frame(height: 20, alignment: .bottom)
      glyphLine(44)
      glyphLine(36)
      glyphLine(28)
    }
    .padding(7)
    .frame(width: 58, height: 74, alignment: .topLeading)
    .background(Theme.page)
    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: 5, style: .continuous).strokeBorder(Theme.ring, lineWidth: 1))
    .environment(\.colorScheme, .light)
    .accessibilityHidden(true)
  }

  private func glyphBar(_ height: CGFloat, current: Bool) -> some View {
    RoundedRectangle(cornerRadius: 1, style: .continuous)
      .fill(Theme.accent.opacity(current ? 1 : 0.35))
      .frame(width: 7, height: height)
  }

  private func glyphLine(_ width: CGFloat) -> some View {
    RoundedRectangle(cornerRadius: 1.5, style: .continuous)
      .fill(Theme.track)
      .frame(width: width, height: 3)
  }

  private var csvGlyph: some View {
    VStack(spacing: 2) {
      ForEach(0..<5, id: \.self) { row in
        HStack(spacing: 2) {
          ForEach(0..<3, id: \.self) { _ in
            RoundedRectangle(cornerRadius: 2, style: .continuous)
              .fill(row == 0 ? Theme.positive.opacity(0.55) : Theme.track)
              .frame(maxWidth: .infinity)
              .frame(height: 9)
          }
        }
      }
    }
    .padding(6)
    .frame(width: 58, height: 74, alignment: .top)
    .accessibilityHidden(true)
  }

  private var includeSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Include").forge(13, .semibold).foregroundStyle(Theme.textSecondary)
      VStack(spacing: 0) {
        includeRow("Workouts", art: "eq-dumbbell", isPrivate: false, isOn: $options.workouts, id: "workouts")
        Divider().padding(.leading, 70)
        includeRow("Program changes", art: "art-plan", isPrivate: false, isOn: $options.programChanges, id: "programChanges")
        Divider().padding(.leading, 70)
        includeRow("Records", art: "art-pro", isPrivate: false, isOn: $options.records, id: "records")
        Divider().padding(.leading, 70)
        includeRow("Body stats", art: "art-numbers", isPrivate: false, isOn: $options.bodyStats, id: "bodyStats")
        Divider().padding(.leading, 70)
        includeRow("Notes", art: "art-welcome", isPrivate: true, isOn: $options.notes, id: "notes")
        Divider().padding(.leading, 70)
        includeRow("Progress photos", art: nil, isPrivate: true, isOn: $options.photos, id: "photos")
      }
      .card(padding: 0)
      Text("Private notes and photos stay out unless you turn them on.")
        .forge(12, .medium)
        .foregroundStyle(Theme.textSecondary)
    }
  }

  private func includeRow(
    _ title: LocalizedStringKey,
    art: String?,
    isPrivate: Bool,
    isOn: Binding<Bool>,
    id: String
  ) -> some View {
    Toggle(isOn: isOn) {
      HStack(spacing: 12) {
        if let art {
          ArtTile(names: [art], size: 44)
        } else {
          Image(systemName: "lock.fill")
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(Theme.metricTime)
            .frame(width: 44, height: 44)
            .background(
              RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
                .fill(Theme.metricTime.opacity(0.14)))
            .overlay(
              RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
                .strokeBorder(Theme.imageOutline, lineWidth: 1))
            .accessibilityHidden(true)
        }
        HStack(spacing: 6) {
          Text(title).forgeBodyStrong()
          if isPrivate { PrivateTag() }
        }
      }
    }
    .tint(Theme.accent)
    .frame(maxWidth: .infinity, minHeight: 64)
    .padding(.horizontal, 14)
    .accessibilityIdentifier("share.progress.include.\(id)")
  }

  private var previewSection: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Preview").forge(13, .semibold).foregroundStyle(Theme.textSecondary)
      Group {
        if options.format == .pdf {
          pdfPreview
        } else {
          csvPreview
        }
      }
      .frame(maxWidth: .infinity)
      .padding(16)
      .background(
        RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
          .fill(Theme.accent.opacity(0.07)))
    }
  }

  private var pdfPreview: some View {
    Group {
      if let content = reportContent {
        ReportPage(content: content)
          .fixedSize(horizontal: false, vertical: true)
          .scaleEffect(previewScale, anchor: .topLeading)
      }
    }
    .frame(width: 176, height: 236, alignment: .topLeading)
    .clipped()
    .background(Theme.page)
    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: 6, style: .continuous)
        .strokeBorder(Theme.ring, lineWidth: 1))
    .environment(\.colorScheme, .light)
    .environment(\.locale, L10n.locale)
    .allowsHitTesting(false)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(pdfPreviewAccessibilityLabel)
  }

  private var pdfPreviewAccessibilityLabel: String {
    var included: [String] = []
    if options.workouts { included.append(String(localized: "workouts", bundle: L10n.bundle)) }
    if options.programChanges { included.append(String(localized: "program changes", bundle: L10n.bundle)) }
    if options.records { included.append(String(localized: "records", bundle: L10n.bundle)) }
    if options.bodyStats { included.append(String(localized: "body stats", bundle: L10n.bundle)) }
    if options.notes { included.append(String(localized: "notes", bundle: L10n.bundle)) }
    if options.photos { included.append(String(localized: "photos", bundle: L10n.bundle)) }

    let summary = String(localized: "Preview of the PDF summary", bundle: L10n.bundle)
    var label = summary + ": " + included.joined(separator: ", ")
    switch (!options.notes, !options.photos) {
    case (true, true):
      label += "; " + String(localized: "Notes and photos not included", bundle: L10n.bundle)
    case (true, false):
      label += "; " + String(localized: "Notes not included", bundle: L10n.bundle)
    case (false, true):
      label += "; " + String(localized: "Photos not included", bundle: L10n.bundle)
    default:
      break
    }
    return label
  }

  private var csvPreview: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(csvPreviewLines.prefix(8).enumerated()), id: \.offset) { _, line in
          Text(line)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.text)
            .lineLimit(1)
        }
        if csvPreviewLines.count > 8 {
          Text("…")
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(Theme.textSecondary)
        }
      }
    }
    .card(padding: 12)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(String(localized: "Preview of the CSV data", bundle: L10n.bundle))
  }

  private var shareButton: some View {
    ShareLink(item: fileURL ?? URL(fileURLWithPath: "share")) {
      HStack(spacing: 8) {
        Image(systemName: "square.and.arrow.up")
          .font(.system(size: 16, weight: .semibold))
        Text(
          options.format == .pdf
            ? String(localized: "Share PDF", bundle: L10n.bundle)
            : String(localized: "Share CSV", bundle: L10n.bundle)
        )
      }
    }
    .buttonStyle(PillButtonStyle())
    .disabled(fileURL == nil || !anyOn)
    .opacity(fileURL == nil || !anyOn ? 0.5 : 1)
    .accessibilityIdentifier("share.progress.share")
  }
}
