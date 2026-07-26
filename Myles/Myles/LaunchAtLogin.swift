import Foundation
import ServiceManagement

/// Wraps `SMAppService.mainApp` so the ⋯ menu can offer a "Launch at login"
/// toggle without knowing anything about ServiceManagement.
///
/// **How it works:** macOS 13+ lets an app register *itself* as a login item
/// — no helper bundle, no `LSSharedFileList`, no user visiting System
/// Settings. The registration is stored by the system, keyed on the app's
/// bundle identifier and code signature, and shows up under
/// *System Settings → General → Login Items* where the user can also
/// disable it. That's why we always read `SMAppService.mainApp.status`
/// instead of caching our own bool: the user can flip it from outside.
///
/// **Xcode caveat:** registering only sticks for an app living in a stable
/// location — typically `/Applications`. Running from Xcode's DerivedData
/// usually throws (or registers a path that stops existing on the next
/// build). `lastError` captures that so the UI can stay honest rather than
/// showing a toggle that silently does nothing.
@MainActor
@Observable
final class LaunchAtLogin {

    /// True when macOS currently has us registered as a login item.
    /// Read fresh from `SMAppService` rather than persisted locally — the
    /// user can change this in System Settings behind our back.
    private(set) var isEnabled: Bool

    /// Set when the most recent register/unregister failed. Cleared on the
    /// next successful call. Mostly non-nil only in dev builds (see above).
    private(set) var lastError: String?

    init() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Re-read the system's view of our registration. Call when the popover
    /// opens so the toggle reflects changes made in System Settings.
    func refresh() {
        isEnabled = SMAppService.mainApp.status == .enabled
    }

    /// Register or unregister as a login item. No-ops on redundant calls
    /// (`SMAppService` throws if you register something already registered).
    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
        // Trust the system over our intent — if the call silently didn't
        // take effect, the toggle should snap back rather than lie.
        refresh()
    }
}
