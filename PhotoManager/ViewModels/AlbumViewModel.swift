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
        uploadStatus = "Feltoltes folyamatban..."
        uploadError = nil

        do {
            // 1) "Fotok" mappa keresese / letrehozasa a Drive gyokereben.
            let fotokID = try await drive.findOrCreateFolder(named: "Fotók", parentID: nil)

            // 2) Ev almappa (az album letrehozasi datuma alapjan).
            let year = String(Calendar.current.component(.year, from: album.createdAt))
            let yearID = try await drive.findOrCreateFolder(named: year, parentID: fotokID)

            // 3) Album almappa.
            let albumFolderID = try await drive.findOrCreateFolder(named: album.name, parentID: yearID)

            // 4) Feltoltes: csak ami meg nincs fent.
            let existing = try await drive.listFolder(albumFolderID)
            let photosToUpload = allPhotos.filter { album.photoIDs.contains($0.id) && $0.localURL != nil }
            var uploaded = 0
            for photo in photosToUpload {
                guard let url = photo.localURL else { continue }
                if existing[url.lastPathComponent] == nil {
                    try await drive.uploadFile(at: url, toFolder: albumFolderID)
                    uploaded += 1
                    uploadStatus = "Feltoltes: \(uploaded)/\(photosToUpload.count)..."
                }
            }

            // 5) Album frissites a drive folder ID-vel.
            if let idx = albums.firstIndex(where: { $0.id == albumID }) {
                albums[idx].driveFolderID = albumFolderID
                persist()
            }

            uploadStatus = "\"\(album.name)\" feltoltve (\(uploaded) uj kep)."
            uploadingAlbumID = nil
        } catch {
            uploadError = error.localizedDescription
            uploadStatus = nil
            uploadingAlbumID = nil
        }
    }

    // MARK: -

    private func persist() { store.save(albums) }
}
