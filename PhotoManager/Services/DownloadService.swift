import Foundation

/// A felhasználó által kiválasztott cél-mappába történő mentés helye.
/// Itt csak felhasználó-barát útvonalakat és subdir-képzést adunk.
enum DownloadService {

    /// Alap letöltési mappa: `~/Pictures/PhotoManager/YYYY-MM-DD/`.
    static func defaultDestination(for date: Date = Date()) -> URL {
        let fm = FileManager.default
        let pictures = (try? fm.url(for: .picturesDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Pictures")
        let root = pictures.appendingPathComponent("PhotoManager", isDirectory: true)
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        let folder = root.appendingPathComponent(fmt.string(from: date), isDirectory: true)
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Fájl másolása egyik helyről a másikra (pl. staging mappába).
    /// Ütközés esetén a cél fájlnevet "-1", "-2" stb. suffix-szel egyedíti.
    static func copyFile(from source: URL, into targetDir: URL) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: targetDir, withIntermediateDirectories: true)
        var destination = targetDir.appendingPathComponent(source.lastPathComponent)
        var index = 1
        while fm.fileExists(atPath: destination.path) {
            let ext = source.pathExtension
            let base = source.deletingPathExtension().lastPathComponent
            destination = targetDir.appendingPathComponent("\(base)-\(index).\(ext)")
            index += 1
        }
        try fm.copyItem(at: source, to: destination)
        return destination
    }
}
