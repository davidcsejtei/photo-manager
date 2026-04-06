import Foundation

/// Google Drive v3 REST API wrapper — valódi implementáció.
///
/// Architektúra:
/// - `shared` singleton: SwiftUI `@EnvironmentObject`-ként injektálva
///   (`PhotoManagerApp`), és `ObservableObject`-ként publikálja a bejelentkezési
///   állapotot, így a Settings UI és az upload view is reaktívan frissül.
/// - `Keychain`-ben tároljuk: `client_id`, `client_secret`, `access_token`,
///   `refresh_token`, `expires_at`.
/// - `GoogleDriveAuth` végzi az OAuth 2.0 PKCE + loopback visszahívást.
/// - A Drive API hívásokhoz minden alkalommal lekérjük a friss access token-t
///   (`ensureValidToken`), ami szükség esetén refresh tokenből újat szerez.
@MainActor
final class GoogleDriveService: ObservableObject {

    static let shared = GoogleDriveService()

    // MARK: - Published state

    @Published private(set) var isSignedIn: Bool = false
    @Published private(set) var hasCredentials: Bool = false
    @Published var lastError: String?

    // MARK: - In-memory token cache (source of truth: Keychain)

    private var accessToken: String?
    private var refreshToken: String?
    private var expiresAt: Date = .distantPast

    // MARK: - Keychain keys

    private enum Key {
        static let clientID = "gd_client_id"
        static let clientSecret = "gd_client_secret"
        static let accessToken = "gd_access_token"
        static let refreshToken = "gd_refresh_token"
        static let expiresAt = "gd_expires_at"
    }

    private init() {
        loadPersistedTokens()
        refreshCredentialsFlag()
    }

    // MARK: - Credentials

    var clientID: String { Keychain.get(Key.clientID) ?? "" }
    var clientSecret: String { Keychain.get(Key.clientSecret) ?? "" }

    func saveCredentials(clientID: String, clientSecret: String) {
        Keychain.set(clientID, for: Key.clientID)
        Keychain.set(clientSecret, for: Key.clientSecret)
        refreshCredentialsFlag()
    }

    private func refreshCredentialsFlag() {
        hasCredentials = !clientID.isEmpty && !clientSecret.isEmpty
    }

    // MARK: - Sign in / out

    func signIn() async throws {
        guard hasCredentials else { throw DriveError.missingCredentials }
        let creds = GoogleDriveAuth.Credentials(clientID: clientID, clientSecret: clientSecret)
        let tokens = try await GoogleDriveAuth.authorize(credentials: creds)
        apply(tokens: tokens)
        persistTokens()
        isSignedIn = true
    }

    func signOut() {
        accessToken = nil
        refreshToken = nil
        expiresAt = .distantPast
        Keychain.delete(Key.accessToken)
        Keychain.delete(Key.refreshToken)
        Keychain.delete(Key.expiresAt)
        isSignedIn = false
    }

    private func loadPersistedTokens() {
        accessToken = Keychain.get(Key.accessToken)
        refreshToken = Keychain.get(Key.refreshToken)
        if let s = Keychain.get(Key.expiresAt), let ts = Double(s) {
            expiresAt = Date(timeIntervalSince1970: ts)
        }
        isSignedIn = accessToken != nil || refreshToken != nil
    }

    private func persistTokens() {
        if let t = accessToken { Keychain.set(t, for: Key.accessToken) }
        if let t = refreshToken { Keychain.set(t, for: Key.refreshToken) }
        Keychain.set(String(expiresAt.timeIntervalSince1970), for: Key.expiresAt)
    }

    private func apply(tokens: GoogleDriveAuth.Tokens) {
        accessToken = tokens.accessToken
        if let r = tokens.refreshToken { refreshToken = r }
        expiresAt = tokens.expiresAt
    }

    /// Biztosítja, hogy érvényes access token legyen. Ha lejárt (vagy 60 mp-n
    /// belül lejár), refresh tokenből újat kér. Ha nincs refresh token sem,
    /// `notSignedIn` hibát dob.
    private func ensureValidToken() async throws -> String {
        if let token = accessToken, Date().addingTimeInterval(60) < expiresAt {
            return token
        }
        guard let rt = refreshToken else { throw DriveError.notSignedIn }
        let creds = GoogleDriveAuth.Credentials(clientID: clientID, clientSecret: clientSecret)
        let newTokens = try await GoogleDriveAuth.refresh(refreshToken: rt, credentials: creds)
        apply(tokens: newTokens)
        persistTokens()
        guard let t = accessToken else { throw DriveError.notSignedIn }
        return t
    }

    // MARK: - Drive v3 REST

