import SwiftUI
#if canImport(QuickLookThumbnailing)
import QuickLookThumbnailing
#endif
#if canImport(AppKit)
import AppKit
#endif

#if canImport(AppKit)
/// URL → NSImage memória cache. URL path szerint kulcsol, és mindig a
/// LEGNAGYOBB eddig látott variánst tartja meg → a grid kis kép beíródik,
/// majd a detail view nagyobb verziója felülírja, és onnan az azonnali.
final class ThumbnailCache {
    static let shared = ThumbnailCache()
    private let cache = NSCache<NSString, NSImage>()

    private init() {
        cache.countLimit = 1500
    }

    func image(for url: URL) -> NSImage? {
        cache.object(forKey: url.path as NSString)
    }

    func set(_ image: NSImage, for url: URL) {
        // Csak frissítünk, ha a most érkezett kép nagyobb, mint a meglévő.
        if let existing = cache.object(forKey: url.path as NSString),
           existing.size.width >= image.size.width {
            return
        }
        cache.setObject(image, forKey: url.path as NSString)
    }
}
#endif

/// Gyors thumbnail egy fájl URL-ről progresszív renderrel:
/// 1) azonnal kirajzolja a cache-ben levő képet (ha bármi elérhető)
/// 2) ha a cached kisebb, mint a kért méret, háttérben újragenerálja
/// 3) az új képet cache-eli, hogy a következő megjelenítés azonnali legyen
struct ThumbnailView: View {
    let url: URL
    var targetSize: CGSize = CGSize(width: 260, height: 180)
    var contentMode: ContentMode = .fill

    #if canImport(AppKit)
    @State private var image: NSImage?
    #endif

    var body: some View {
        Group {
            #if canImport(AppKit)
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                placeholder
            }
            #else
            placeholder
            #endif
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .task(id: url) { await load() }
    }

    private var placeholder: some View {
        ZStack {
            Color.gray.opacity(0.2)
            Image(systemName: "photo")
                .foregroundStyle(.secondary)
                .font(.title2)
        }
    }

    @MainActor
    private func load() async {
        #if canImport(AppKit) && canImport(QuickLookThumbnailing)
        // 1) Azonnali cache hit — bármilyen méretű már generált kép jó placeholdernek.
        if let cached = ThumbnailCache.shared.image(for: url) {
            self.image = cached
            // Ha a cached legalább akkora, mint a kért méret, nem regenerálunk.
            if cached.size.width >= targetSize.width * (NSScreen.main?.backingScaleFactor ?? 2) * 0.9 {
                return
            }
        }

        // 2) Háttér generálás a kért méreten.
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(
            fileAt: url,
            size: targetSize,
            scale: scale,
            representationTypes: .thumbnail
        )
        do {
            let rep = try await QLThumbnailGenerator.shared.generateBestRepresentation(for: request)
            let img = rep.nsImage
            ThumbnailCache.shared.set(img, for: url)
            self.image = img
        } catch {
            // csend — placeholder marad
        }
        #endif
    }
}
