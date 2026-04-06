import SwiftUI

/// Három-oszlopos NavigationSplitView:
/// - bal: sidebar (Kamera / Albumok / Drive-ra feltöltés)
/// - közép: fotólista (grid)
/// - jobb: részletek / akciók
struct ContentView: View {

    enum Section: Hashable {
        case camera
        case album(UUID)
        case uploadBatch(UUID)
    }

    @EnvironmentObject var cameraVM: CameraViewModel
    @EnvironmentObject var albumVM: AlbumViewModel
    @EnvironmentObject var uploadVM: UploadBatchViewModel

    @State private var selection: Section? = .camera

    var body: some View {
        NavigationSplitView {
            Sidebar(selection: $selection)
                .frame(minWidth: 220)
        } content: {
            centerPane
                .frame(minWidth: 420)
        } detail: {
            detailPane
                .frame(minWidth: 560, idealWidth: 720)
        }
        .task { cameraVM.start() }
        .toolbar { toolbarContent }
        .alert("Hiba", isPresented: .constant(cameraVM.errorMessage != nil), actions: {
            Button("OK") { cameraVM.errorMessage = nil }
        }, message: {
            Text(cameraVM.errorMessage ?? "")
        })
    }

    // MARK: - Panes

    @ViewBuilder
    private var centerPane: some View {
        switch selection {
        case .camera, .none:
            Group {
                if case .disconnected = cameraVM.connection {
                    ContentUnavailableView(
                        "Nincs csatlakoztatott kamera",
                        systemImage: "camera.badge.ellipsis",
                        description: Text("Csatlakoztasd a fényképezőt USB-n Mass Storage módban. Amint megjelenik meghajtóként, a képek automatikusan betöltődnek.")
                    )
                } else if cameraVM.photos.isEmpty {
                    ContentUnavailableView(
                        "Üres mappa",
                        systemImage: "tray",
                        description: Text("Az aktuális DCIM mappa üres, vagy még nem olvasható.")
                    )
                } else {
                    PhotoGridView(photos: cameraVM.photos,
                                  selection: $cameraVM.selectedPhotoIDs)
                }
            }
            .navigationTitle(connectionTitle)
        case .album(let id):
            if let album = albumVM.albums.first(where: { $0.id == id }) {
                let photos = cameraVM.photos.filter { album.photoIDs.contains($0.id) }
                PhotoGridView(photos: photos, selection: $cameraVM.selectedPhotoIDs)
                    .navigationTitle("Album — \(album.name)")
            } else {
                Text("Album nem található")
            }
        case .uploadBatch(let id):
            UploadBatchView(batchID: id)
        }
    }

    @ViewBuilder
    private var detailPane: some View {
        if let photo = firstSelectedPhoto {
            PhotoDetailView(photo: photo)
        } else {
            ContentUnavailableView(
                "Nincs kiválasztott fotó",
                systemImage: "photo.on.rectangle",
                description: Text("Jelölj ki egy képet a részletek megtekintéséhez.")
            )
        }
    }

    private var firstSelectedPhoto: Photo? {
        guard let id = cameraVM.selectedPhotoIDs.first else { return nil }
        return cameraVM.photos.first { $0.id == id }
    }

    private var connectionTitle: String {
        switch cameraVM.connection {
        case .disconnected: return "Kamera — nincs csatlakoztatva"
        case .connecting: return "Kamera — csatlakozás…"
        case .connected(let name): return name
        }
    }

    // MARK: - Delete (kontextus-érzékeny)

    /// Az "Albumban" vagy "Drive feltöltésben" levő kép törlése csak
    /// eltávolítás az adott gyűjteményből — a fájl a kamerán marad.
    /// Csak a "Kamera" nézetben jelent valódi fájltörlést.
    private func handleDelete() {
        let ids = Array(cameraVM.selectedPhotoIDs)
        guard !ids.isEmpty else { return }
        switch selection {
        case .album(let albumID):
            albumVM.removePhotos(ids, from: albumID)
            cameraVM.clearSelection()
        case .uploadBatch(let batchID):
            uploadVM.remove(photoIDs: ids, from: batchID)
            cameraVM.clearSelection()
        case .camera, .none:
            Task { await cameraVM.deleteSelected() }
        }
    }

    private var deleteLabel: (title: String, icon: String) {
        switch selection {
        case .album: return ("Eltávolítás az albumból", "minus.circle")
        case .uploadBatch: return ("Eltávolítás a mappából", "minus.circle")
        case .camera, .none: return ("Törlés a kameráról", "trash")
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button {
                Task { await cameraVM.downloadSelected() }
            } label: {
                Label("Letöltés", systemImage: "arrow.down.circle")
            }
            .disabled(cameraVM.selectedPhotoIDs.isEmpty)
        }
        ToolbarItem(placement: .primaryAction) {
            Button(role: .destructive) {
                handleDelete()
            } label: {
                Label(deleteLabel.title, systemImage: deleteLabel.icon)
            }
            .disabled(cameraVM.selectedPhotoIDs.isEmpty)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                cameraVM.refresh()
            } label: {
                Label("Frissítés", systemImage: "arrow.clockwise")
            }
        }
    }
}
