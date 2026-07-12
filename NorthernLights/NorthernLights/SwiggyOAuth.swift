import Foundation
import AppKit

/// The OAuth 2.1 + PKCE + Dynamic Client Registration orchestrator for Swiggy MCP.
///
/// Full flow (first launch):
///   1. Register this app with Swiggy → get a `client_id` (one-time, cached in Keychain)
///   2. Generate a PKCE verifier + challenge (per attempt)
///   3. Start a local loopback HTTP server on 127.0.0.1:34567 to catch the callback
///   4. Open Swiggy's login page in the user's default browser via NSWorkspace
///   5. User logs in → Swiggy redirects the browser to http://127.0.0.1:34567/callback?code=...
///   6. Our local server catches the request and hands the URL back to the app
///   7. Exchange code + verifier for access + refresh tokens
///   8. Save tokens to Keychain
///
/// Subsequent launches skip step 1 (cached client_id) and can skip 3–7 entirely
/// if the stored access token is still valid, or `refresh()` for a new one.
///
/// Why loopback and not a custom URL scheme: Swiggy's OAuth server only accepts
/// a small allowlist of redirect URI schemes. Custom schemes like
/// `northernlights://` are rejected. RFC 8252 recommends loopback for
/// native apps that can't use a whitelisted scheme.
@MainActor
final class SwiggyOAuth {

    // MARK: - Configuration

    private enum Endpoint {
        static let register = URL(string: "https://mcp.swiggy.com/auth/register")!
        static let authorize = URL(string: "https://mcp.swiggy.com/auth/authorize")!
        static let token = URL(string: "https://mcp.swiggy.com/auth/token")!
    }

    private enum Config {
        // Loopback redirect. Must match what LocalCallbackServer listens on.
        static let redirectURI = "http://127.0.0.1:\(LocalCallbackServer.port)/callback"
        static let clientName = "Northern Lights"
        static let scope = "mcp:tools mcp:resources mcp:prompts"
    }

    // MARK: - Public API

    /// Full login flow. Presents Swiggy's login page and stores the resulting tokens.
    /// Throws `SwiggyOAuthError` on failure (including user cancellation).
    func authorize() async throws {
        let clientId = try await registerClientIfNeeded()
        let pkce = PKCE.generate()
        let state = UUID().uuidString

        let authURL = buildAuthorizeURL(
            clientId: clientId,
            codeChallenge: pkce.challenge,
            state: state
        )

        let callbackURL = try await startBrowserAuth(url: authURL)
        let (code, returnedState) = try parseCallback(callbackURL)

        // CSRF check — the state we sent must match what came back.
        guard returnedState == state else {
            throw SwiggyOAuthError.stateMismatch
        }

        let tokens = try await exchangeCodeForTokens(
            code: code,
            verifier: pkce.verifier,
            clientId: clientId
        )
        try persistTokens(tokens)
    }

