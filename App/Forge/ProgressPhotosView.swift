import PhotosUI
import SwiftData
import SwiftUI

/// Photos: can I see my change, privately? Blurred until the lifter taps Show; the reveal
/// resets when the page is left. Everything stays on this device.
struct ProgressPhotosView: View {
  @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
  @Query(sort: \BodyMeasurement.date) private var measurements: [BodyMeasurement]
  @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]
  @Query private var profiles: [UserProfile]
  @Environment(\.modelContext) private var modelContext
  @State private var pickerItem: PhotosPickerItem?
  @State private var pose = ProgressPhoto.poses[0]
  @State private var revealed = false
  @State private var comparePose = ProgressPhoto.poses[0]
  @State private var pendingDelete: ProgressPhoto?

  private var profile: UserProfile? { profiles.first }

  private var ordered: [ProgressPhoto] { photos.sorted { $0.date < $1.date } }

  /// Poses the collection actually has, display-cased for the segmented control.
  private var posesPresent: [String] {
    ProgressPhoto.poses.filter { pose in photos.contains { $0.pose == pose } }
  }

  /// First vs latest of the compare pose.
  private var pair: (first: ProgressPhoto, last: ProgressPhoto)? {
    let inPose = ordered.filter { $0.pose == comparePose }
    guard inPose.count >= 2 else { return nil }
    return (first: inPose.first!, last: inPose.last!)
  }

  var body: some View {
    ScrollView {
      LazyVStack(spacing: 0) {
        ProgressLargeTitle(title: "Photos", subtitle: subtitle, art: "art-camera")
          .padding(.horizontal, Theme.margin)
          .padding(.bottom, 20)
        privacyStrip
          .padding(.horizontal, Theme.margin)
          .padding(.bottom, 20)
        if photos.isEmpty {
          emptyCard
            .padding(.horizontal, Theme.margin)
        } else {
          compareSection
          LogBand()
          allPhotos.padding(.bottom, 24)
        }
      }
    }
    .background(Theme.page)
    .progressTitleNavigation("Photos")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        PhotosPicker(selection: $pickerItem, matching: .images) {
          Image(systemName: "photo.badge.plus")
        }
        .accessibilityLabel(String(localized: "Add photo", bundle: L10n.bundle))
      }
    }
    .onChange(of: pickerItem) { _, item in
      guard let item else { return }
      Task {
        if let data = try? await item.loadTransferable(type: Data.self) {
          ProgressPhoto.insert(data, date: .now, pose: pose, context: modelContext)
        }
        pickerItem = nil
      }
    }
    .onDisappear { revealed = false }
    .onChange(of: posesPresent) { _, poses in
      guard !poses.isEmpty, !poses.contains(comparePose) else { return }
      comparePose = poses[0]
    }
    .confirmationDialog(
      "Delete this photo?",
      isPresented: Binding(
        get: { pendingDelete != nil },
        set: { if !$0 { pendingDelete = nil } }),
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) {
        guard let photo = pendingDelete else { return }
        photo.deleteFile()
        modelContext.delete(photo)
        pendingDelete = nil
      }
      Button("Cancel", role: .cancel) { pendingDelete = nil }
    } message: {
      Text("It is removed from this iPhone.")
    }
  }

  private var subtitle: String? {
    guard let first = ordered.first else { return nil }
    let count = photos.count
    if count == 1 {
      return String(
        localized: "1 photo · \(first.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))",
        bundle: L10n.bundle)
    }
    return String(
      localized: "\(count) photos · \(first.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))) to \(ordered.last!.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))",
      bundle: L10n.bundle)
  }

  // MARK: privacy

  private var privacyStrip: some View {
    V3NoteRow(icon: revealed ? "eye" : "lock", title: revealed ? showingTitle : privateTitle,
      subtitle: revealed ? showingDetail : privateDetail) {
      Button {
        revealed.toggle()
      } label: {
        Text(verbatim: revealed ? hideTitle : showTitle)
          .forge(16, .medium)
          .foregroundStyle(Theme.accentText)
          .frame(minHeight: 44)
          .contentShape(Rectangle())
      }
      .accessibilityLabel(revealed ? hideA11y : showA11y)
    }
  }

  private var privateTitle: String { String(localized: "Stays on this device", bundle: L10n.bundle) }
  private var privateDetail: String { String(localized: "Blurred until you tap Show", bundle: L10n.bundle) }
  private var showingTitle: String { String(localized: "Showing photos", bundle: L10n.bundle) }
  private var showingDetail: String { String(localized: "They blur again when you leave", bundle: L10n.bundle) }
  private var showTitle: String { String(localized: "Show", bundle: L10n.bundle) }
  private var hideTitle: String { String(localized: "Hide", bundle: L10n.bundle) }
  private var showA11y: String { String(localized: "Show photos", bundle: L10n.bundle) }
  private var hideA11y: String { String(localized: "Hide photos", bundle: L10n.bundle) }

  // MARK: compare

  private var compareSection: some View {
    VStack(spacing: 0) {
      HStack(alignment: .center) {
        Text("Compare").forge(20, .bold).tracking(-0.3).foregroundStyle(Theme.text)
        Spacer(minLength: 12)
        if posesPresent.count > 1 {
          Picker("Pose", selection: $comparePose) {
            ForEach(posesPresent, id: \.self) { pose in
              Text(verbatim: pose.capitalized).forge(13, .medium).tag(pose)
            }
          }
          .pickerStyle(.segmented)
          .frame(width: 148)
          .accessibilityIdentifier("photos.pose")
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 10)
      if let pair {
        HStack(alignment: .top, spacing: 10) {
          compareHalf(pair.first)
          compareHalf(pair.last)
        }
        .padding(.horizontal, Theme.margin)
        .padding(.bottom, 12)
        Text(verbatim: compareFootnote(pair))
          .forge(13, .regular)
          .foregroundStyle(Theme.textSecondary)
          .monospacedDigit()
          .padding(.horizontal, Theme.margin)
          .padding(.bottom, 20)
      }
    }
  }

  private func compareHalf(_ photo: ProgressPhoto) -> some View {
    VStack(spacing: 8) {
      PhotoTile(photo: photo, revealed: revealed)
        .contextMenu { deletePhotoButton(photo) }
      VStack(alignment: .leading, spacing: 1) {
        Text(
          photo.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
        )
        .forge(15, .semibold)
        .foregroundStyle(Theme.text)
        .frame(maxWidth: .infinity, alignment: .leading)
        if let placement = blockPlacement(of: photo.date) {
          Text(verbatim: placement)
            .forge(13, .regular)
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
    }
    .frame(maxWidth: .infinity)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(
      String(
        localized: "\(photo.pose.capitalized) photo, \(photo.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale)))",
        bundle: L10n.bundle))
    .accessibilityAction(named: String(localized: "Delete photo", bundle: L10n.bundle)) {
      pendingDelete = photo
    }
  }

  /// "8 weeks apart · waist 86 → 84 cm" — the waist part only when both dates have one.
  private func compareFootnote(_ pair: (first: ProgressPhoto, last: ProgressPhoto)) -> String {
    let weeks = Int(pair.last.date.timeIntervalSince(pair.first.date) / (7 * 86400))
    let weeksText = String(
      localized: "\(weeks) week\(L10n.pluralSuffix(weeks)) apart", bundle: L10n.bundle)
    guard let firstWaist = waist(at: pair.first.date), let lastWaist = waist(at: pair.last.date),
      abs(firstWaist - lastWaist) >= 0.5
    else { return weeksText }
    return String(
      localized: "\(weeksText) · waist \(Fmt.num(firstWaist, max: 1)) → \(Fmt.num(lastWaist, max: 1)) cm",
      bundle: L10n.bundle)
  }

  /// Waist measurement of the day, or the latest one before it.
  private func waist(at date: Date) -> Double? {
    measurements
      .compactMap { m in
        Calendar.current.isDate(m.date, inSameDayAs: date) || m.date < date
          ? m.tape["waist"].map { (m.date, $0) } : nil
      }
      .filter { $0.1 > 0 }
      .max { $0.0 < $1.0 }?.1
  }

  /// "Block 2 · week 3" of a photo date, from the same block walk History uses.
  private func blockPlacement(of date: Date) -> String? {
    let blocks = LogV3.blocks(sessions: sessions, profile: profile)
    for block in blocks {
      for week in block.weeks where date >= week.firstDate && date <= week.lastDate.addingTimeInterval(86400) {
        return String(
          localized: "Block \(block.number) · week \(week.week)", bundle: L10n.bundle)
      }
    }
    return nil
  }

  // MARK: all photos

  private var photoDays: [(date: Date, photos: [ProgressPhoto])] {
    let groups = Dictionary(grouping: photos) { Calendar.current.startOfDay(for: $0.date) }
    return groups.keys.sorted(by: >).map { day in
      (date: day, photos: groups[day]!.sorted { $0.pose < $1.pose })
    }
  }

  private var allPhotos: some View {
    VStack(spacing: 0) {
      V3SectionHeader("All photos")
      ForEach(Array(photoDays.enumerated()), id: \.offset) { index, day in
        if index > 0 { Divider().padding(.horizontal, Theme.margin) }
        photoDayRow(day)
      }
    }
  }

  private func photoDayRow(_ day: (date: Date, photos: [ProgressPhoto])) -> some View {
    let names = day.photos.map(\.pose)
    let poses = names.map { $0.capitalized }.formatted(.list(type: .and).locale(L10n.locale))
    let row = HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(
          day.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
        )
        .forge(17, .semibold)
        .foregroundStyle(Theme.text)
        Text(verbatim: poses)
          .forge(14, .regular)
          .foregroundStyle(Theme.textSecondary)
      }
      Spacer(minLength: 8)
      ForEach(day.photos) { photo in
        SmallPhotoTile(photo: photo, revealed: revealed)
          .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
              .strokeBorder(inPair(photo) ? Theme.accent : .clear, lineWidth: 2))
          .contextMenu { deletePhotoButton(photo) }
      }
    }
    .padding(.horizontal, Theme.margin)
    .padding(.vertical, 12)
    .frame(minHeight: 60)
    .accessibilityElement(children: .combine)
    .accessibilityLabel(dayRowLabel(day, poses: poses))
    // Tiles are hidden when combined, so each photo needs its own named delete action.
    return deleteActions(row, photos: day.photos)
  }

  /// Applies one VoiceOver delete action per photo, because a row can hold several poses.
  private func deleteActions(_ row: some View, photos: [ProgressPhoto]) -> AnyView {
    guard let photo = photos.first else { return AnyView(row) }
    let name = photos.count == 1
      ? String(localized: "Delete photo", bundle: L10n.bundle)
      : String(localized: "Delete \(photo.pose.capitalized) photo", bundle: L10n.bundle)
    return deleteActions(
      row.accessibilityAction(named: name) { pendingDelete = photo },
      photos: Array(photos.dropFirst()))
  }

  /// "Front and side photos, Sep 29", plus "front in comparison" for the outlined pair tiles.
  private func dayRowLabel(
    _ day: (date: Date, photos: [ProgressPhoto]), poses: String
  ) -> String {
    let date = day.date.formatted(.dateTime.month(.abbreviated).day().locale(L10n.locale))
    let base = String(localized: "\(poses) photos, \(date)", bundle: L10n.bundle)
    let compared = day.photos.filter { inPair($0) }.map { $0.pose.capitalized }
    guard !compared.isEmpty else { return base }
    let list = compared.formatted(.list(type: .and).locale(L10n.locale))
    return base + String(localized: ", \(list) in comparison", bundle: L10n.bundle)
  }

  private func inPair(_ photo: ProgressPhoto) -> Bool {
    guard let pair else { return false }
    return pair.first.id == photo.id || pair.last.id == photo.id
  }

  private func deletePhotoButton(_ photo: ProgressPhoto) -> some View {
    Button("Delete photo", role: .destructive) { pendingDelete = photo }
  }

  // MARK: empty

  private var emptyCard: some View {
    VStack(spacing: 12) {
      Image(systemName: "person.crop.rectangle.stack.fill")
        .font(.system(size: 42, weight: .semibold))
        .foregroundStyle(Theme.metricTime)
        .frame(width: 84, height: 84)
        .background(Circle().fill(Theme.metricTime.opacity(0.12)))
      Text("No progress photos yet").forgeSection()
      Text(
        "Photos are optional and stay private on this device unless you explicitly export them."
      )
      .forgeLabel()
      .multilineTextAlignment(.center)
      PhotosPicker(selection: $pickerItem, matching: .images) {
        Label("Add photo", systemImage: "plus")
      }
      .buttonStyle(PillButtonStyle(minHeight: 44))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 24)
    .card()
  }
}

