import Foundation

/// Observable auth state — the single source of truth SwiftUI watches to decide
/// which screen to show (idle / authorizing / authenticated / error).
///
/// The UI calls `signIn()`, this class updates `status`, SwiftUI re-renders.
///
/// **Session-expired signal:**
/// When the poller catches a 401 (dead token), it calls `markSessionExpired()`
/// instead of the vanilla `signOut()`. Both drop to `.idle`, but the former
/// sets `justExpiredSessionMessageShown = true` so LoginView can show a
/// contextual "Your session has expired" line above the CTA. The flag is
/// cleared automatically on the next `signIn()` attempt or explicit `signOut()`.
///
/// **For testing during dev:** to wipe local credentials from the terminal:
///   `security delete-generic-password -s com.dharani.NorthernLights`
///   (run three times — once per stored key: clientId, accessToken, refreshToken)
@MainActor
@Observable
final class AuthState {

    enum Status: Equatable {
        case idle                 // never signed in — or signed out
        case authorizing          // browser open, waiting on the user
        case authenticated        // valid tokens in Keychain
        case error(String)        // last sign-in attempt failed; retryable
    }

    private(set) var status: Status

    /// Set when auth was invalidated by the server (401), not by explicit
    /// sign-out. LoginView reads this to show the "Session expired" preamble.
    /// Cleared on next signIn attempt or explicit signOut.
    private(set) var justExpiredSessionMessageShown: Bool = false

    private let oauth: SwiggyOAuth

    init() {
        let oauth = SwiggyOAuth()
        self.oauth = oauth
        // Rehydrate on launch: if Keychain already has an access token,
        // treat the user as signed in. (Doesn't validate expiry — an
        // expired token will fail at first API call and trigger refresh.)
        self.status = oauth.isAuthenticated ? .authenticated : .idle
    }

    /// Kick off the OAuth flow. Called from the "Sign in with Swiggy" button.
    func signIn() async {
        // Clear the "session expired" preamble the moment the user acts on it.
        justExpiredSessionMessageShown = false
        status = .authorizing
        do {
            try await oauth.authorize()
            status = .authenticated
        } catch SwiggyOAuthError.userCanceled {
            // User closed the auth window — treat as neutral, not error.
            status = .idle
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    /// Explicit sign-out from the More menu. Wipes local credentials, resets
    /// the session-expired flag, and returns to the fresh login screen.
    func signOut() {
        oauth.signOut()
        justExpiredSessionMessageShown = false
        status = .idle
    }

    /// Called by the poller when Swiggy returns 401 (token is dead). Same
    /// as `signOut()` in terms of local state — wipes credentials and drops
    /// to `.idle` — but sets `justExpiredSessionMessageShown = true` so
    /// LoginView can explain why the user is looking at the login screen.
    func markSessionExpired() {
        oauth.signOut()
        justExpiredSessionMessageShown = true
        status = .idle
    }

    // MARK: - Preview helpers
    //
    // Do not use in the app. These bypass Keychain to force a specific state
    // for Xcode Previews (which can't run the OAuth flow).

    /// Pre-authenticated instance — for previewing signed-in screens.
    static var previewAuthenticated: AuthState {
        let s = AuthState()
        s.status = .authenticated
        return s
    }

    /// Fresh signed-out instance — for previewing the login screen.
    /// Forces `.idle` regardless of what's in Keychain.
    static var previewSignedOut: AuthState {
        let s = AuthState()
        s.status = .idle
        s.justExpiredSessionMessageShown = false
        return s
    }

    /// Signed-out instance that got here via 401 — for previewing the
    /// "session expired" variant of the login screen.
    static var previewSessionExpired: AuthState {
        let s = AuthState()
        s.status = .idle
        s.justExpiredSessionMessageShown = true
        return s
    }

    /// Mid-OAuth instance — for previewing the disabled/spinner CTA state.
    static var previewAuthorizing: AuthState {
        let s = AuthState()
        s.status = .authorizing
        return s
    }

    /// OAuth attempt failed — for previewing the inline error message.
    static var previewAuthError: AuthState {
        let s = AuthState()
        s.status = .error("Couldn't complete sign-in with Swiggy.")
        return s
    }
}
