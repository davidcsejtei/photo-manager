import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct PhotoGridView: View {

    let photos: [Photo]
    @Binding var selection: Set<String>
    /// Photo ID-k amik meg nincsenek szinkronizalva a Drive-ra.
    var unsyncedIDs: Set<String> = []

    @FocusState private var gridFocused: Bool
    @State private var columnCount: Int = 1

    private let itemMinWidth: CGFloat = 140
    private let itemSpacing: CGFloat = 10
    private let gridPadding: CGFloat = 16

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: itemMinWidth, maximum: 180), spacing: itemSpacing)]
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, spacing: itemSpacing) {
                    ForEach(photos) { photo in
                        PhotoCell(photo: photo, isSelected: selection.contains(photo.id), isUnsynced: unsyncedIDs.contains(photo.id))
                            .id(photo.id)
                            .onTapGesture {
                                handleTap(on: photo)
                            }
                    }
                }
                .padding(gridPadding)
            }
            .background(
                // Oszlopszám mérése a tényleges szélesség alapján, hogy az
                // ↑/↓ nyilak pontosan egy sornyit lépjenek.
                GeometryReader { geo in
                    Color.clear
                        .onAppear { updateColumnCount(width: geo.size.width) }
                        .onChange(of: geo.size.width) { _, w in
                            updateColumnCount(width: w)
                        }
                }
            )
            .focusable()
            .focused($gridFocused)
            .focusEffectDisabled()
            .onAppear { gridFocused = true }
            .onKeyPress(.leftArrow) {
                move(by: -1, proxy: proxy); return .handled
            }
            .onKeyPress(.rightArrow) {
                move(by: 1, proxy: proxy); return .handled
            }
            .onKeyPress(.upArrow) {
                move(by: -columnCount, proxy: proxy); return .handled
            }
            .onKeyPress(.downArrow) {
                move(by: columnCount, proxy: proxy); return .handled
            }
            .onKeyPress(.escape) {
                selection.removeAll(); return .handled
            }
        }
        .overlay(alignment: .bottom) {
            if selection.count > 1 {
                selectionBar
            }
        }
    }

    // MARK: - Selection logic

    private func handleTap(on photo: Photo) {
        gridFocused = true
        #if canImport(AppKit)
        let flags = NSEvent.modifierFlags
        if flags.contains(.command) {
            // Cmd+klikk: toggle hozzáad/eltávolít a kijelölésből
            if selection.contains(photo.id) {
                selection.remove(photo.id)
            } else {
                selection.insert(photo.id)
            }
            return
        }
        if flags.contains(.shift), let anchorID = selection.first,
           let a = photos.firstIndex(where: { $0.id == anchorID }),
           let b = photos.firstIndex(where: { $0.id == photo.id }) {
            // Shift+klikk: tartomány kijelölés az első kijelölttől
            let range = a <= b ? a...b : b...a
            selection = Set(photos[range].map { $0.id })
            return
        }
        #endif
        // Alap klikk: single select (lecseréli a kijelölést)
        selection = [photo.id]
    }

    private func updateColumnCount(width: CGFloat) {
        // Ugyanaz a képlet, amit a LazyVGrid .adaptive használ:
        // max(1, floor((available + spacing) / (min + spacing)))
        let available = max(0, width - gridPadding * 2)
        let c = max(1, Int(floor((available + itemSpacing) / (itemMinWidth + itemSpacing))))
        if c != columnCount { columnCount = c }
    }

    private func move(by delta: Int, proxy: ScrollViewProxy) {
        guard !photos.isEmpty else { return }
        let currentIdx: Int = {
            if let id = selection.first, let i = photos.firstIndex(where: { $0.id == id }) {
                return i
            }
            return delta > 0 ? -1 : photos.count
        }()
        let next = max(0, min(photos.count - 1, currentIdx + delta))
        let nextID = photos[next].id
        selection = [nextID]
        withAnimation(.easeOut(duration: 0.15)) {
            proxy.scrollTo(nextID, anchor: .center)
        }
    }

    // MARK: - Subviews

    private var selectionBar: some View {
        HStack {
            Text("\(selection.count) kijelölve")
                .font(.callout)
            Spacer()
            Button("Kijelölés törlése") { selection.removeAll() }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.thinMaterial, in: Capsule())
        .padding(.bottom, 12)
    }
}

private struct PhotoCell: View {
    let photo: Photo
    let isSelected: Bool
    var isUnsynced: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ZStack(alignment: .topTrailing) {
                Rectangle()
                    .fill(Color.gray.opacity(0.2))
                    .aspectRatio(3/2, contentMode: .fit)
                    .overlay {
                        if let url = photo.localURL {
                            ThumbnailView(url: url)
                        } else {
                            Image(systemName: "photo")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                // Jobb felso sarok badge-ek
                VStack(spacing: 4) {
                    if isSelected {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.title2)
                            .foregroundStyle(.white, .blue)
                    }
                    if isUnsynced {
                        Image(systemName: "icloud.slash")
                            .font(.caption)
                            .foregroundStyle(.white)
                            .padding(3)
                            .background(.orange, in: Circle())
                    }
                }
                .padding(6)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isSelected ? Color.accentColor : isUnsynced ? Color.orange.opacity(0.6) : .clear, lineWidth: isSelected ? 3 : isUnsynced ? 2 : 0)
            )
            HStack(spacing: 4) {
                Text(photo.fileName)
                    .font(.caption)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .contentShape(Rectangle())
    }
}
