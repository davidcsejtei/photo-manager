import Foundation

/// Upload batch-ek perzisztálása (JSON az Application Support mappában) +
/// az ideiglenes staging mappa kezelése.
final class UploadBatchStore {

    private let fileURL: URL
    let stagingRoot: URL

    init(filename: String = "upload_batches.json") {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("PhotoManager", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        self.fileURL = dir.appendingPathComponent(filename)

        self.stagingRoot = dir.appendingPathComponent("staging", isDirectory: true)
        try? fm.createDirectory(at: stagingRoot, withIntermediateDirectories: true)
    }

    func load() -> [UploadBatch] {
        guard let data = try? Data(contentsOf: fileURL) else { return [] }
        return (try? JSONDecoder().decode([UploadBatch].self, from: data)) ?? []
    }

    func save(_ batches: [UploadBatch]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(batches) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// Új staging mappa egy adott batch-hez. A név alapján szlug-ot képez,
    /// hogy a mappa név biztonságos legyen a fájlrendszeren.
    func createStagingFolder(for batchName: String) throws -> URL {
        let slug = Self.slugify(batchName)
        let url = stagingRoot.appendingPathComponent("\(slug)-\(UUID().uuidString.prefix(6))", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func slugify(_ s: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(.init(charactersIn: "-_"))
        let mapped = s.lowercased().replacingOccurrences(of: " ", with: "-")
        return String(mapped.unicodeScalars.filter { allowed.contains($0) })
    }
}
