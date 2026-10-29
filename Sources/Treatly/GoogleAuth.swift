import AppKit
import Foundation
import Network
import TreatlyCore

struct GoogleAuthError: LocalizedError {
    var errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

/// Google sign-in for a desktop app: opens the browser, catches the redirect
/// on a 127.0.0.1 loopback port, and keeps the refresh token in the Keychain.
/// The OAuth client (a "Desktop app" client from Google Cloud Console) is
/// supplied by the user, so no credentials ship in the repo.
@MainActor
final class GoogleAuth {
    private static let refreshTokenAccount = "google-refresh-token"
    private static let scope = "https://www.googleapis.com/auth/tasks"

    private let credentials: () -> (id: String, secret: String)?
    private var accessToken: String?
    private var accessTokenExpiry = Date.distantPast

    init(credentials: @escaping () -> (id: String, secret: String)?) {
        self.credentials = credentials
    }

    var isSignedIn: Bool { Keychain.read(Self.refreshTokenAccount) != nil }

    func signOut() {
        Keychain.delete(Self.refreshTokenAccount)
        accessToken = nil
        accessTokenExpiry = .distantPast
    }

    func signIn() async throws {
        guard let client = credentials() else { throw GoogleAuthError("Add a Google OAuth client ID first.") }
        let receiver = try LoopbackReceiver()
        defer { receiver.stop() }
        let port = try await receiver.start()
        let redirectURI = "http://127.0.0.1:\(port)"
        let verifier = OAuth.makeVerifier()
        let state = OAuth.makeVerifier()

        var auth = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        auth.queryItems = [
            URLQueryItem(name: "client_id", value: client.id),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: Self.scope),
            URLQueryItem(name: "code_challenge", value: OAuth.challenge(for: verifier)),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: state),
        ]
        NSWorkspace.shared.open(auth.url!)

        let params = try await receiver.waitForCallback(timeout: 300)
        if let error = params["error"] { throw GoogleAuthError("Google sign-in failed: \(error)") }
        guard params["state"] == state, let code = params["code"] else { throw GoogleAuthError("Google sign-in returned an unexpected response.") }

        let token = try await requestToken([
            ("client_id", client.id),
            ("client_secret", client.secret),
            ("code", code),
            ("code_verifier", verifier),
            ("grant_type", "authorization_code"),
            ("redirect_uri", redirectURI),
        ])
        guard let refresh = token.refresh_token else { throw GoogleAuthError("Google did not return a refresh token.") }
        Keychain.write(refresh, for: Self.refreshTokenAccount)
        store(token)
    }

    func validAccessToken() async throws -> String {
        if let accessToken, accessTokenExpiry > Date().addingTimeInterval(60) { return accessToken }
        guard let client = credentials(), let refresh = Keychain.read(Self.refreshTokenAccount) else {
            throw GoogleAuthError("Not signed in to Google.")
        }
        let token = try await requestToken([
            ("client_id", client.id),
            ("client_secret", client.secret),
            ("refresh_token", refresh),
            ("grant_type", "refresh_token"),
        ])
        store(token)
        return token.access_token
    }

    private struct TokenResponse: Decodable {
        var access_token: String
        var expires_in: Double
        var refresh_token: String?
    }

    private func store(_ token: TokenResponse) {
        accessToken = token.access_token
        accessTokenExpiry = Date().addingTimeInterval(token.expires_in)
    }

    private func requestToken(_ fields: [(String, String)]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = OAuth.formBody(fields)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            if (response as? HTTPURLResponse)?.statusCode == 400 { signOut() }
            throw GoogleAuthError("Google token request failed: \(String(data: data, encoding: .utf8) ?? "")")
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}

/// A one-shot HTTP listener on 127.0.0.1 that waits for the OAuth redirect.
private final class LoopbackReceiver: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "treatly.oauth")
    // Both are only touched on `queue` once the listener starts.
    private var started: CheckedContinuation<UInt16, Error>?
    private var callback: CheckedContinuation<[String: String], Error>?

    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }

    func start() async throws -> UInt16 {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
            started = continuation
            listener.stateUpdateHandler = { [weak self] state in
                guard let self, let started = self.started else { return }
                switch state {
                case .ready:
                    self.started = nil
                    started.resume(returning: self.listener.port?.rawValue ?? 0)
                case .failed(let error):
                    self.started = nil
                    started.resume(throwing: error)
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] connection in self?.handle(connection) }
            listener.start(queue: queue)
        }
    }

    func waitForCallback(timeout: TimeInterval) async throws -> [String: String] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                self.callback = continuation
                self.queue.asyncAfter(deadline: .now() + timeout) {
                    self.finish(.failure(GoogleAuthError("Google sign-in timed out.")))
                }
            }
        }
    }

    func stop() { listener.cancel() }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16_384) { [weak self] data, _, _, _ in
            let requestLine = data.flatMap { String(data: $0, encoding: .utf8) }?.components(separatedBy: "\r\n").first ?? ""
            let params = OAuth.callbackParameters(requestLine: requestLine) ?? [:]
            let isCallback = params["code"] != nil || params["error"] != nil
            let body = isCallback
                ? "<html><body style=\"font-family:-apple-system;text-align:center;padding:4em\"><h2>Treatly is connected</h2><p>You can close this tab.</p></body></html>"
                : "Not found"
            let status = isCallback ? "200 OK" : "404 Not Found"
            let response = "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
            connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
            if isCallback { self?.finish(.success(params)) }
        }
    }

    /// Runs on `queue`.
    private func finish(_ result: Result<[String: String], Error>) {
        guard let callback else { return }
        self.callback = nil
        callback.resume(with: result)
    }
}
