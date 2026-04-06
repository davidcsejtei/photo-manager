import Foundation
#if canImport(AppKit)
import AppKit
#endif

/// A Sony ZV-E10 (és sok más kamera) USB-n Mass Storage módban egy egyszerű
/// meghajtóként jelenik meg a macOS-en (pl. `/Volumes/Untitled`). A fotók a
/// `DCIM/100MSDCF/` stílusú mappákban vannak. Ez a szolgáltatás ezt detektálja:
///
/// - figyeli az `NSWorkspace` mount/unmount eseményeit
/// - induláskor végignézi a már csatlakoztatott köteteket
/// - DCIM mappát kereső egyszerű heurisztika → kamera
/// - az "aktuális mappa" a DCIM legutóbb módosított alkönyvtára (ahova a kamera
///   a legutolsó képeket írta)
/// - a fájlok valódi `URL`-ekkel rendelkeznek, így thumbnail, letöltés (copy)
///   és törlés (`FileManager.removeItem`) triviális
@MainActor
final class VolumeCameraService: NSObject, CameraServicing {

    weak var delegate: CameraServiceDelegate?

    private(set) var currentVolume: URL?
    private(set) var currentFolder: URL?
    private var mountObserver: NSObjectProtocol?
    private var unmountObserver: NSObjectProtocol?

    /// A támogatott kiterjesztések (kisbetűvel). A ZV-E10 JPG + ARW-t ad ki,
    /// de általánosítva pár másikat is beveszünk.
    private static let imageExtensions: Set<String> = [
        "jpg", "jpeg", "arw", "raf", "nef", "cr2", "cr3", "dng",
        "heic", "heif", "png", "tiff", "tif"
    ]

    // MARK: - Lifecycle

    func start() {
        #if canImport(AppKit)
        let nc = NSWorkspace.shared.notificationCenter
        mountObserver = nc.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.rescan() }
        }
        unmountObserver = nc.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            Task { @MainActor in self?.handleUnmount(note: note) }
        }
        #endif
        rescan()
    }

    func stop() {
        #if canImport(AppKit)
        let nc = NSWorkspace.shared.notificationCenter
        if let o = mountObserver { nc.removeObserver(o) }
        if let o = unmountObserver { nc.removeObserver(o) }
        #endif
        mountObserver = nil
        unmountObserver = nil
    }

    func reloadMediaFiles() {
        guard let folder = currentFolder else {
            delegate?.cameraService(self, didUpdatePhotos: [])
            return
        }
        delegate?.cameraService(self, didUpdatePhotos: loadPhotos(from: folder))
    }

    // MARK: - Mount handling

    private func rescan() {
        // Ha már van aktív kötet, és továbbra is létezik, csak újraolvassuk a fájlokat.
        if let v = currentVolume, FileManager.default.fileExists(atPath: v.path) {
            reloadMediaFiles()
            return
        }

        let fm = FileManager.default
        let volumes = fm.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsRemovableKey, .volumeNameKey],
            options: [.skipHiddenVolumes]
        ) ?? []

        for url in volumes where isLikelyCamera(url) {
            attach(to: url)
            return
        }

        // Semmi camera → megmondjuk a delegate-nek, hogy üres.
        if currentVolume == nil {
            delegate?.cameraService(self, didUpdatePhotos: [])
        }
    }

    private func handleUnmount(note: Notification) {
        guard let current = currentVolume else { return }
        #if canImport(AppKit)
        if let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL {
            if url == current {
                currentVolume = nil
                currentFolder = nil
                delegate?.cameraServiceDidDisconnect(self)
                // Esetleg van másik kamera is csatlakoztatva?
                rescan()
                return
            }
        }
        #endif
        // Ha nem kaptuk meg a volume URL-t a userInfoban, akkor ellenőrzés fájlrendszerből:
        if !FileManager.default.fileExists(atPath: current.path) {
            currentVolume = nil
            currentFolder = nil
            delegate?.cameraServiceDidDisconnect(self)
            rescan()
        }
    }

    private func isLikelyCamera(_ volumeURL: URL) -> Bool {
        // A kamerák DCIM mappát tartalmaznak (DCF szabvány).
        let dcim = volumeURL.appendingPathComponent("DCIM", isDirectory: true)
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: dcim.path, isDirectory: &isDir) && isDir.boolValue
    }

    private func attach(to volumeURL: URL) {
        currentVolume = volumeURL
        let dcim = volumeURL.appendingPathComponent("DCIM", isDirectory: true)
        let folder = latestSubfolder(in: dcim) ?? dcim
        currentFolder = folder

        let name: String = {
            #if canImport(AppKit)
            if let n = try? volumeURL.resourceValues(forKeys: [.volumeNameKey]).volumeName, !n.isEmpty {
                return n
            }
            #endif
            return volumeURL.lastPathComponent
        }()

        delegate?.cameraService(self, didConnect: name)
        delegate?.cameraService(self, didUpdatePhotos: loadPhotos(from: folder))
    }

    // MARK: - Folder / file scanning

    /// A DCIM legutóbb módosított alkönyvtára — ez az a mappa, ahová a kamera
    /// jelenleg a képeket menti. A Sony kamerák pl. `100MSDCF`, `101MSDCF`, ...
    private func latestSubfolder(in dcim: URL) -> URL? {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .contentModificationDateKey]
        let items = (try? fm.contentsOfDirectory(
            at: dcim,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
        let dirs = items.filter {
            (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        }
        return dirs.max { a, b in
            let aDate = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let bDate = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return aDate < bDate
        }
    }

    private func loadPhotos(from folder: URL) -> [Photo] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [
            .fileSizeKey,
            .contentModificationDateKey,
            .creationDateKey,
            .isRegularFileKey
        ]
        let items = (try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        let files = items
            .filter { Self.imageExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { lhs, rhs in
                let l = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let r = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return l > r   // legújabb elöl
            }

        return files.map { url in
            let rv = try? url.resourceValues(forKeys: Set(keys))
            let size = Int64(rv?.fileSize ?? 0)
            let date = rv?.contentModificationDate ?? rv?.creationDate
            return Photo(
                id: url.path,              // teljes elérési út stabil kulcsként
                fileName: url.lastPathComponent,
                fileSize: size,
                captureDate: date,
                thumbnailURL: url,
                isDownloaded: false,
                localURL: url,
                deviceFileRef: nil
            )
        }
    }

    // MARK: - Download / Delete

    func download(photoIDs: [String], to destination: URL) async throws -> [URL] {
        let fm = FileManager.default
        try fm.createDirectory(at: destination, withIntermediateDirectories: true)

        var result: [URL] = []
        for id in photoIDs {
            let src = URL(fileURLWithPath: id)
            guard fm.fileExists(atPath: src.path) else { continue }

            var dest = destination.appendingPathComponent(src.lastPathComponent)
            var i = 1
            while fm.fileExists(atPath: dest.path) {
                let base = src.deletingPathExtension().lastPathComponent
                let ext = src.pathExtension
                dest = destination.appendingPathComponent("\(base)-\(i).\(ext)")
                i += 1
            }
            try fm.copyItem(at: src, to: dest)
            result.append(dest)
        }
        return result
    }

    func delete(photoIDs: [String]) async throws {
        let fm = FileManager.default
        for id in photoIDs {
            let url = URL(fileURLWithPath: id)
            if fm.fileExists(atPath: url.path) {
                try fm.removeItem(at: url)
            }
        }
        reloadMediaFiles()
    }
}
