import Foundation

@MainActor
final class AlbumViewModel: ObservableObject {

    @Published private(set) var albums: [Album] = []
    @Published var selectedAlbumID: UUID?
    @Published var isCreatingAlbum: Bool = false
    @Published var newAlbumName: String = ""
    @Published var createError: String?

    // Upload/sync state
    @Published var uploadingAlbumID: UUID?
    @Published var uploadStatus: String?
    @Published var uploadError: String?
    @Published var uploadProgress: Double = 0
    @Published var uploadedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var remainingBytes: Int64 = 0

    // Download state
    @Published var downloadingDriveAlbumID: String?
    @Published var downloadStatus: String?
    @Published var downloadError: String?
    @Published var downloadProgress: Double = 0

    // Drive album lista
    @Published private(set) var driveAlbums: [DriveAlbum] = []
    @Published var isFetchingDriveAlbums: Bool = false

    private let store = AlbumStore()
    private let drive = GoogleDriveService.shared
    private static let fotokRootID = "1K4BSqP_zIobVG_npR7vsWznADLtkAe8i"

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

    /// Kamera foto hozzaadasa syncable albumhoz — masolja a fajlt a lokal mappaba.
    func addCameraPhoto(_ photo: Photo, to albumID: UUID) {
        guard let idx = albums.firstIndex(where: { $0.id == albumID }) else { return }
        guard let sourceURL = photo.localURL else { return }

        let album = albums[idx]

        if album.isSyncable {
            // Masolas a syncable album lokal konyvtaraba
            let dir = album.localPhotosDir
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent(sourceURL.lastPathComponent)
            if !FileManager.default.fileExists(atPath: dest.path) {
                try? FileManager.default.copyItem(at: sourceURL, to: dest)
            }
            // A photo ID a fajlnev (igy konzisztens a loadLocalPhotos-szal)
            let localID = sourceURL.lastPathComponent
            if !albums[idx].photoIDs.contains(localID) {
                albums[idx].photoIDs.append(localID)
            }
        } else {
            // Sima album: a camera photo.id-t hasznaljuk
            if !albums[idx].photoIDs.contains(photo.id) {
                albums[idx].photoIDs.append(photo.id)
            }
        }
        persist()
    }

    func removePhotos(_ photoIDs: [String], from albumID: UUID) {
        guard let idx = albums.firstIndex(where: { $0.id == albumID }) else { return }
        let toRemove = Set(photoIDs)
        albums[idx].photoIDs.removeAll { toRemove.contains($0) }
        persist()
    }

    // MARK: - Load local photos for Drive-downloaded albums

    /// Drive-rol letoltott album kepeit betolti a lokal konyvtarbol.
    func loadLocalPhotos(for album: Album) -> [Photo] {
        let dir = album.localPhotosDir
        let fm = FileManager.default
        guard fm.fileExists(atPath: dir.path) else { return [] }

        let keys: [URLResourceKey] = [.fileSizeKey, .contentModificationDateKey, .creationDateKey]
        let items = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []

        return items
            .filter { album.photoIDs.contains($0.lastPathComponent) }
            .map { url in
                let rv = try? url.resourceValues(forKeys: Set(keys))
                return Photo(
                    id: url.lastPathComponent,
                    fileName: url.lastPathComponent,
                    fileSize: Int64(rv?.fileSize ?? 0),
                    captureDate: rv?.contentModificationDate ?? rv?.creationDate,
                    thumbnailURL: url,
                    isDownloaded: true,
                    localURL: url,
                    deviceFileRef: nil
                )
            }
            .sorted { ($0.fileName) < ($1.fileName) }
    }

    // MARK: - Upload / Sync to Drive

    /// Egyseges belepesi pont: ha az album syncable (Drive-rol letoltott), bidirekcionalisan
    /// szinkronizal; ha nem, egyiranyuan feltolt.
    func uploadAlbumToDrive(albumID: UUID, allPhotos: [Photo]) async {
        guard let album = albums.first(where: { $0.id == albumID }) else { return }
        guard drive.isSignedIn else {
            uploadError = "Eloszor csatlakozz a Google Drive-hoz a Beallitasokban."
            return
        }
        if album.isSyncable {
            await syncAlbumToDrive(albumID: albumID)
        } else {
            await uploadOnlyToDrive(albumID: albumID, allPhotos: allPhotos)
        }
    }

