import Foundation

struct Album: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var photoIDs: [String]
    var createdAt: Date
    var driveFolderID: String?

    /// Sync tracking: local photo ID -> Drive file ID.
    /// Ha nem nil, az album Drive-rol lett letoltve es szinkronizalhato.
    /// - photoIDs-ben van, de driveFileIndex-ben nincs = uj, feltoltendo
    /// - driveFileIndex-ben van, de photoIDs-ben nincs = torolt, Drive-rol torlendo
    var driveFileIndex: [String: String]?

    /// Az ev mappa neve a Drive-on (pl. "2026").
    var driveYear: String?

    /// Az album neve a Drive-on az utolso szinkron idejen.
    /// Ha name != driveAlbumName, atnevezes szukseges.
    var driveAlbumName: String?

    init(
        id: UUID = UUID(),
        name: String,
        photoIDs: [String] = [],
        createdAt: Date = Date(),
        driveFolderID: String? = nil,
        driveFileIndex: [String: String]? = nil,
        driveYear: String? = nil,
        driveAlbumName: String? = nil
    ) {
        self.id = id
        self.name = name
        self.photoIDs = photoIDs
        self.createdAt = createdAt
        self.driveFolderID = driveFolderID
        self.driveFileIndex = driveFileIndex
        self.driveYear = driveYear
        self.driveAlbumName = driveAlbumName
    }

    var isOnDrive: Bool { driveFolderID != nil }

    /// True ha ez az album Drive-rol lett letoltve (van szinkron index).
    var isSyncable: Bool { driveFileIndex != nil }

    /// Lokal konyvtar a Drive-rol letoltott kepeknek.
    var localPhotosDir: URL {
        let fm = FileManager.default
        let base = (try? fm.url(for: .picturesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        return base.appendingPathComponent("PhotoManager/DriveAlbums/\(id.uuidString)", isDirectory: true)
    }
}
