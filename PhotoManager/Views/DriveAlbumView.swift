import SwiftUI

/// Drive-on letezo album tartalmat mutatja — ugyanolyan grid + preview
/// layouttal, mint a lokal albumok. A thumbnaileket es a nagy kepeket
/// a Google Drive API-rol tolti le es lokalisan cache-eli.
struct DriveAlbumView: View {
    let folderID: String
    @EnvironmentObject var albumVM: AlbumViewModel

    @State private var photos: [Photo] = []
    @State private var selection: Set<String> = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    /// Drive file ID -> drive file, a teljes kep letolteshez.
    @State private var driveFileMap: [String: GoogleDriveService.DriveFile] = [:]

    private let drive = GoogleDriveService.shared

    var body: some View {
        HSplitView {
            gridPane
                .frame(minWidth: 400)
            detailPane
                .frame(minWidth: 300, idealWidth: 500)
        }
        .navigationTitle(albumName)
        .task(id: folderID) { await loadAlbum() }
    }

    private var albumName: String {
        albumVM.driveAlbums.first(where: { $0.id == folderID })?.name ?? "Drive album"
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

            // Photo objektumok letrehozasa — meg thumbnail nelkul
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

                // A Google thumbnailLink-ben levo s220 meretet nagyobbra csereljuk
                let biggerLink = link.replacingOccurrences(of: "=s220", with: "=s400")

                do {
                    try await drive.downloadThumbnail(link: biggerLink, to: thumbPath)
                    // Frissitjuk a Photo objektumot a letoltott thumbnail-lel
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
                    // Csendben — placeholder marad
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
/// A nagy kepet on-demand tolti le a Drive API-rol.
private struct DrivePhotoDetail: View {
    let photo: Photo
    let driveFile: GoogleDriveService.DriveFile?

    @State private var fullImageURL: URL?
    @State private var isDownloading = false

    var body: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Nagy kep
                    Group {
                        if let url = fullImageURL {
                            ThumbnailView(
                                url: url,
                                targetSize: CGSize(width: 2000, height: 1500),
                                contentMode: .fit
                            )
                        } else if let url = photo.localURL {
                            // Thumbnail mint placeholder
                            ThumbnailView(
                                url: url,
                                targetSize: CGSize(width: 600, height: 400),
                                contentMode: .fit
                            )
                            .overlay {
                                if isDownloading {
                                    ProgressView()
                                        .controlSize(.regular)
                                        .padding(8)
                                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        } else {
                            Rectangle()
                                .fill(Color.gray.opacity(0.15))
                                .overlay {
                                    if isDownloading {
                                        ProgressView("Kep letoltese...")
                                    } else {
                                        Image(systemName: "photo")
                                            .font(.system(size: 48))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: geo.size.height * 0.8)
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
        .task(id: photo.id) { await downloadFullImage() }
    }

    private func labeledRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value)
        }
        .font(.callout)
    }

    private func downloadFullImage() async {
        guard let driveFile else { return }
        let cacheDir = GoogleDriveService.cacheDir
        let ext = (driveFile.name as NSString).pathExtension
        let fullPath = cacheDir.appendingPathComponent("full_\(driveFile.id).\(ext)")

        // Mar letezik a cache-ben?
        if FileManager.default.fileExists(atPath: fullPath.path) {
            fullImageURL = fullPath
            return
        }

        isDownloading = true
        do {
            try await GoogleDriveService.shared.downloadFileContent(fileID: driveFile.id, to: fullPath)
            fullImageURL = fullPath
        } catch {
            // Marad a thumbnail
        }
        isDownloading = false
    }
}