    /// Létrehoz egy mappát a Drive-on, visszaadja a folder ID-t.
    func createFolder(named name: String, parentID: String? = nil) async throws -> String {
        let token = try await ensureValidToken()
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [
            "name": name,
            "mimeType": "application/vnd.google-apps.folder"
        ]
        if let p = parentID { body["parents"] = [p] }
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw DriveError.http("createFolder", status, String(data: data, encoding: .utf8) ?? "")
        }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let id = json["id"] as? String
        else {
            throw DriveError.badResponse
        }
        return id
    }

    /// Multipart upload egy lokális fájl → Drive mappa. Visszaadja a drive file ID-t.
    @discardableResult
    func uploadFile(at localURL: URL, toFolder folderID: String) async throws -> String {
        let token = try await ensureValidToken()

        let boundary = "boundary-\(UUID().uuidString)"
        let metadata: [String: Any] = [
            "name": localURL.lastPathComponent,
            "parents": [folderID]
        ]
        let metaData = try JSONSerialization.data(withJSONObject: metadata)
        let fileData = try Data(contentsOf: localURL)
        let mime = mimeType(for: localURL.pathExtension)

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Type: application/json; charset=UTF-8\r\n\r\n")
        body.append(metaData)
        body.append("\r\n--\(boundary)\r\n")
        body.append("Content-Type: \(mime)\r\n\r\n")
        body.append(fileData)
        body.append("\r\n--\(boundary)--\r\n")

        var req = URLRequest(url: URL(string: "https://www.googleapis.com/upload/drive/v3/files?uploadType=multipart")!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("multipart/related; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        req.httpBody = body

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw DriveError.http("uploadFile", status, String(data: data, encoding: .utf8) ?? "")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        return (json?["id"] as? String) ?? ""
    }

    func deleteFile(driveFileID: String) async throws {
        let token = try await ensureValidToken()
        var req = URLRequest(url: URL(string: "https://www.googleapis.com/drive/v3/files/\(driveFileID)")!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...204).contains(status) else {
            throw DriveError.http("deleteFile", status, String(data: data, encoding: .utf8) ?? "")
        }
    }

    /// Egy mappa tartalma: [fájlnév: drive fileID]. Pagination egyszerűsítve:
    /// egy oldal (az első 1000 találat). A ZV-E10 batch-ekhez ez bőven elég.
    func listFolder(_ folderID: String) async throws -> [String: String] {
        let token = try await ensureValidToken()
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comps.queryItems = [
            .init(name: "q", value: "'\(folderID)' in parents and trashed=false"),
            .init(name: "fields", value: "files(id,name)"),
            .init(name: "pageSize", value: "1000")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw DriveError.http("listFolder", status, String(data: data, encoding: .utf8) ?? "")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [[String: Any]] ?? []
        var result: [String: String] = [:]
        for f in files {
            if let id = f["id"] as? String, let name = f["name"] as? String {
                result[name] = id
            }
        }
        return result
    }

    /// Keres egy mappát név + szülő alapján. Ha nincs, létrehozza.
    /// A `parentID == nil` esetben a Drive gyökerében keres.
    func findOrCreateFolder(named name: String, parentID: String?) async throws -> String {
        if let existing = try await findFolder(named: name, parentID: parentID) {
            return existing
        }
        return try await createFolder(named: name, parentID: parentID)
    }

    /// Keres egy létező mappát név + szülő alapján. `nil`-t ad ha nincs.
    func findFolder(named name: String, parentID: String?) async throws -> String? {
        let token = try await ensureValidToken()
        let parent = parentID ?? "root"
        let q = "name='\(name)' and '\(parent)' in parents and mimeType='application/vnd.google-apps.folder' and trashed=false"
        var comps = URLComponents(string: "https://www.googleapis.com/drive/v3/files")!
        comps.queryItems = [
            .init(name: "q", value: q),
            .init(name: "fields", value: "files(id,name)"),
            .init(name: "pageSize", value: "1")
        ]
        var req = URLRequest(url: comps.url!)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            throw DriveError.http("findFolder", status, String(data: data, encoding: .utf8) ?? "")
        }
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let files = json?["files"] as? [[String: Any]] ?? []
        return files.first?["id"] as? String
    }

    // MARK: - Helpers

    private func mimeType(for ext: String) -> String {
        switch ext.lowercased() {
        case "jpg", "jpeg": return "image/jpeg"
        case "png": return "image/png"
        case "heic", "heif": return "image/heic"
        case "tiff", "tif": return "image/tiff"
        case "arw", "raf", "nef", "cr2", "cr3", "dng": return "image/x-dcraw"
        case "mp4": return "video/mp4"
        case "mov": return "video/quicktime"
        default: return "application/octet-stream"
        }
    }

    enum DriveError: LocalizedError {
        case missingCredentials
        case notSignedIn
        case http(String, Int, String)
        case badResponse

        var errorDescription: String? {
            switch self {
            case .missingCredentials:
                return "Hiányzó Client ID vagy Client Secret — állítsd be a Beállításokban."
            case .notSignedIn:
                return "Nincs érvényes Google Drive kapcsolat. Jelentkezz be a Beállításokban."
            case .http(let op, let code, let body):
                return "\(op) hiba (HTTP \(code)): \(body)"
            case .badResponse:
                return "Érvénytelen válasz a Drive API-tól."
            }
        }
    }
}

// MARK: - Data append helper

private extension Data {
    mutating func append(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
