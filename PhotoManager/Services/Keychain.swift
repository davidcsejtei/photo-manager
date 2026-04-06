import Foundation

/// Egyszerű fájl-alapú credential tároló az Application Support mappában.
///
/// Miért nem Keychain? Az ad-hoc signed (kódaláírás nélküli) macOS app-ok
/// minden Keychain-hozzáférésnél rendszerjelszót kérnek debug módban.
/// Fejlesztés alatt ez elviselhetetlen, ezért egy lokális JSON fájlt
/// használunk helyette. Éles disztribúcióhoz (notarized + signed) érdemes
/// visszaváltani valódi Keychain-re.
///
/// A fájl: `~/Library/Application Support/PhotoManager/credentials.json`
enum Keychain {

    private static let fileURL: URL = {
        let fm = FileManager.default
        let base = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
            ?? fm.temporaryDirectory
        let dir = base.appendingPathComponent("PhotoManager", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("credentials.json")
    }()

    private static var cache: [String: String]? = nil

    // MARK: - Public API (ugyanaz, mint korábban)

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        var dict = loadDict()
        dict[key] = value
        cache = dict
        return saveDict(dict)
    }

    static func get(_ key: String) -> String? {
        return loadDict()[key]
    }

    static func delete(_ key: String) {
        var dict = loadDict()
        dict.removeValue(forKey: key)
        cache = dict
        saveDict(dict)
    }

    // MARK: - File I/O

    private static func loadDict() -> [String: String] {
        if let cached = cache { return cached }
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: String].self, from: data)
        else { return [:] }
        cache = dict
        return dict
    }

    @discardableResult
    private static func saveDict(_ dict: [String: String]) -> Bool {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(dict)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            return false
        }
    }
}
