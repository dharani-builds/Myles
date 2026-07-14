import Foundation

/// Observable auth state — the single source of truth SwiftUI watches to decide
/// which screen to show (idle / authorizing / authenticated / error).
///
/// The UI calls `signIn()`, this class updates `status`, SwiftUI re-renders.
///
/// **For testing during dev:** to reset back to the "idle" state, either call
/// `signOut()` from code, or wipe the Keychain items via terminal:
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

    /// Clear local credentials. Dev/testing affordance for now.
    func signOut() {
        oauth.signOut()
        status = .idle
    }

    // MARK: - Preview helpers
    //
    // SwiftUI Previews can't run the real OAuth flow, so we expose a factory
    // that returns an AuthState already in the `.authenticated` state. This
    // lets us preview downstream orders screens (loading / empty / loaded /
    // error) without pretending to sign in.

    /// A pre-authenticated instance for Xcode Previews. Do not use in the app.
    static var previewAuthenticated: AuthState {
        let s = AuthState()
        s.status = .authenticated
        return s
    }
}
