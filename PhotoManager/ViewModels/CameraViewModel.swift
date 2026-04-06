import Foundation
import Combine

/// A kamera állapotát + fotólistát publikáló ViewModel. A view-k ezt figyelik.
@MainActor
final class CameraViewModel: ObservableObject {

    enum ConnectionState: Equatable {
        case disconnected
        case connecting
        case connected(String)  // camera name
    }

    @Published private(set) var connection: ConnectionState = .disconnected
    @Published private(set) var photos: [Photo] = []
    @Published var selectedPhotoIDs: Set<String> = []
    @Published var errorMessage: String?

    private let service: CameraServicing

    init() {
        // Valódi kamera: USB-n keresztül mint Mass Storage kötet.
        // (Mock-hoz: `MockCameraService()`. PTP/ImageCaptureCore-hoz: `ICCameraService()`.)
        self.service = VolumeCameraService()
        self.service.delegate = self
    }

    // MARK: - Actions

    func start() {
        connection = .connecting
        service.start()
    }

    func stop() {
        service.stop()
    }

    func refresh() {
        service.reloadMediaFiles()
    }

    func toggleSelection(_ id: String) {
        if selectedPhotoIDs.contains(id) {
            selectedPhotoIDs.remove(id)
        } else {
            selectedPhotoIDs.insert(id)
        }
    }

    func selectAll() {
        selectedPhotoIDs = Set(photos.map { $0.id })
    }

    func clearSelection() {
        selectedPhotoIDs.removeAll()
    }

    func downloadSelected() async {
        guard !selectedPhotoIDs.isEmpty else { return }
        let dest = DownloadService.defaultDestination()
        do {
            _ = try await service.download(photoIDs: Array(selectedPhotoIDs), to: dest)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deleteSelected() async {
        guard !selectedPhotoIDs.isEmpty else { return }
        let ids = Array(selectedPhotoIDs)
        do {
            try await service.delete(photoIDs: ids)
            selectedPhotoIDs.removeAll()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

// MARK: - CameraServiceDelegate

extension CameraViewModel: CameraServiceDelegate {
    func cameraService(_ service: CameraServicing, didConnect cameraName: String) {
        connection = .connected(cameraName)
    }
    func cameraServiceDidDisconnect(_ service: CameraServicing) {
        connection = .disconnected
        photos = []
    }
    func cameraService(_ service: CameraServicing, didUpdatePhotos photos: [Photo]) {
        self.photos = photos
        // A kijelölésből kiszedjük azokat, amik már nincsenek a listában.
        let validIDs = Set(photos.map { $0.id })
        selectedPhotoIDs.formIntersection(validIDs)
    }
}
