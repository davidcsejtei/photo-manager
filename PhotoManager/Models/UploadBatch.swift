import Foundation

/// Egy "Drive-ra feltöltendő" válogatás. A felhasználó kiválaszt képeket,
/// ad nekik egy mappanevet, majd a teljes batchet feltölti a Google Drive-ra.
/// Ha már feltöltött batchhez újabb képeket ad / töröl, a `driveFolderID` alapján
/// szinkronizálhatjuk a Drive oldali mappával.
struct UploadBatch: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String                 // a felhasználó által adott mappanév
    var stagingFolder: URL           // ideiglenes mappa a Mac-en (a képek ide másolódnak)
    var photoIDs: [String]           // mely Photo.id-k tartoznak hozzá
    var driveFolderID: String?       // Google Drive mappa ID, ha már fel lett töltve
    var lastSyncedAt: Date?
    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        stagingFolder: URL,
        photoIDs: [String] = [],
        driveFolderID: String? = nil,
        lastSyncedAt: Date? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.stagingFolder = stagingFolder
        self.photoIDs = photoIDs
        self.driveFolderID = driveFolderID
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
    }

    var isUploaded: Bool { driveFolderID != nil }
    var needsSync: Bool {
        // Ha fel lett töltve, de azóta változott a tartalom, szinkronizálni kell.
        // Az egyszerű MVP-ben ezt a VM követi; itt csak a flag-et tesszük elérhetővé.
        false
    }
}
