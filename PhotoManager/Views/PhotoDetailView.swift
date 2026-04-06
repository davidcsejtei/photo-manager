import SwiftUI
#if canImport(AppKit)
import AppKit
import QuickLookThumbnailing
#endif

struct PhotoDetailView: View {
    let photo: Photo
    @EnvironmentObject var albumVM: AlbumViewModel
    @EnvironmentObject var uploadVM: UploadBatchViewModel
    @EnvironmentObject var cameraVM: CameraViewModel

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    LargePreview(photo: photo)
                        .frame(maxWidth: .infinity, maxHeight: geo.size.height * 0.8)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(photo.fileName).font(.title3.weight(.semibold))
                        labeled("Méret", value: ByteCountFormatter.string(fromByteCount: photo.fileSize, countStyle: .file))
                        if let date = photo.captureDate {
                            labeled("Dátum", value: date.formatted(date: .abbreviated, time: .shortened))
                        }
                        labeled("Letöltve", value: photo.isDownloaded ? "Igen" : "Nem")
                    }

                    Divider()

                    addToAlbumSection
                    addToBatchSection
                }
                .padding()
            }
        }
    }

    private func labeled(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
    }

    private var addToAlbumSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Albumhoz adás").font(.headline)
            if albumVM.albums.isEmpty {
                Text("Még nincs album.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(albumVM.albums) { album in
                    Button {
                        albumVM.addPhotos([photo.id], to: album.id)
                    } label: {
                        HStack {
                            Image(systemName: "rectangle.stack")
                            Text(album.name)
                            Spacer()
                            if album.photoIDs.contains(photo.id) {
                                Image(systemName: "checkmark").foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var addToBatchSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Drive feltöltéshez adás").font(.headline)
            if uploadVM.batches.isEmpty {
                Text("Még nincs feltöltési mappa.").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(uploadVM.batches) { batch in
                    Button {
                        // A mock flow: csak a photoID-t rögzítjük. Valódi
                        // helyzetben előbb le kell tölteni a képet, és a
                        // `localURL`-eket átadni a VM-nek.
                        try? uploadVM.add(photoIDs: [photo.id], localURLs: [], to: batch.id)
                    } label: {
                        HStack {
                            Image(systemName: "tray.and.arrow.up")
                            Text(batch.name)
                            Spacer()
                            if batch.photoIDs.contains(photo.id) {
                                Image(systemName: "checkmark").foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Large preview

/// Nagy előnézet. A natúr képarányt megtartja (portrait-re is), a szélesség
/// a konténerrel nő, a max magasság nincs erősen korlátozva. Használja a
/// `ThumbnailCache`-t azonnali rajzoláshoz, majd nagyobb verziót generál.
private struct LargePreview: View {
    let photo: Photo

    #if canImport(AppKit)
    @State private var image: NSImage?
    #endif

    var body: some View {
        Group {
            #if canImport(AppKit)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
                    .frame(height: 360)
            }
            #else
            placeholder.frame(height: 360)
            #endif
        }
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: photo.id) { await load() }
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.15)
            Image(systemName: "photo")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func load() async {
        #if canImport(AppKit) && canImport(QuickLookThumbnailing)
        guard let url = photo.localURL else { return }

        // 1) Cache hit → azonnali rajzolás.
        if let cached = ThumbnailCache.shared.image(for: url) {
            self.image = cached
        } else {
            self.image = nil
        }

        // 2) Nagy verzió generálása háttérben.
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let target = CGSize(width: 2000, height: 1500)
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: target,
            scale: scale,
            representationTypes: .thumbnail
        )
        do {
            let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            let img = rep.nsImage
            ThumbnailCache.shared.set(img, for: url)
            // Csak akkor írjuk át, ha közben nem váltott más képre a user.
            if photo.localURL == url {
                self.image = img
            }
        } catch {
            // placeholder marad
        }
        #endif
    }
}
