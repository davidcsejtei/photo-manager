import Foundation

/// Egy album, ami a Google Drive-on letezik a Fotok/{ev}/{nev} strukturaban,
/// de nem feltetlen van meg helyi Album parosa.
struct DriveAlbum: Identifiable, Hashable {
    let id: String        // Drive folder ID
    let name: String
    let year: String
}
