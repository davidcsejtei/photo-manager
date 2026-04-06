import Foundation

/// Fejlesztés alatt használt mock. Ugyanazt a `CameraServicing` protokollt
/// implementálja, mint az `ICCameraService`, így a ViewModel kód változatlan.
@MainActor
final class MockCameraService: CameraServicing {

    weak var delegate: CameraServiceDelegate?
    private var photos: [Photo] = (1...48).map { Photo.mock($0) }

    func start() {
        // Szimuláljuk, hogy 0.3s múlva "csatlakozik" a kamera.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 300_000_000)
            delegate?.cameraService(self, didConnect: "Sony ZV-E10 (Mock)")
            delegate?.cameraService(self, didUpdatePhotos: photos)
        }
    }

    func stop() {
        delegate?.cameraServiceDidDisconnect(self)
    }

    func reloadMediaFiles() {
        delegate?.cameraService(self, didUpdatePhotos: photos)
    }

    func download(photoIDs: [String], to destination: URL) async throws -> [URL] {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        var urls: [URL] = []
        for id in photoIDs {
            guard let photo = photos.first(where: { $0.id == id }) else { continue }
            let url = destination.appendingPathComponent(photo.fileName)
            // Üres placeholder fájl, hogy a letöltés "látszódjon".
            if !FileManager.default.fileExists(atPath: url.path) {
                FileManager.default.createFile(atPath: url.path, contents: Data())
            }
            urls.append(url)
        }
        return urls
    }

    func delete(photoIDs: [String]) async throws {
        photos.removeAll { photoIDs.contains($0.id) }
        delegate?.cameraService(self, didUpdatePhotos: photos)
    }
}
