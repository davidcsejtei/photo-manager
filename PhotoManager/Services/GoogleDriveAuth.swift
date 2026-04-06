import Foundation
import CryptoKit
import Network
#if canImport(AppKit)
import AppKit
#endif

/// Google OAuth 2.0 Desktop app flow PKCE-vel és loopback redirect URI-val.
///
/// Folyamat:
/// 1. PKCE verifier + challenge generálás
/// 2. `LoopbackListener` indítása egy szabad 127.0.0.1:PORT-on
/// 3. Browser megnyitása az auth URL-lel (redirect: http://127.0.0.1:PORT)
/// 4. Várakozás a visszahívott code-ra a listeneren
/// 5. Code → access_token + refresh_token csere a Google token endpointon
///
/// Referenciák:
///   https://developers.google.com/identity/protocols/oauth2/native-app
enum GoogleDriveAuth {

    struct Credentials {
        var clientID: String
        var clientSecret: String
    }

    struct Tokens {
        var accessToken: String
        var refreshToken: String?
        var expiresAt: Date
    }

    static let scope = "https://www.googleapis.com/auth/drive.file"

    // MARK: - Authorize

    static func authorize(credentials: Credentials) async throws -> Tokens {
        // 1) PKCE
        let verifier = randomURLSafeString(length: 64)
        let challenge = sha256URLSafe(verifier)

        // 2) Loopback listener
        let listener = LoopbackListener()
        let port = try await listener.start()
        let redirectURI = "http://127.0.0.1:\(port)"

        // 3) Auth URL + böngésző
        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: credentials.clientID),
            .init(name: "redirect_uri", value: redirectURI),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent")
        ]
        guard let url = comps.url else {
            listener.stop()
            throw AuthError.invalidURL
        }
        #if canImport(AppKit)
        await MainActor.run { NSWorkspace.shared.open(url) }
        #endif

        // 4) Várakozás a code-ra
        let code: String
        do {
            code = try await listener.waitForCode(timeout: 300)
        } catch {
            listener.stop()
            throw error
        }
        listener.stop()

        // 5) Token csere
        return try await exchangeCode(
            code,
            verifier: verifier,
            redirectURI: redirectURI,
            credentials: credentials
        )
    }

    // MARK: - Token refresh

    static func refresh(refreshToken: String, credentials: Credentials) async throws -> Tokens {
        let params: [String: String] = [
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        let json = try await postForm(to: "https://oauth2.googleapis.com/token", params: params)

        guard let access = json["access_token"] as? String else {
            throw AuthError.tokenExchangeFailed("no access_token")
        }
        let expiresIn = (json["expires_in"] as? Int) ?? 3600
        return Tokens(
            accessToken: access,
            refreshToken: (json["refresh_token"] as? String) ?? refreshToken,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }

    // MARK: - Private: code exchange

    private static func exchangeCode(
        _ code: String,
        verifier: String,
        redirectURI: String,
        credentials: Credentials
    ) async throws -> Tokens {
        let params: [String: String] = [
            "client_id": credentials.clientID,
            "client_secret": credentials.clientSecret,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": redirectURI
        ]
        let json = try await postForm(to: "https://oauth2.googleapis.com/token", params: params)

        guard let access = json["access_token"] as? String else {
            throw AuthError.tokenExchangeFailed("no access_token")
        }
        let expiresIn = (json["expires_in"] as? Int) ?? 3600
        return Tokens(
            accessToken: access,
            refreshToken: json["refresh_token"] as? String,
            expiresAt: Date().addingTimeInterval(TimeInterval(expiresIn))
        )
    }

    private static func postForm(to urlString: String, params: [String: String]) async throws -> [String: Any] {
        guard let url = URL(string: urlString) else { throw AuthError.invalidURL }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = encodeForm(params).data(using: .utf8)

        let (data, resp) = try await URLSession.shared.data(for: req)
        let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AuthError.tokenExchangeFailed("HTTP \(status): \(body)")
        }
        return (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }

    private static func encodeForm(_ params: [String: String]) -> String {
        params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }

    // MARK: - PKCE helpers

    private static func randomURLSafeString(length: Int) -> String {
        let chars = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_")
        var out = ""
        out.reserveCapacity(length)
        for _ in 0..<length {
            out.append(chars.randomElement()!)
        }
        return out
    }

    private static func sha256URLSafe(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return Data(digest).base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    // MARK: - Errors

    enum AuthError: LocalizedError {
        case invalidURL
        case tokenExchangeFailed(String)
        case timeout
        case listenerFailed(String)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Érvénytelen OAuth URL."
            case .tokenExchangeFailed(let s):
                return "Token csere sikertelen: \(s)"
            case .timeout:
                return "Az OAuth várakozás időtúllépés miatt megszakadt."
            case .listenerFailed(let s):
                return "Lokális visszahívás (loopback) nem indult: \(s)"
            }
        }
    }
}