    /// Egyiranyu feltoltes (uj album, meg nincs Drive-on).
    private func uploadOnlyToDrive(albumID: UUID, allPhotos: [Photo]) async {
        guard let album = albums.first(where: { $0.id == albumID }) else { return }

        uploadingAlbumID = albumID
        uploadStatus = "Elofelkeszites..."
        uploadError = nil
        uploadProgress = 0
        uploadedCount = 0
        totalCount = 0
        remainingBytes = 0

        do {
            let year = String(Calendar.current.component(.year, from: album.createdAt))
            let yearID = try await drive.findOrCreateFolder(named: year, parentID: Self.fotokRootID)
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
                updateAlbumDriveState(albumID, folderID: albumFolderID)
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
                uploadStatus = formatProgress(uploaded: uploadedCount, total: totalCount, remainingBytes: remainingBytes)
            }

            updateAlbumDriveState(albumID, folderID: albumFolderID)
            uploadStatus = "\"\(album.name)\" feltoltve (\(uploadedCount) kep)."
            uploadProgress = 1
            uploadingAlbumID = nil
        } catch {
            uploadError = error.localizedDescription
            uploadStatus = nil
            uploadingAlbumID = nil
        }
    }

    /// Bidirekcionalas szinkron — atnevezes + uj kepek feltoltese + torolt kepek eltavolitasa.
    private func syncAlbumToDrive(albumID: UUID) async {
        guard var album = albums.first(where: { $0.id == albumID }),
              let folderID = album.driveFolderID,
              var fileIndex = album.driveFileIndex
        else { return }

        uploadingAlbumID = albumID
        uploadStatus = "Szinkronizalas..."
        uploadError = nil
        uploadProgress = 0
        uploadedCount = 0

        do {
            // 1) Atnevezes ha a nev valtozott
            if let driveAlbumName = album.driveAlbumName, album.name != driveAlbumName {
                uploadStatus = "Mappa atnevezese..."
                try await drive.renameFile(driveFileID: folderID, newName: album.name)
                album.driveAlbumName = album.name
            }

            let localIDs = Set(album.photoIDs)
            let indexedIDs = Set(fileIndex.keys)

            // 2) Uj kepek feltoltese (lokalban van, Drive-on nincs)
            let toUpload = localIDs.subtracting(indexedIDs)
            // 3) Torolt kepek (Drive-on van, lokalban nincs)
            let toDelete = indexedIDs.subtracting(localIDs)

            totalCount = toUpload.count + toDelete.count
            var done = 0

            // Feltoltes
            if !toUpload.isEmpty {
                let dir = album.localPhotosDir
                for photoID in toUpload {
                    let url = dir.appendingPathComponent(photoID)
                    guard FileManager.default.fileExists(atPath: url.path) else { continue }
                    let driveFileID = try await drive.uploadFile(at: url, toFolder: folderID)
                    fileIndex[photoID] = driveFileID
                    done += 1
                    uploadProgress = totalCount > 0 ? Double(done) / Double(totalCount) : 1
                    uploadStatus = "Feltoltes: \(done)/\(totalCount)..."
                }
            }

            // Torles
            if !toDelete.isEmpty {
                for photoID in toDelete {
                    if let driveFileID = fileIndex[photoID] {
                        try await drive.deleteFile(driveFileID: driveFileID)
                    }
                    fileIndex.removeValue(forKey: photoID)
                    done += 1
                    uploadProgress = totalCount > 0 ? Double(done) / Double(totalCount) : 1
                    uploadStatus = "Torles: \(done)/\(totalCount)..."
                }
            }

            // Frissites
            album.driveFileIndex = fileIndex
            album.driveAlbumName = album.name
            if let idx = albums.firstIndex(where: { $0.id == albumID }) {
                albums[idx] = album
            }
            persist()

            let summary = [
                toUpload.isEmpty ? nil : "\(toUpload.count) feltoltve",
                toDelete.isEmpty ? nil : "\(toDelete.count) torolve",
                album.name != (albums.first(where: { $0.id == albumID })?.driveAlbumName ?? album.name) ? "atnevezve" : nil
            ].compactMap { $0 }
            uploadStatus = summary.isEmpty ? "Minden szinkronban." : "Szinkronizalva: \(summary.joined(separator: ", "))."
            uploadProgress = 1
            uploadingAlbumID = nil
        } catch {
            uploadError = error.localizedDescription
            uploadStatus = nil
            uploadingAlbumID = nil
        }
    }

    private func updateAlbumDriveState(_ albumID: UUID, folderID: String) {
        if let idx = albums.firstIndex(where: { $0.id == albumID }) {
            albums[idx].driveFolderID = folderID
            persist()
        }
    }

    // MARK: - Download Drive album to local

    func downloadDriveAlbumToLocal(driveAlbum: DriveAlbum) async {
        guard drive.isSignedIn else {
            downloadError = "Eloszor csatlakozz a Google Drive-hoz a Beallitasokban."
            return
        }

        downloadingDriveAlbumID = driveAlbum.id
        downloadStatus = "Fajlok listazasa..."
        downloadError = nil
        downloadProgress = 0

        do {
            let files = try await drive.listFolderDetailed(driveAlbum.id)

            let album = Album(
                name: driveAlbum.name,
                createdAt: Date(),
                driveFolderID: driveAlbum.id,
                driveFileIndex: [:],
                driveYear: driveAlbum.year,
                driveAlbumName: driveAlbum.name
            )
            let dir = album.localPhotosDir
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            var photoIDs: [String] = []
            var fileIndex: [String: String] = [:]
            let total = files.count

            for (i, file) in files.enumerated() {
                let localName = file.name
                let dest = dir.appendingPathComponent(localName)

                downloadStatus = "\(i + 1)/\(total): \(file.name)"
                downloadProgress = Double(i) / Double(max(total, 1))

                if !FileManager.default.fileExists(atPath: dest.path) {
                    try await drive.downloadFileContent(fileID: file.id, to: dest)
                }

                photoIDs.append(localName)
                fileIndex[localName] = file.id
            }

            var finalAlbum = album
            finalAlbum.photoIDs = photoIDs
            finalAlbum.driveFileIndex = fileIndex

            albums.append(finalAlbum)
            persist()
            selectedAlbumID = finalAlbum.id

            downloadStatus = "\"\(driveAlbum.name)\" letoltve (\(total) kep)."
            downloadProgress = 1
            downloadingDriveAlbumID = nil

            // Drive lista frissitese (az album most mar lokal is)
            await fetchDriveAlbums()
        } catch {
            downloadError = error.localizedDescription
            downloadStatus = nil
            downloadingDriveAlbumID = nil
        }
    }

    // MARK: - Drive album lista

    func fetchDriveAlbums() async {
        guard drive.isSignedIn else {
            driveAlbums = []
            return
        }
        isFetchingDriveAlbums = true
        defer { isFetchingDriveAlbums = false }

        var result: [DriveAlbum] = []
        do {
            let years = try await drive.listFolder(Self.fotokRootID)
            for (yearName, yearFolderID) in years {
                let albumFolders = try await drive.listFolder(yearFolderID)
                for (albumName, albumFolderID) in albumFolders {
                    result.append(DriveAlbum(id: albumFolderID, name: albumName, year: yearName))
                }
            }
            result.sort { ($0.year, $0.name) < ($1.year, $1.name) }
            driveAlbums = result
        } catch {}
    }

    var remoteOnlyDriveAlbums: [DriveAlbum] {
        let localDriveIDs = Set(albums.compactMap { $0.driveFolderID })
        return driveAlbums.filter { !localDriveIDs.contains($0.id) }
    }

    // MARK: -

    private func persist() { store.save(albums) }

    private func formatProgress(uploaded: Int, total: Int, remainingBytes: Int64) -> String {
        let remaining = total - uploaded
        let mb = ByteCountFormatter.string(fromByteCount: remainingBytes, countStyle: .file)
        return "\(uploaded)/\(total) kep feltoltve -- meg \(remaining) kep (\(mb)) hatra"
    }
}
