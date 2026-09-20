import PhotosUI
import SwiftData
import SwiftUI

struct ProgressPhotosView: View {
  @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
  @Environment(\.modelContext) private var modelContext
  @State private var pickerItem: PhotosPickerItem?
  @State private var pose = ProgressPhoto.poses[0]
  @State private var selected: [ProgressPhoto] = []

  /// Current comparison: the tapped pair when two are picked, else newest vs oldest of the same pose.
  private var pair: (ProgressPhoto, ProgressPhoto)? {
    if selected.count == 2 {
      let ordered = selected.sorted { $0.date < $1.date }
      return (ordered[0], ordered[1])
    }
    guard let newest = photos.first, photos.count >= 2 else { return nil }
    let samePose = photos.dropFirst().filter { $0.pose == newest.pose }
    return (samePose.last ?? photos.last!, newest)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.groupGap) {
        Picker("Pose for the next photo", selection: $pose) {
          ForEach(ProgressPhoto.poses, id: \.self) { p in
            Text(p.capitalized).forge(13, .medium).tag(p)
          }
        }
        .pickerStyle(.segmented)
        if let pair {
          compareCard(pair.0, pair.1)
        }
        if photos.isEmpty {
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
        } else {
          grid
        }
      }
      .padding(.horizontal, Theme.margin)
      .padding(.bottom, 24)
    }
    .background(Theme.page)
    .navigationTitle("Photos")
    .toolbar {
      ToolbarItem(placement: .topBarTrailing) {
        PhotosPicker(selection: $pickerItem, matching: .images) {
          Image(systemName: "plus")
        }
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
  }

  private var grid: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: 10)], spacing: 12) {
      ForEach(photos) { photo in
        Button {
          if selected.isEmpty, let pair { selected = [pair.0, pair.1] }
          if let i = selected.firstIndex(of: photo) {
            selected.remove(at: i)
          } else if selected.count < 2 {
            selected.append(photo)
          } else {
            selected = [selected[1], photo]
          }
        } label: {
          VStack(spacing: 4) {
            Thumbnail(photo: photo, height: 120)
            Text(
              "\(photo.date.formatted(.dateTime.month().day().locale(L10n.locale))) · \(photo.pose)"
            ).forgeCaption()
          }
          .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
              .strokeBorder(inPair(photo) ? Theme.accent : .clear, lineWidth: 2))
        }
      }
    }
  }

  private func inPair(_ photo: ProgressPhoto) -> Bool {
    guard let pair else { return false }
    return pair.0 == photo || pair.1 == photo
  }

  private func compareCard(_ a: ProgressPhoto, _ b: ProgressPhoto) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      VStack(alignment: .leading, spacing: 4) {
        Text("Compare").forgeSection()
        Text("Tap a photo to change the pair.").forgeCaption()
      }
      HStack(spacing: 10) {
        compareHalf(a)
        compareHalf(b)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .card()
  }

  private func compareHalf(_ photo: ProgressPhoto) -> some View {
    VStack(spacing: 6) {
      Thumbnail(photo: photo, height: 220)
      Text(photo.date.formatted(.dateTime.month().day().year().locale(L10n.locale))).forgeCaption()
    }
    .frame(maxWidth: .infinity)
  }
}

private struct Thumbnail: View {
  let photo: ProgressPhoto
  var height: CGFloat

  var body: some View {
    Group {
      if let ui = UIImage(contentsOfFile: photo.fileURL.path) {
        Image(uiImage: ui).resizable().scaledToFill()
      } else {
        Theme.innerSurface
      }
    }
    .frame(maxWidth: .infinity)
    .frame(height: height)
    .clipped()
    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous))
  }
}
