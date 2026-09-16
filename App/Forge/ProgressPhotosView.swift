import SwiftUI
import SwiftData
import PhotosUI

struct ProgressPhotosView: View {
  @Query(sort: \ProgressPhoto.date, order: .reverse) private var photos: [ProgressPhoto]
  @Environment(\.modelContext) private var modelContext
  @State private var pickerItem: PhotosPickerItem?
  @State private var pose = ProgressPhoto.poses[0]
  @State private var compare = false
  @State private var selected: [ProgressPhoto] = []

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.groupGap) {
        Picker("Pose for the next photo", selection: $pose) {
          ForEach(ProgressPhoto.poses, id: \.self) { p in
            Text(p.capitalized).forge(13, .medium).tag(p)
          }
        }
        .pickerStyle(.segmented)
        if compare, selected.count == 2 {
          compareCard(selected[0], selected[1])
        }
        if photos.isEmpty {
          VStack(spacing: 8) {
            Illustration(name: "art-empty-progress", height: 120)
            Text("No photos yet").forgeSection()
            Text("Progress photos stay on this device, forever private.")
              .forgeLabel()
              .multilineTextAlignment(.center)
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
        Toggle("Compare", isOn: $compare)
      }
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
          guard compare else { return }
          if let i = selected.firstIndex(of: photo) {
            selected.remove(at: i)
          } else if selected.count < 2 {
            selected.append(photo)
          }
        } label: {
          VStack(spacing: 4) {
            Thumbnail(photo: photo, height: 120)
            Text("\(photo.date.formatted(.dateTime.month().day())) · \(photo.pose)").forgeCaption()
          }
          .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusRow, style: .continuous)
              .strokeBorder(selected.contains(photo) ? Theme.accent : .clear, lineWidth: 2))
          .opacity(compare ? 1 : 0.85)
        }
      }
    }
  }

  private func compareCard(_ a: ProgressPhoto, _ b: ProgressPhoto) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      Text("Compare").forgeSection()
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
      Text(photo.date.formatted(.dateTime.month().day().year())).forgeCaption()
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
