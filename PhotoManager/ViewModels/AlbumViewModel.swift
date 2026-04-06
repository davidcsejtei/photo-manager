import Foundation

@MainActor
final class AlbumViewModel: ObservableObject {

    @Published private(set) var albums: [Album] = []
    @Published var selectedAlbumID: UUID?
    @Published var isCreatingAlbum: Bool = false
    @Published var newAlbumName: String = ""

    private let store = AlbumStore()

    init() {
        self.albums = store.load()
    }

    // MARK: - CRUD

    func startCreatingAlbum() {
        newAlbumName = ""
        isCreatingAlbum = true
    }

    func confirmCreateAlbum() {
        let name = newAlbumName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let album = Album(name: name)
        albums.append(album)
        persist()
        selectedAlbumID = album.id
        isCreatingAlbum = false
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

    // MARK: -

    private func persist() { store.save(albums) }
}
