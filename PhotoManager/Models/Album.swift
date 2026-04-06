import Foundation

/// Helyi album. A fotókat stabil `Photo.id`-val hivatkozza, hogy a kamerai és a
/// letöltött állapot között is azonos maradjon.
struct Album: Identifiable, Hashable, Codable {
    var id: UUID
    var name: String
    var photoIDs: [String]
    var createdAt: Date
    var driveFolderID: String?

    init(id: UUID = UUID(), name: String, photoIDs: [String] = [], createdAt: Date = Date(), driveFolderID: String? = nil) {
        self.id = id
        self.name = name
        self.photoIDs = photoIDs
        self.createdAt = createdAt
        self.driveFolderID = driveFolderID
    }

    var isOnDrive: Bool { driveFolderID != nil }
}
