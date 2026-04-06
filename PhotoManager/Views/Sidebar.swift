import SwiftUI

struct Sidebar: View {

    @Binding var selection: ContentView.Section?
    @EnvironmentObject var albumVM: AlbumViewModel
    @EnvironmentObject var uploadVM: UploadBatchViewModel

    var body: some View {
        List(selection: $selection) {
            Section("Kamera") {
                Label("Összes fotó", systemImage: "camera")
                    .tag(ContentView.Section.camera)
            }

            Section {
                ForEach(albumVM.albums) { album in
                    Label(album.name, systemImage: "rectangle.stack")
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
    }

    private var newAlbumSheet: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Új album").font(.headline)
            TextField("Album neve", text: $albumVM.newAlbumName)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
            HStack {
                Spacer()
                Button("Mégse") { albumVM.isCreatingAlbum = false }
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
