import Foundation
import CryptoKit

/// PKCE (Proof Key for Code Exchange) helpers for OAuth 2.1.
///
/// In plain English:
///   1. Generate a random secret (`codeVerifier`) — 43+ URL-safe chars.
///      This secret stays inside our app; it never leaves the device.
///   2. Hash it with SHA-256 and base64-url-encode the result → `codeChallenge`.
///      We send this hash to Swiggy in the authorization URL.
///   3. Later, when we exchange the auth code for tokens, we send the ORIGINAL
///      verifier. Swiggy re-hashes it and compares to the challenge it saw
///      earlier. If they match, we're the real requester.
///
/// The point: even if someone intercepts the auth code, they can't exchange
/// it for tokens without our verifier — which never crossed the wire.
enum PKCE {

    /// Generate a new PKCE pair. Call once per authorization attempt.
    /// Save the verifier in memory until token exchange completes; discard after.
    static func generate() -> (verifier: String, challenge: String) {
        let verifier = randomCodeVerifier()
        let challenge = codeChallenge(for: verifier)
        return (verifier, challenge)
    }

    // MARK: - Internals

    /// A cryptographically-random URL-safe string, 64 chars long (well within
    /// the RFC 7636 range of 43–128).
    private static func randomCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 48) // 48 bytes → 64 base64url chars
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "Failed to generate random bytes for PKCE verifier")
        return base64URLEncode(Data(bytes))
    }

    /// SHA-256 hash of the verifier, base64-url encoded. This is what we send
    /// to Swiggy in the `code_challenge` query parameter.
    private static func codeChallenge(for verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return base64URLEncode(Data(hash))
    }

    /// Standard base64url encoding: URL-safe alphabet, no padding.
    /// Same encoding OAuth/JWT specs use everywhere.
    private static func base64URLEncode(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
