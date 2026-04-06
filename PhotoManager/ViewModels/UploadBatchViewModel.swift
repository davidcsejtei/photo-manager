import Foundation

/// A "kijelölt képeket egy ideiglenes mappába gyűjtöm és gombnyomásra Drive-ra"
/// flow-t vezérlő VM. Felelős azért is, hogy egy már feltöltött batch-et
/// újra szinkronizálni tudjon a Drive oldali mappával.
@MainActor
final class UploadBatchViewModel: ObservableObject {

    @Published private(set) var batches: [UploadBatch] = []
    @Published var selectedBatchID: UUID?
    @Published var isCreating: Bool = false
    @Published var newBatchName: String = ""
    @Published var statusMessage: String?

    private let store = UploadBatchStore()
    private let drive = GoogleDriveService.shared

    init() { self.batches = store.load() }

    // MARK: - Batch létrehozás

    func startCreating() {
        newBatchName = ""
        isCreating = true
    }

    func confirmCreate() throws {
        let name = newBatchName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let folder = try store.createStagingFolder(for: name)
        let batch = UploadBatch(name: name, stagingFolder: folder)
        batches.append(batch)
        selectedBatchID = batch.id
        isCreating = false
        store.save(batches)
    }

    // MARK: - Képek hozzáadása / eltávolítása

    /// A megadott képek `localURL`-jét (ha letöltött) bemásolja a batch staging mappájába.
    /// Ha a kép még nincs letöltve, előbb a hívó oldalnak kell letöltenie.
    func add(photoIDs: [String], localURLs: [URL], to batchID: UUID) throws {
        guard let idx = batches.firstIndex(where: { $0.id == batchID }) else { return }
        var batch = batches[idx]

        for url in localURLs {
            _ = try DownloadService.copyFile(from: url, into: batch.stagingFolder)
        }
        var existing = Set(batch.photoIDs)
        for id in photoIDs where !existing.contains(id) {
            batch.photoIDs.append(id)
            existing.insert(id)
        }
        batches[idx] = batch
        store.save(batches)
    }

    func remove(photoIDs: [String], from batchID: UUID) {
        guard let idx = batches.firstIndex(where: { $0.id == batchID }) else { return }
        let toRemove = Set(photoIDs)
        batches[idx].photoIDs.removeAll { toRemove.contains($0) }
        store.save(batches)
    }

    // MARK: - Drive feltöltés / sync

    /// Egy batch teljes feltöltése a Drive-ra. Ha már létezik `driveFolderID`,
    /// akkor szinkronizál: a staging mappa tartalmát képként elküldi, a Drive
    /// oldalon a batch `photoIDs` listájából már hiányzókat törli.
    func uploadOrSync(batchID: UUID) async {
        guard let idx = batches.firstIndex(where: { $0.id == batchID }) else { return }
        var batch = batches[idx]

        do {
            if !drive.isSignedIn { try await drive.signIn() }

            // 1) Folder létrehozás, ha még nincs.
            if batch.driveFolderID == nil {
                batch.driveFolderID = try await drive.createFolder(named: batch.name)
            }
            guard let folderID = batch.driveFolderID else { return }

            // 2) Staging mappa tartalma → Drive
            let fm = FileManager.default
            let files = (try? fm.contentsOfDirectory(at: batch.stagingFolder, includingPropertiesForKeys: nil)) ?? []
            let remote = try await drive.listFolder(folderID) // name → fileID

            // Ami helyi staging-ben van, de Drive-on nincs → feltöltés
            for file in files where remote[file.lastPathComponent] == nil {
                try await drive.uploadFile(at: file, toFolder: folderID)
            }

            // Ami Drive-on van, de helyi staging-ből kikerült → törlés
            let stagingNames = Set(files.map { $0.lastPathComponent })
            for (remoteName, remoteID) in remote where !stagingNames.contains(remoteName) {
                try await drive.deleteFile(driveFileID: remoteID)
            }

            batch.lastSyncedAt = Date()
            batches[idx] = batch
            store.save(batches)
            statusMessage = "\"\(batch.name)\" szinkronizálva."
        } catch {
            statusMessage = "Hiba: \(error.localizedDescription)"
        }
    }
}
