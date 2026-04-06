import SwiftUI

struct UploadBatchView: View {
    let batchID: UUID
    @EnvironmentObject var uploadVM: UploadBatchViewModel
    @EnvironmentObject var cameraVM: CameraViewModel

    var body: some View {
        if let batch = uploadVM.batches.first(where: { $0.id == batchID }) {
            VStack(alignment: .leading, spacing: 12) {
                header(for: batch)
                Divider()
                photoList(for: batch)
                Spacer()
                footer(for: batch)
            }
            .padding()
            .navigationTitle("Feltöltés — \(batch.name)")
        } else {
            ContentUnavailableView("Mappa nem található", systemImage: "questionmark.folder")
        }
    }

    private func header(for batch: UploadBatch) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: batch.isUploaded ? "icloud.fill" : "tray.and.arrow.up")
                Text(batch.name).font(.title2.weight(.semibold))
                Spacer()
                Text("\(batch.photoIDs.count) kép").foregroundStyle(.secondary)
            }
            Text("Staging: \(batch.stagingFolder.path)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            if let synced = batch.lastSyncedAt {
                Text("Utoljára szinkronizálva: \(synced.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func photoList(for batch: UploadBatch) -> some View {
        let photos = cameraVM.photos.filter { batch.photoIDs.contains($0.id) }
        if photos.isEmpty {
            ContentUnavailableView(
                "Még nincsenek képek",
                systemImage: "photo",
                description: Text("Nyisd meg a \"Kamera\" nézetet, jelölj ki képeket, és a jobb oldali panelről add hozzá ehhez a mappához.")
            )
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 120))], spacing: 8) {
                    ForEach(photos) { photo in
                        VStack(spacing: 4) {
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.gray.opacity(0.2))
                                .aspectRatio(3/2, contentMode: .fit)
                                .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                            Text(photo.fileName).font(.caption2).lineLimit(1)
                        }
                        .contextMenu {
                            Button("Eltávolítás a mappából", role: .destructive) {
                                uploadVM.remove(photoIDs: [photo.id], from: batch.id)
                            }
                        }
                    }
                }
            }
        }
    }

    private func footer(for batch: UploadBatch) -> some View {
        HStack {
            if let status = uploadVM.statusMessage {
                Text(status).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                Task { await uploadVM.uploadOrSync(batchID: batch.id) }
            } label: {
                Label(batch.isUploaded ? "Szinkronizálás" : "Feltöltés Drive-ra",
                      systemImage: batch.isUploaded ? "arrow.triangle.2.circlepath" : "icloud.and.arrow.up")
            }
            .keyboardShortcut("u", modifiers: .command)
            .buttonStyle(.borderedProminent)
        }
    }
}
