import SwiftUI

struct Sidebar: View {

    @Binding var selection: ContentView.Section?
    @EnvironmentObject var albumVM: AlbumViewModel
    @EnvironmentObject var uploadVM: UploadBatchViewModel
    @EnvironmentObject var cameraVM: CameraViewModel

    var body: some View {
        List(selection: $selection) {
            Section("Kamera") {
                Label("Összes fotó", systemImage: "camera")
                    .tag(ContentView.Section.camera)
            }

            Section {
                ForEach(albumVM.albums) { album in
                    HStack {
                        Label(album.name, systemImage: "rectangle.stack")
                        Spacer()
                        // Feltöltés ikon — ha már fent van, zöld pipa; ha épp tölt, spinner.
                        if albumVM.uploadingAlbumID == album.id {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Button {
                                Task {
                                    await albumVM.uploadAlbumToDrive(
                                        albumID: album.id,
                                        allPhotos: cameraVM.photos
                                    )
                                }
                            } label: {
                                Image(systemName: album.isOnDrive
                                      ? "checkmark.icloud.fill"
                                      : "icloud.and.arrow.up")
                                    .foregroundStyle(album.isOnDrive ? .green : .accentColor)
                                    .font(.caption)
                            }
                            .buttonStyle(.borderless)
                            .help(album.isOnDrive ? "Szinkronizálás a Drive-ra" : "Feltöltés a Drive-ra")
                        }
                    }
                    .tag(ContentView.Section.album(album.id))
                    .contextMenu {
                        Button("Törlés", role: .destructive) {
                            albumVM.deleteAlbum(album.id)
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Albumok")
                    Spacer()
                    Button {
                        albumVM.startCreatingAlbum()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Section {
                ForEach(uploadVM.batches) { batch in
                    Label(batch.name, systemImage: batch.isUploaded ? "icloud.fill" : "tray.and.arrow.up")
                        .tag(ContentView.Section.uploadBatch(batch.id))
                }
            } header: {
                HStack {
                    Text("Drive feltöltések")
                    Spacer()
                    Button {
                        uploadVM.startCreating()
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                }
            }
        }
        .listStyle(.sidebar)
        .sheet(isPresented: $albumVM.isCreatingAlbum) {
            newAlbumSheet
        }
        .sheet(isPresented: $uploadVM.isCreating) {
            newBatchSheet
        }
        // Drive upload státusz / hiba üzenetek
        .alert("Feltöltés hiba", isPresented: .constant(albumVM.uploadError != nil), actions: {
            Button("OK") { albumVM.uploadError = nil }
        }, message: {
            Text(albumVM.uploadError ?? "")
        })
        .onChange(of: albumVM.uploadStatus) { _, status in
            // Státusz üzenet 3 mp-ig látható, majd eltűnik.
            if status != nil {
                Task {
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    if albumVM.uploadingAlbumID == nil {
                        albumVM.uploadStatus = nil
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let status = albumVM.uploadStatus {
                Text(status)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.thinMaterial)
            }
        }
    }

    // MARK: - Sheets

    private var newAlbumSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Új album").font(.headline)
            TextField("Album neve", text: $albumVM.newAlbumName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            if let error = albumVM.createError {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .font(.caption)
            }
            HStack {
                Spacer()
                Button("Mégse") {
                    albumVM.isCreatingAlbum = false
                    albumVM.createError = nil
                }
                Button("Létrehoz") { albumVM.confirmCreateAlbum() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }

    private var newBatchSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Új Drive feltöltés").font(.headline)
            Text("Adj egy nevet a mappának. Ez lesz a cél mappa a Google Drive-on is.")
                .font(.caption)
                .foregroundStyle(.secondary)
            TextField("Mappa neve", text: $uploadVM.newBatchName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 280)
            HStack {
                Spacer()
                Button("Mégse") { uploadVM.isCreating = false }
                Button("Létrehoz") {
                    try? uploadVM.confirmCreate()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
    }
}