// MARK: - LoopbackListener

/// One-shot HTTP listener a 127.0.0.1 egy szabad portján. Network.framework
/// `NWListener`-t használ, `.any` porttal (ephemeral). Amikor jön a Google
/// redirect (`GET /?code=... HTTP/1.1`), kiszedi a code-ot és visszaad egy
/// kis HTML-t a böngészőnek.
final class LoopbackListener {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "photomanager.oauth.loopback")

    private var readyContinuation: CheckedContinuation<UInt16, Error>?
    private var codeContinuation: CheckedContinuation<String, Error>?
    private var didResumeReady = false
    private var didResumeCode = false

    init() {
        let listener: NWListener
        do {
            listener = try NWListener(using: .tcp, on: .any)
        } catch {
            // Fallback: fixed port attempt
            listener = try! NWListener(using: .tcp, on: NWEndpoint.Port(rawValue: 0)!)
        }
        self.listener = listener
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<UInt16, Error>) in
            self.readyContinuation = cont
            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    if !self.didResumeReady, let port = self.listener.port?.rawValue {
                        self.didResumeReady = true
                        self.readyContinuation?.resume(returning: port)
                        self.readyContinuation = nil
                    }
                case .failed(let err):
                    if !self.didResumeReady {
                        self.didResumeReady = true
                        self.readyContinuation?.resume(throwing: GoogleDriveAuth.AuthError.listenerFailed(err.localizedDescription))
                        self.readyContinuation = nil
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.handle(connection: conn)
            }
            listener.start(queue: queue)
        }
    }

    func waitForCode(timeout: TimeInterval) async throws -> String {
        try await withThrowingTaskGroup(of: String.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (cont: CheckedContinuation<String, Error>) in
                    self.codeContinuation = cont
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                throw GoogleDriveAuth.AuthError.timeout
            }
            guard let code = try await group.next() else {
                throw GoogleDriveAuth.AuthError.timeout
            }
            group.cancelAll()
            return code
        }
    }

    func stop() {
        listener.cancel()
    }

    // MARK: - HTTP handling

    private func handle(connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            guard let self else { return }
            if let data, let request = String(data: data, encoding: .utf8) {
                if let code = self.parseCode(from: request) {
                    self.respondSuccess(on: connection)
                    if !self.didResumeCode {
                        self.didResumeCode = true
                        self.codeContinuation?.resume(returning: code)
                        self.codeContinuation = nil
                    }
                    return
                }
                self.respondError(on: connection)
            } else {
                self.respondError(on: connection)
            }
        }
    }

    private func parseCode(from httpRequest: String) -> String? {
        // Az első sor: "GET /?code=XXXX&state=YYYY HTTP/1.1"
        guard let firstLine = httpRequest.components(separatedBy: "\r\n").first else { return nil }
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2 else { return nil }
        let path = parts[1]
        guard let comps = URLComponents(string: "http://127.0.0.1\(path)") else { return nil }
        return comps.queryItems?.first(where: { $0.name == "code" })?.value
    }

    private func respondSuccess(on connection: NWConnection) {
        let body = """
        <!doctype html>
        <html><head><meta charset="utf-8"><title>Photo Manager</title>
        <style>body{font-family:-apple-system,sans-serif;padding:40px;text-align:center;color:#222;}h2{color:#0a7d32;}</style>
        </head><body>
        <h2>✓ Sikeres bejelentkezés</h2>
        <p>Visszatérhetsz a Photo Manager alkalmazáshoz.</p>
        </body></html>
        """
        let response = [
            "HTTP/1.1 200 OK",
            "Content-Type: text/html; charset=utf-8",
            "Content-Length: \(body.utf8.count)",
            "Connection: close",
            "",
            body
        ].joined(separator: "\r\n")
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private func respondError(on connection: NWConnection) {
        let response = "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { _ in
            connection.cancel()
        })
    }
}