    /// Use the stored refresh token to get a new access token.
    /// Called when an API request comes back with 401, or preemptively before expiry.
    func refresh() async throws {
        guard let refreshToken = KeychainStore.get(.swiggyRefreshToken),
              let clientId = KeychainStore.get(.swiggyClientId) else {
            throw SwiggyOAuthError.notAuthenticated
        }

        let tokens = try await requestTokens(body: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientId
        ])
        try persistTokens(tokens)
    }

    /// True if we have an access token stored (does not check expiry).
    var isAuthenticated: Bool {
        KeychainStore.get(.swiggyAccessToken) != nil
    }

    /// Wipe local credentials. Does NOT tell Swiggy to invalidate the session server-side.
    func signOut() {
        KeychainStore.clearAll()
    }

    // MARK: - Dynamic Client Registration

    /// Register with Swiggy if we haven't already. Returns the client_id.
    /// Cached in Keychain — only runs the network call on first launch.
    private func registerClientIfNeeded() async throws -> String {
        if let existing = KeychainStore.get(.swiggyClientId) {
            return existing
        }

        let body = DCRRequest(
            redirectUris: [Config.redirectURI],
            tokenEndpointAuthMethod: "none",
            grantTypes: ["authorization_code", "refresh_token"],
            responseTypes: ["code"],
            clientName: Config.clientName,
            scope: Config.scope
        )

        var request = URLRequest(url: Endpoint.register)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateSuccess(response, data: data, mapTo: SwiggyOAuthError.registrationFailed)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let decoded = try decoder.decode(DCRResponse.self, from: data)

        try KeychainStore.set(decoded.clientId, for: .swiggyClientId)
        return decoded.clientId
    }

    // MARK: - Authorize URL

    private func buildAuthorizeURL(clientId: String, codeChallenge: String, state: String) -> URL {
        var components = URLComponents(url: Endpoint.authorize, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: Config.redirectURI),
            URLQueryItem(name: "scope", value: Config.scope),
            URLQueryItem(name: "code_challenge", value: codeChallenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "state", value: state)
        ]
        return components.url!
    }

    // MARK: - Browser handoff (loopback)

    /// Start the local loopback server, open the auth URL in the user's
    /// default browser, and suspend until Swiggy redirects the browser back.
    private func startBrowserAuth(url: URL) async throws -> URL {
        let server = LocalCallbackServer()
        try await server.start()
        defer { server.stop() }

        // Open the auth URL in whatever the user's default browser is (Chrome, Safari, Arc, etc.)
        guard NSWorkspace.shared.open(url) else {
            throw SwiggyOAuthError.serverError(
                status: 0,
                body: "Could not open browser for Swiggy sign-in"
            )
        }

        return try await server.waitForCallback()
    }

    private func parseCallback(_ url: URL) throws -> (code: String, state: String) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.queryItems,
              let code = items.first(where: { $0.name == "code" })?.value,
              let state = items.first(where: { $0.name == "state" })?.value else {
            throw SwiggyOAuthError.invalidCallback
        }
        return (code, state)
    }

    // MARK: - Token exchange

    private func exchangeCodeForTokens(code: String, verifier: String, clientId: String) async throws -> TokenResponse {
        try await requestTokens(body: [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientId,
            "redirect_uri": Config.redirectURI,
            "code_verifier": verifier
        ])
    }

    private func requestTokens(body: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: Endpoint.token)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formURLEncode(body).data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateSuccess(response, data: data, mapTo: SwiggyOAuthError.tokenExchangeFailed)

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(TokenResponse.self, from: data)
    }

    private func persistTokens(_ tokens: TokenResponse) throws {
        try KeychainStore.set(tokens.accessToken, for: .swiggyAccessToken)
        if let refresh = tokens.refreshToken {
            try KeychainStore.set(refresh, for: .swiggyRefreshToken)
        }
    }

    // MARK: - Helpers

    private func validateSuccess(_ response: URLResponse, data: Data, mapTo error: @autoclosure () -> SwiggyOAuthError) throws {
        guard let http = response as? HTTPURLResponse else {
            throw error()
        }
        guard (200...299).contains(http.statusCode) else {
            // Try to include server's error message for easier debugging.
            let body = String(data: data, encoding: .utf8) ?? ""
            throw SwiggyOAuthError.serverError(status: http.statusCode, body: body)
        }
    }

    private func formURLEncode(_ params: [String: String]) -> String {
        params.map { key, value in
            let k = key.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? key
            let v = value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value
            return "\(k)=\(v)"
        }.joined(separator: "&")
    }
}

// MARK: - Codable types

private struct DCRRequest: Encodable {
    let redirectUris: [String]
    let tokenEndpointAuthMethod: String
    let grantTypes: [String]
    let responseTypes: [String]
    let clientName: String
    let scope: String
}

private struct DCRResponse: Decodable {
    let clientId: String
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: Int?
    let tokenType: String?
}

// MARK: - Errors

enum SwiggyOAuthError: LocalizedError {
    case registrationFailed
    case userCanceled
    case invalidCallback
    case stateMismatch
    case tokenExchangeFailed
    case notAuthenticated
    case serverError(status: Int, body: String)

    var errorDescription: String? {
        switch self {
        case .registrationFailed:
            return "Couldn't register with Swiggy. Please try again."
        case .userCanceled:
            return "Sign-in was cancelled."
        case .invalidCallback:
            return "Invalid response from Swiggy after sign-in."
        case .stateMismatch:
            return "Sign-in failed a security check. Please try again."
        case .tokenExchangeFailed:
            return "Couldn't complete sign-in with Swiggy."
        case .notAuthenticated:
            return "Not signed in."
        case .serverError(let status, let body):
            return "Swiggy returned an error (\(status)): \(body)"
        }
    }
}
