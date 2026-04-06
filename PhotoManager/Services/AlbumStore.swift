import Foundation

/// Albumok perzisztálása JSON formátumban az Application Support mappába.
/// Tudatosan egyszerű, hogy ne legyen Core Data függés a vázban.
final class AlbumStore {
    private let fileURL: URL

    init(filename: String = "albums.json") {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("PhotoManager", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent(filename)
    }

    func load() -> [Album] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([Album].self, from: data)) ?? []
    }

    func save(_ albums: [Album]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(albums) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }
}
