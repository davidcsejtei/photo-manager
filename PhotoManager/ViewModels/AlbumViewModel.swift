import Foundation

@MainActor
final class AlbumViewModel: ObservableObject {

    @Published private(set) var albums: [Album] = []
    @Published var selectedAlbumID: UUID?
    @Published var isCreatingAlbum: Bool = false
    @Published var newAlbumName: String = ""
    @Published var createError: String?

    /// Drive upload state
    @Published var uploadingAlbumID: UUID?
    @Published var uploadStatus: String?
    @Published var uploadError: String?
    @Published var uploadProgress: Double = 0        // 0.0 ... 1.0
    @Published var uploadedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var remainingBytes: Int64 = 0

    /// Drive-on letezo albumok (beleertve a csak tavolrol letezokat is).
    @Published private(set) var driveAlbums: [DriveAlbum] = []
    @Published var isFetchingDriveAlbums: Bool = false

    private let store = AlbumStore()
    private let drive = GoogleDriveService.shared

    init() {
        self.albums = store.load()
    }

    // MARK: - CRUD

    func startCreatingAlbum() {
        newAlbumName = ""
        createError = nil
        isCreatingAlbum = true
    }

    func confirmCreateAlbum() {
        let name = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        if albums.contains(where: { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) {
            createError = "Mar letezik album \"\(name)\" nevvel."
            return
        }

        let album = Album(name: name)
        albums.append(album)
        persist()
        selectedAlbumID = album.id
        isCreatingAlbum = false
        createError = nil
    }

    func renameAlbum(_ id: UUID, to newName: String) {
        guard let idx = albums.firstIndex(where: { $0.id == id }) else { return }
        albums[idx].name = newName
        persist()
    }

    func deleteAlbum(_ id: UUID) {
        albums.removeAll { $0.id == id }
        if selectedAlbumID == id { selectedAlbumID = nil }
        persist()
    }

    // MARK: - Assignment

    func addPhotos(_ photoIDs: [String], to albumID: UUID) {
        guard let idx = albums.firstIndex(where: { $0.id == albumID }) else { return }
        var existing = Set(albums[idx].photoIDs)
        for id in photoIDs where !existing.contains(id) {
            albums[idx].photoIDs.append(id)
            existing.insert(id)
        }
        persist()
    }

    func removePhotos(_ photoIDs: [String], from albumID: UUID) {
        guard let idx = albums.firstIndex(where: { $0.id == albumID }) else { return }
        let toRemove = Set(photoIDs)
        albums[idx].photoIDs.removeAll { toRemove.contains($0) }
        persist()
    }

    // MARK: - Drive upload

    /// Album feltoltese a Drive-ra: Fotok/{ev}/{album neve}/ strukturaba.
    func uploadAlbumToDrive(albumID: UUID, allPhotos: [Photo]) async {
        guard let album = albums.first(where: { $0.id == albumID }) else { return }
        guard drive.isSignedIn else {
            uploadError = "Eloszor csatlakozz a Google Drive-hoz a Beallitasokban."
            return
        }

        uploadingAlbumID = albumID
        uploadStatus = "Elofelkeszites..."
        uploadError = nil
        uploadProgress = 0
        uploadedCount = 0
        totalCount = 0
        remainingBytes = 0

        do {
            // Fix Drive gyokermappa: "Fotok" (csillagozott, a user altal megadott)
            let fotokID = "1K4BSqP_zIobVG_npR7vsWznADLtkAe8i"
            let year = String(Calendar.current.component(.year, from: album.createdAt))
            let yearID = try await drive.findOrCreateFolder(named: year, parentID: fotokID)
            let albumFolderID = try await drive.findOrCreateFolder(named: album.name, parentID: yearID)

            let existing = try await drive.listFolder(albumFolderID)
            let photosToUpload = allPhotos
                .filter { album.photoIDs.contains($0.id) && $0.localURL != nil }
                .filter { existing[$0.localURL!.lastPathComponent] == nil }

            totalCount = photosToUpload.count
            let totalBytes = photosToUpload.reduce(Int64(0)) { $0 + $1.fileSize }
            remainingBytes = totalBytes

            if totalCount == 0 {
                uploadStatus = "Minden kep mar fent van a Drive-on."
                uploadProgress = 1
                uploadingAlbumID = nil
                if let idx = albums.firstIndex(where: { $0.id == albumID }) {
                    albums[idx].driveFolderID = albumFolderID
                    persist()
                }
                return
            }

            uploadStatus = formatProgress(uploaded: 0, total: totalCount, remainingBytes: remainingBytes)

            var uploadedBytes: Int64 = 0
            for photo in photosToUpload {
                guard let url = photo.localURL else { continue }
                try await drive.uploadFile(at: url, toFolder: albumFolderID)
                uploadedCount += 1
                uploadedBytes += photo.fileSize
                remainingBytes = totalBytes - uploadedBytes
                uploadProgress = Double(uploadedCount) / Double(totalCount)
                uploadStatus = formatProgress(
                    uploaded: uploadedCount,
                    total: totalCount,
                    remainingBytes: remainingBytes
                )
            }

            if let idx = albums.firstIndex(where: { $0.id == albumID }) {
                albums[idx].driveFolderID = albumFolderID
                persist()
            }

            uploadStatus = "\"\(album.name)\" feltoltve (\(uploadedCount) kep)."
            uploadProgress = 1
            uploadingAlbumID = nil
        } catch {
            uploadError = error.localizedDescription
            uploadStatus = nil
            uploadingAlbumID = nil
        }
    }

    // MARK: -

    private func persist() { store.save(albums) }

    // MARK: - Drive album lista

    /// Beolvassa a Drive Fotok/{ev}/ mappastrukturat, es osszegyujti az albumokat.
    /// A mar lokalisan is letezo albumokat kiszuri (driveFolderID egyezes alapjan).
    func fetchDriveAlbums() async {
        guard drive.isSignedIn else {
            driveAlbums = []
            return
        }

        isFetchingDriveAlbums = true
        defer { isFetchingDriveAlbums = false }

        let fotokID = "1K4BSqP_zIobVG_npR7vsWznADLtkAe8i"
        var result: [DriveAlbum] = []

        do {
            // 1) Ev mappak listazasa
            let years = try await drive.listFolder(fotokID)

            // 2) Minden ev mappaban az album almappak
            for (yearName, yearFolderID) in years {
                let albumFolders = try await drive.listFolder(yearFolderID)
                for (albumName, albumFolderID) in albumFolders {
                    result.append(DriveAlbum(
                        id: albumFolderID,
                        name: albumName,
                        year: yearName
                    ))
                }
            }

            // Rendezés év + név szerint
            result.sort { ($0.year, $0.name) < ($1.year, $1.name) }
            driveAlbums = result
        } catch {
            // Csendben hiba - a lista marad ami volt
        }
    }

    /// Drive albumok amiknek NINCS helyi parjuk (csak a Drive-on leteznek).
    var remoteOnlyDriveAlbums: [DriveAlbum] {
        let localDriveIDs = Set(albums.compactMap { $0.driveFolderID })
        return driveAlbums.filter { !localDriveIDs.contains($0.id) }
    }

    private func formatProgress(uploaded: Int, total: Int, remainingBytes: Int64) -> String {
        let remaining = total - uploaded
        let mb = ByteCountFormatter.string(fromByteCount: remainingBytes, countStyle: .file)
        return "\(uploaded)/\(total) kep feltoltve — meg \(remaining) kep (\(mb)) hatra"
    }
}
