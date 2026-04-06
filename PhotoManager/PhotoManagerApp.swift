import SwiftUI

@main
struct PhotoManagerApp: App {
    @StateObject private var cameraVM = CameraViewModel()
    @StateObject private var albumVM = AlbumViewModel()
    @StateObject private var uploadVM = UploadBatchViewModel()
    @StateObject private var drive = GoogleDriveService.shared

    var body: some Scene {
        WindowGroup("Photo Manager") {
            ContentView()
                .environmentObject(cameraVM)
                .environmentObject(albumVM)
                .environmentObject(uploadVM)
                .environmentObject(drive)
                .frame(minWidth: 1400, minHeight: 800)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button("Új album…") { albumVM.startCreatingAlbum() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
        }

        Settings {
            SettingsView()
                .environmentObject(drive)
        }
    }
}
