import Foundation
import Network

/// Minimal HTTP server that listens on 127.0.0.1 for OAuth loopback redirects.
///
/// Why we need this: Swiggy's OAuth server only accepts a small allowlist of
/// redirect URI schemes (`http:`, `https:`, plus a handful of partner apps).
/// Custom schemes like `northernlights://` are rejected. So we follow
/// RFC 8252's recommended pattern for native apps: run a loopback HTTP server,
/// register `http://127.0.0.1:PORT/callback` as our redirect URI.
///
/// Flow inside a single `authorize()` call:
///   1. `start()`     — binds the listener; suspends until it's actually accepting
///   2. `NSWorkspace.open(authURL)` (called by caller — not this class)
///   3. `waitForCallback()` — suspends until Swiggy redirects the browser back
///                            to our local server, then returns the callback URL
///   4. `stop()`      — safe to call anytime; also called internally on completion
final class LocalCallbackServer: @unchecked Sendable {

    /// The port we listen on. Registered with Swiggy in advance during
    /// Dynamic Client Registration so `redirect_uri` matches at auth time.
    static let port: UInt16 = 34567

    private var listener: NWListener?
    private let lock = NSLock()
    private var callbackContinuation: CheckedContinuation<URL, Error>?

    // MARK: - Public API

    /// Bind the local listener. Suspends until the socket is actually ready
    /// to accept connections (so it's safe to open the browser afterwards).
    func start() async throws {
        let port = NWEndpoint.Port(rawValue: Self.port)!
        let listener = try NWListener(using: .tcp, on: port)
        self.listener = listener

        // Wait for listener to enter .ready before returning
        try await withCheckedThrowingContinuation { (readyContinuation: CheckedContinuation<Void, Error>) in
            let didResume = Atomic(false)

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if didResume.compareAndSet(expected: false, new: true) {
                        readyContinuation.resume()
                    }
                case .failed(let error):
                    if didResume.compareAndSet(expected: false, new: true) {
                        readyContinuation.resume(throwing: error)
                    }
                default:
                    break
                }
            }

            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection: connection)
            }

            listener.start(queue: .global(qos: .userInitiated))
        }
    }

    /// Suspend until the browser hits our /callback endpoint. Returns the
    /// full callback URL (including `?code=…&state=…` query params).
    /// Times out after `timeout` seconds — treated as a user cancellation.
    func waitForCallback(timeout: TimeInterval = 300) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            callbackContinuation = continuation
            lock.unlock()

            // Safety timeout — if the user closes the browser or wanders off
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { [weak self] in
                self?.resumeCallback(with: .failure(SwiggyOAuthError.userCanceled))
            }
        }
    }

    /// Cancel the listener and clean up. Safe to call multiple times.
    func stop() {
        listener?.cancel()
        listener = nil
    }

    // MARK: - Connection handling

    private func handle(connection: NWConnection) {
        connection.start(queue: .global(qos: .userInitiated))
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, _, _ in
            defer { connection.cancel() }

            guard let self,
                  let data,
                  let request = String(data: data, encoding: .utf8) else { return }

            // Parse the request line: "GET /callback?code=xxx&state=yyy HTTP/1.1"
            let firstLine = request.components(separatedBy: "\r\n").first ?? ""
            let parts = firstLine.components(separatedBy: " ")
            guard parts.count >= 2, parts[0] == "GET" else { return }
            let path = parts[1]

            // Ignore incidental requests (favicon.ico, etc.) — respond with 404 politely
            guard path.hasPrefix("/callback") else {
                let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
                connection.send(content: response.data(using: .utf8),
                                completion: .contentProcessed { _ in })
                return
            }

            // Send the friendly close-window page
            let html = """
            <!doctype html>
            <html>
              <head><meta charset="utf-8"><title>Myles</title></head>
              <body style="font-family:-apple-system,BlinkMacSystemFont,sans-serif;text-align:center;padding:3rem;color:#1C2024">
                <h2>You're signed in.</h2>
                <p style="color:#60646C">You can close this window and return to Myles.</p>
              </body>
            </html>
            """
            let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
            connection.send(content: response.data(using: .utf8),
                            completion: .contentProcessed { _ in })

            // Return the full URL to the caller
            let callbackURL = URL(string: "http://127.0.0.1:\(Self.port)\(path)")!
            self.resumeCallback(with: .success(callbackURL))
        }
    }

    private func resumeCallback(with result: Result<URL, Error>) {
        lock.lock()
        let continuation = callbackContinuation
        callbackContinuation = nil
        lock.unlock()

        guard let continuation else { return }
        stop()

        switch result {
        case .success(let url): continuation.resume(returning: url)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}

// MARK: - Tiny atomic helper (avoids `import os` for one CAS op)

private final class Atomic<Value: Equatable>: @unchecked Sendable {
    private var value: Value
    private let lock = NSLock()

    init(_ value: Value) { self.value = value }

    /// Set `new` only if the current value equals `expected`. Returns true if swap happened.
    func compareAndSet(expected: Value, new: Value) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard value == expected else { return false }
        value = new
        return true
    }
}
