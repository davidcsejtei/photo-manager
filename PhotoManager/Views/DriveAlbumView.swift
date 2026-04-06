import SwiftUI

/// Egy csak Drive-on letezo album tartalmat mutatja (fajlnevek listaja).
/// Mivel a kepek nincsenek lokalisan, thumbnail nincs — csak a fajl lista.
struct DriveAlbumView: View {
    let folderID: String
    @EnvironmentObject var albumVM: AlbumViewModel

    @State private var files: [String: String] = [:]  // name -> id
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Betoltes...")
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Hiba",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error)
                )
            } else if files.isEmpty {
                ContentUnavailableView(
                    "Ures mappa",
                    systemImage: "folder",
                    description: Text("Ez a Drive mappa ures.")
                )
            } else {
                List {
                    ForEach(files.keys.sorted(), id: \.self) { name in
                        Label(name, systemImage: iconForFile(name))
                    }
                }
            }
        }
        .navigationTitle(albumName)
        .task(id: folderID) { await load() }
    }

    private var albumName: String {
        albumVM.driveAlbums.first(where: { $0.id == folderID })?.name ?? "Drive album"
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            files = try await GoogleDriveService.shared.listFolder(folderID)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func iconForFile(_ name: String) -> String {
        let ext = (name as NSString).pathExtension.lowercased()
        switch ext {
        case "jpg", "jpeg", "heic", "heif", "png", "tiff", "tif":
            return "photo"
        case "arw", "raf", "nef", "cr2", "cr3", "dng":
            return "camera.filters"
        case "mp4", "mov":
            return "film"
        default:
            return "doc"
        }
    }
}
