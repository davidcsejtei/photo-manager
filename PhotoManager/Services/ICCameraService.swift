import Foundation
#if canImport(ImageCaptureCore)
import ImageCaptureCore
#endif

/// Valódi ImageCaptureCore-alapú implementáció a `CameraServicing` protokollhoz.
///
/// **Állapot:** csontváz. A Sony ZV-E10 macOS-en PTP eszközként jelenik meg,
/// amit az Apple `ImageCaptureCore` frameworkje tud kezelni (ugyanaz az API,
/// amit az "Image Capture" alkalmazás is használ). Az alábbi metódusokban
/// meg vannak jelölve a helyek, ahol a tényleges API-hívásokat be kell kötni.
///
/// Referenciák:
///   - `ICDeviceBrowser` — eszközfelderítés
///   - `ICCameraDevice.mediaFiles` — fotók listája
///   - `ICCameraDevice.requestDownloadFile(...)` — letöltés
///   - `ICCameraDevice.requestDeleteFiles(...)` — törlés
///
/// A pontos signature-ök macOS verziónként kissé eltérnek (pl. macOS 13+
/// async variánsok). Érdemes az Xcode autocomplete-ből dolgozni, mert a
/// framework szimbólumai gyorsan jelzik a jelenlegi helyes formát.
@MainActor
final class ICCameraService: NSObject, CameraServicing {

    weak var delegate: CameraServiceDelegate?

    #if canImport(ImageCaptureCore)
    private let browser = ICDeviceBrowser()
    private var connectedCamera: ICCameraDevice?
    private var fileIndex: [String: ICCameraFile] = [:]
    #endif

    // MARK: - Lifecycle

    func start() {
        #if canImport(ImageCaptureCore)
        browser.delegate = self
        // A pontos mask összerakása OptionSet-ekkel macOS verziónként eltér;
        // a legegyszerűbb csak kamerákra szűrni:
        browser.browsedDeviceTypeMask = .camera
        browser.start()
        #endif
    }

    func stop() {
        #if canImport(ImageCaptureCore)
        browser.stop()
        connectedCamera?.requestCloseSession()
        connectedCamera = nil
        #endif
    }

    func reloadMediaFiles() {
        #if canImport(ImageCaptureCore)
        guard let camera = connectedCamera else {
            delegate?.cameraService(self, didUpdatePhotos: [])
            return
        }
        let files = (camera.mediaFiles ?? []).compactMap { $0 as? ICCameraFile }
        fileIndex.removeAll(keepingCapacity: true)
        let photos: [Photo] = files.map { file in
            let id = Self.stableID(for: file)
            fileIndex[id] = file
            return Photo(
                id: id,
                fileName: file.name ?? "unknown",
                fileSize: Int64(file.fileSize),
                captureDate: file.creationDate,
                thumbnailURL: nil,
                isDownloaded: false,
                localURL: nil,
                deviceFileRef: nil
            )
        }
        delegate?.cameraService(self, didUpdatePhotos: photos)
        #endif
    }

    // MARK: - Download / Delete

    func download(photoIDs: [String], to destination: URL) async throws -> [URL] {
        // TODO: `camera.requestDownloadFile(_:options:downloadDelegate:...)`
        // a macOS verziónak megfelelő formában. Az options dict kulcsai
        // `ICDownloadOption` típusúak (pl. `.downloadsDirectoryURL`, `.saveAsFilename`).
        throw CameraError.notImplemented
    }

    func delete(photoIDs: [String]) async throws {
        // TODO: `camera.requestDeleteFiles(_:)` — a return érték egy
        // `[ICDeleteError: ICCameraItem]` map a sikertelenségekről.
        throw CameraError.notImplemented
    }

    // MARK: - Helpers

    #if canImport(ImageCaptureCore)
    /// Stabil azonosító egy device-fájlhoz. Az `ICCameraFile` referencia nem
    /// marad meg újracsatlakozás után, ezért névből + méretből + dátumból
    /// generálunk kulcsot, ami a `Photo.id`-val is egyezik az app-on belül.
    static func stableID(for file: ICCameraFile) -> String {
        let name = file.name ?? "?"
        let size = file.fileSize
        let date = file.creationDate?.timeIntervalSince1970 ?? 0
        return "\(name)|\(size)|\(Int(date))"
    }
    #endif
}

#if canImport(ImageCaptureCore)
// MARK: - ICDeviceBrowserDelegate

extension ICCameraService: ICDeviceBrowserDelegate {
    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didAdd device: ICDevice, moreComing: Bool) {
        Task { @MainActor in
            guard let camera = device as? ICCameraDevice else { return }
            camera.delegate = self
            camera.requestOpenSession()
            self.connectedCamera = camera
            self.delegate?.cameraService(self, didConnect: camera.name ?? "Kamera")
        }
    }

    nonisolated func deviceBrowser(_ browser: ICDeviceBrowser, didRemove device: ICDevice, moreGoing: Bool) {
        Task { @MainActor in
            if device === self.connectedCamera {
                self.connectedCamera = nil
                self.delegate?.cameraServiceDidDisconnect(self)
            }
        }
    }
}

// MARK: - ICDeviceDelegate (minimális stub)

extension ICCameraService: ICDeviceDelegate {
    nonisolated func didRemove(_ device: ICDevice) {}
    nonisolated func device(_ device: ICDevice, didOpenSessionWithError error: Error?) {
        Task { @MainActor in self.reloadMediaFiles() }
    }
    nonisolated func device(_ device: ICDevice, didCloseSessionWithError error: Error?) {}
    nonisolated func deviceDidBecomeReady(_ device: ICDevice) {
        Task { @MainActor in self.reloadMediaFiles() }
    }
    nonisolated func device(_ device: ICDevice, didEncounterError error: Error?) {}
}
#endif