/// One 3:4 photo tile, blurred with a glass veil until revealed (mock .ph).
struct PhotoTile: View {
  let photo: ProgressPhoto
  let revealed: Bool
  var small = false

  private var blur: CGFloat { small ? 6 : 12 }

  var body: some View {
    ZStack {
      Group {
        if let ui = UIImage(contentsOfFile: photo.fileURL.path) {
          Image(uiImage: ui).resizable().scaledToFill()
        } else {
          Theme.innerSurface
        }
      }
      .blur(radius: revealed ? 0 : blur)
      .saturation(revealed ? 1 : 0.7)
      if !revealed {
        Image(systemName: "eye.slash")
          .font(.system(size: small ? 14 : 20, weight: .semibold))
          .foregroundStyle(Theme.text)
          .frame(width: small ? 32 : 44, height: small ? 32 : 44)
          .background(Circle().fill(Theme.todayGlass))
          .overlay(Circle().strokeBorder(Theme.todayCardRing, lineWidth: 1))
      }
    }
    .aspectRatio(3 / 4, contentMode: .fit)
    .frame(maxWidth: .infinity)
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
    .overlay(
      RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
        .strokeBorder(Theme.imageOutline, lineWidth: 1))
    .accessibilityHidden(true)
  }
}

private struct SmallPhotoTile: View {
  let photo: ProgressPhoto
  let revealed: Bool

  var body: some View {
    PhotoTile(photo: photo, revealed: revealed, small: true)
      .frame(width: 66)
  }
}
