import Foundation

/// Absztrakció a kamera fölött. A UI réteg ezt a protokollt használja,
/// így tudunk váltogatni mock és valódi (ImageCaptureCore alapú) implementáció között.
@MainActor
protocol CameraServicing: AnyObject {
    var delegate: CameraServiceDelegate? { get set }

    func start()
    func stop()
    func reloadMediaFiles()

    func download(photoIDs: [String], to destination: URL) async throws -> [URL]
    func delete(photoIDs: [String]) async throws
}

@MainActor
protocol CameraServiceDelegate: AnyObject {
    func cameraService(_ service: CameraServicing, didConnect cameraName: String)
    func cameraServiceDidDisconnect(_ service: CameraServicing)
    func cameraService(_ service: CameraServicing, didUpdatePhotos photos: [Photo])
}

enum CameraError: LocalizedError {
    case notConnected
    case downloadFailed
    case notImplemented

    var errorDescription: String? {
        switch self {
        case .notConnected: return "Nincs csatlakoztatott kamera."
        case .downloadFailed: return "A letöltés nem sikerült."
        case .notImplemented: return "Ez a funkció még nincs implementálva (ImageCaptureCore bekötés szükséges)."
        }
    }
}
