import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Drive-on letezo album tartalmat mutatja — ugyanolyan grid + preview
/// layouttal, mint a lokal albumok.
struct DriveAlbumView: View {
    let folderID: String
    @EnvironmentObject var albumVM: AlbumViewModel

    @State private var photos: [Photo] = []
    @State private var selection: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var driveFileMap: [String: GoogleDriveService.DriveFile] = [:]

    private let drive = GoogleDriveService.shared

    var body: some View {
        HSplitView {
            gridPane
                .frame(minWidth: 400, maxWidth: .infinity, maxHeight: .infinity)
            detailPane
                .frame(minWidth: 300, idealWidth: 500, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(albumName)
        .task(id: folderID) { await loadAlbum() }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    guard let da = currentDriveAlbum else { return }
                    Task { await albumVM.downloadDriveAlbumToLocal(driveAlbum: da) }
                } label: {
                    Label("Letoltes helyire", systemImage: "arrow.down.to.line")
                }
                .disabled(albumVM.downloadingDriveAlbumID != nil)
            }
        }
        .safeAreaInset(edge: .bottom) {
            if albumVM.downloadingDriveAlbumID == folderID {
                VStack(alignment: .leading, spacing: 4) {
                    ProgressView(value: albumVM.downloadProgress)
                        .progressViewStyle(.linear)
                    if let status = albumVM.downloadStatus {
                        Text(status).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(.thinMaterial)
            }
        }
    }

    private var currentDriveAlbum: DriveAlbum? {
        albumVM.driveAlbums.first(where: { $0.id == folderID })
    }

    private var albumName: String {
        currentDriveAlbum?.name ?? "Drive album"
    }

    // MARK: - Grid

    @ViewBuilder
    private var gridPane: some View {
        if isLoading {
            VStack {
                ProgressView("Betoltes...")
                    .padding()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage {
            ContentUnavailableView(
                "Hiba",
                systemImage: "exclamationmark.triangle",
                description: Text(error)
            )
        } else if photos.isEmpty {
            ContentUnavailableView(
                "Ures album",
                systemImage: "folder",
                description: Text("Ez a Drive mappa ures.")
            )
        } else {
            PhotoGridView(photos: photos, selection: $selection)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailPane: some View {
        if let photo = selectedPhoto {
            DrivePhotoDetail(photo: photo, driveFile: driveFileMap[photo.id])
        } else {
            ContentUnavailableView(
                "Nincs kivalasztott foto",
                systemImage: "photo.on.rectangle",
                description: Text("Jelolj ki egy kepet a reszletek megtekitesehez.")
            )
        }
    }

    private var selectedPhoto: Photo? {
        guard let id = selection.first else { return nil }
        return photos.first { $0.id == id }
    }

    // MARK: - Load

    private func loadAlbum() async {
        isLoading = true
        errorMessage = nil
        photos = []
        driveFileMap = [:]

        do {
            let files = try await drive.listFolderDetailed(folderID)
            let cacheDir = GoogleDriveService.cacheDir

            var newPhotos: [Photo] = []
            for f in files {
                driveFileMap[f.id] = f
                let thumbPath = cacheDir.appendingPathComponent("thumb_\(f.id).jpg")
                let hasThumb = FileManager.default.fileExists(atPath: thumbPath.path)
                newPhotos.append(Photo(
                    id: f.id,
                    fileName: f.name,
                    fileSize: f.size,
                    captureDate: f.createdTime,
                    thumbnailURL: hasThumb ? thumbPath : nil,
                    isDownloaded: false,
                    localURL: hasThumb ? thumbPath : nil,
                    deviceFileRef: nil
                ))
            }
            photos = newPhotos
            isLoading = false

            // Progressziv thumbnail letoltes hatterben
            for (i, file) in files.enumerated() {
                let thumbPath = cacheDir.appendingPathComponent("thumb_\(file.id).jpg")
                if FileManager.default.fileExists(atPath: thumbPath.path) { continue }
                guard let link = file.thumbnailLink else { continue }

                let biggerLink = link.replacingOccurrences(of: "=s220", with: "=s400")

                do {
                    try await drive.downloadThumbnail(link: biggerLink, to: thumbPath)
                    if i < photos.count, photos[i].id == file.id {
                        photos[i] = Photo(
                            id: file.id,
                            fileName: file.name,
                            fileSize: file.size,
                            captureDate: file.createdTime,
                            thumbnailURL: thumbPath,
                            isDownloaded: false,
                            localURL: thumbPath,
                            deviceFileRef: nil
                        )
                    }
                } catch {
                    // placeholder marad
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            isLoading = false
        }
    }
}

// MARK: - Drive photo detail

/// A Drive-rol szarmazo kep reszletei + nagy elonezet.
/// NSImage-bol kozvetlenul tolt be (nem QLThumbnailGenerator-bol),
/// mert a Drive-rol letoltott fajlok nem feltetlen rendelkeznek QL thumbnaillel.
private struct DrivePhotoDetail: View {
    let photo: Photo
    let driveFile: GoogleDriveService.DriveFile?

    #if canImport(AppKit)
    @State private var previewImage: NSImage?
    #endif
    @State private var isDownloading = false
    @State private var fullImageCached = false

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Nagy kep
                    imagePreview
                        .frame(maxWidth: .infinity, maxHeight: geo.size.height * 0.8)
                        .background(Color.black.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 10))

                    // Metaadatok
                    VStack(alignment: .leading, spacing: 6) {
                        Text(photo.fileName).font(.title3.weight(.semibold))
                        labeledRow("Meret", value: ByteCountFormatter.string(fromByteCount: photo.fileSize, countStyle: .file))
                        if let date = photo.captureDate {
                            labeledRow("Datum", value: date.formatted(date: .abbreviated, time: .shortened))
                        }
                        if let mime = driveFile?.mimeType {
                            labeledRow("Tipus", value: mime)
                        }
                        labeledRow("Forras", value: "Google Drive")
                    }
                }
                .padding()
            }
        }
        .task(id: photo.id) { await loadPreview() }
    }

    @ViewBuilder
    private var imagePreview: some View {
        #if canImport(AppKit)
        if let image = previewImage {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .overlay(alignment: .bottomTrailing) {
                    if isDownloading {
                        ProgressView()
                            .controlSize(.small)
                            .padding(8)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
                            .padding(8)
                    }
                }
        } else {
            ZStack {
                Color.gray.opacity(0.15)
                if isDownloading {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("Kep letoltese...").font(.caption).foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "photo")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
            }
        }
        #else
        Color.gray.opacity(0.15)
        #endif
    }

    private func labeledRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
    }

    @MainActor
    private func loadPreview() async {
        #if canImport(AppKit)
        previewImage = nil
        isDownloading = false
        fullImageCached = false

        // 1) Thumbnail — azonnali megjelenites, ha van cache-elt
        if let thumbURL = photo.localURL {
            previewImage = NSImage(contentsOf: thumbURL)
        }

        // 2) Teljes kep letoltese Drive-rol
        guard let driveFile else { return }
        let cacheDir = GoogleDriveService.cacheDir
        let ext = (driveFile.name as NSString).pathExtension
        let fullPath = cacheDir.appendingPathComponent("full_\(driveFile.id).\(ext)")

        if FileManager.default.fileExists(atPath: fullPath.path) {
            if let img = NSImage(contentsOf: fullPath) {
                previewImage = img
                fullImageCached = true
            }
            return
        }

        isDownloading = true
        do {
            try await GoogleDriveService.shared.downloadFileContent(fileID: driveFile.id, to: fullPath)
            if let img = NSImage(contentsOf: fullPath) {
                previewImage = img
                fullImageCached = true
            }
        } catch {
            // Marad a thumbnail
        }
        isDownloading = false
        #endif
    }
}
