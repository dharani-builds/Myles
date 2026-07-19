//
//  ContentView.swift
//  NorthernLights
//
//  Created by Dharanitharan R on 08/07/26.
//

import SwiftUI
import AppKit

/// Root view for the menu bar popover.
///
/// Two-level branching:
///   1. `AuthState` — is the user signed in?
///   2. `OrdersState` — if signed in, what's the order fetch showing?
///
/// The orders branch (loading / empty / loaded / error) is wrapped in a
/// shared card container with the footer at the bottom. Auth screens keep
/// their own self-contained styling — no footer, since there's nothing to
/// refresh yet.
struct ContentView: View {
    @Environment(AuthState.self) private var authState
    @Environment(OrdersState.self) private var ordersState

    var body: some View {
        switch authState.status {
        case .idle, .authorizing, .error:
            // One screen handles all three auth states inline — the CTA button
            // reflects the state (label, spinner, disabled), and any error copy
            // shows above it. No dedicated "auth loading" or "auth error" screen.
            LoginView()
        case .authenticated:
            ordersScreen
        }
    }

    /// Shared card that wraps whichever orders-state view is active + the footer.
    private var ordersScreen: some View {
        VStack(spacing: 0) {
            stateContent
            footerDivider
            OrdersFooterView()
        }
        .background(Color.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 2, x: 1, y: 2)
        .frame(width: 350)
    }

    @ViewBuilder
    private var stateContent: some View {
        switch ordersState.status {
        case .loading:
            OrdersLoadingView()
        case .empty:
            EmptyOrdersView()
        case .loaded(let orders):
            OrderCardView(orders: orders)
        case .error:
            // Same screen structure for both error variants — just different
            // title copy. `hadOrdersAtErrorStart` (from OrdersState) tells us
            // whether the user was previously watching an active order.
            OrdersErrorContentView(
                title: ordersState.hadOrdersAtErrorStart
                    ? "Something went wrong"
                    : "Couldn't fetch orders"
            )
        }
    }

    /// Thin divider separating the state content from the footer.
    private var footerDivider: some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 0.5)
    }
}

// MARK: - Login (all pre-auth states)
//
// One screen handles four auth situations, differing only in the CTA button
// and a small context line above it:
//   1. Fresh (.idle, no expired flag)  → "Log in with Swiggy"
//   2. Session expired (.idle, flag)   → "Log in again" + "Your session has expired"
//   3. In flight (.authorizing)        → spinner + "Signing in…", button disabled
//   4. Sign-in failed (.error)         → "Try again" + inline error message
//
// Frame matches Figma node 160:804: 350 wide, header + illustration (161×132)
// + orange CTA (44 tall, corner radius 8, swiggy500), no footer.

private struct LoginView: View {
    @Environment(AuthState.self) private var authState

    var body: some View {
        VStack(spacing: 0) {
            SharedHeader()
            SharedSolidDivider()
            VStack(spacing: 16) {
                // Pointer for the fresh invite; sad illustration for the
                // "something's up" states (expired session, sign-in error) so
                // the mood matches the message. Each asset has a different
                // natural aspect ratio — width tracks the illustration so it
                // fills the same visual weight (~132 tall) in both cases.
                Image(illustration.name)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: illustration.width, height: 132)

                // Optional context line — session expired, or sign-in error.
                // Absent for the fresh idle case and while authorizing.
                if let context = contextMessage {
                    Text(context)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.textTertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await authState.signIn() }
                } label: {
                    HStack(spacing: 8) {
                        if authState.status == .authorizing {
                            ProgressView()
                                .controlSize(.small)
                                .tint(Color.brandSwiggyOnPrimary)
                        }
                        Text(ctaLabel)
                            .font(.system(size: 14, weight: .bold))
                            .tracking(-0.14)  // Figma letter-spacing
                            .foregroundStyle(Color.brandSwiggyOnPrimary)
                            .frame(height: 20)  // Figma lineHeightPx
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(Color.swiggy500)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(authState.status == .authorizing)
                .opacity(authState.status == .authorizing ? 0.85 : 1.0)
            }
            .padding(16)
        }
        .background(Color.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 2, x: 1, y: 2)
        .frame(width: 350)
    }

    // MARK: - Copy derivation

    private var ctaLabel: String {
        switch authState.status {
        case .authorizing:      return "Signing in…"
        case .error:            return "Try again"
        case .idle:
            return authState.justExpiredSessionMessageShown
                ? "Log in again"
                : "Log in with Swiggy"
        case .authenticated:    return "Log in with Swiggy"  // unreachable in this view
        }
    }

    private var contextMessage: String? {
        if case .error(let msg) = authState.status {
            return msg
        }
        if authState.justExpiredSessionMessageShown {
            return "Your Swiggy session has expired"
        }
        return nil
    }

    /// Fresh login gets the delivery-boy-pointing-down invite. Error and
    /// session-expired states swap in the sad illustration so it doesn't
    /// feel oddly cheerful over an error message. Widths mirror how each
    /// asset is sized in its home screen (login 161, error 198), so the
    /// swap keeps the same visual weight (~132 tall).
    private var illustration: (name: String, width: CGFloat) {
        switch authState.status {
        case .error:
            return ("ErrorIllustration", 198)
        case .idle where authState.justExpiredSessionMessageShown:
            return ("ErrorIllustration", 198)
        default:
            return ("LoginIllustration", 161)
        }
    }
}

// MARK: - Orders: loading (placeholder — pending design)

private struct OrdersLoadingView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(0.8)
            Text("Checking for orders…")
                .font(.system(size: 11, weight: .regular))
                .foregroundStyle(Color.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(32)
    }
}

// MARK: - Empty state (Figma 160:709)

/// Matches Figma node 160:709 (dark-mode spec):
///   • Header: "Your Orders" + solid divider (same as the loaded state)
///   • Content: illustration (233×132) + "No Active orders" title, centered
///     vertically & horizontally, item spacing 12, padding 16 all sides.
private struct EmptyOrdersView: View {
    var body: some View {
        VStack(spacing: 0) {
            SharedHeader()
            SharedSolidDivider()
            VStack(spacing: 12) {
                Image("EmptyStateIllustration")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 233, height: 132)
                Text("No Active orders")
                    .font(.system(size: 18, weight: .bold))
                    .tracking(-0.18)  // Figma letter-spacing
                    .foregroundStyle(Color.textSecondary)
                    .frame(height: 24)  // Figma lineHeightPx
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        }
    }
}

// MARK: - Error content (shared between "cold" + "mid-order" variants)
//
// Same illustration + title + "Help me fix it" link.
// Titles differ per Figma:
//   • Cold error (never had orders):   "Couldn't fetch orders"     (160:812)
//   • Mid-order error (had an order):  "Something went wrong"      (168:923)
//
// "Help me fix it" opens the user's Twitter as the informal feedback channel,
// same URL as the More menu's feedback link.

private struct OrdersErrorContentView: View {
    let title: String

    private var feedbackURL: URL? {
        URL(string: "https://x.com/Dharani_design")
    }

    var body: some View {
        VStack(spacing: 0) {
            SharedHeader()
            SharedSolidDivider()
            VStack(spacing: 12) {
                Image("ErrorIllustration")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 198, height: 132)
                VStack(spacing: 8) {
                    Text(title)
                        .font(.system(size: 16, weight: .bold))
                        .tracking(-0.16)
                        .foregroundStyle(Color.textSecondary)
                        .frame(height: 24)
                    HStack(spacing: 6) {
                        Text("Help me fix it")
                            .font(.system(size: 14, weight: .medium))
                            .tracking(-0.14)
                            .foregroundStyle(Color.textLink)
                            .frame(height: 20)
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(Color.textLink)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        if let url = feedbackURL {
                            NSWorkspace.shared.open(url)
                        }
                    }
                }
                .frame(width: 183)
            }
            .frame(maxWidth: .infinity)
            .padding(16)
        }
    }
}

// MARK: - Shared header + divider
//
// The "Your Orders" bar + subtle bottom divider used across empty, loaded,
// login, and error screens. Kept here (not per-view) so the styling stays
// consistent across all popover states.

private struct SharedHeader: View {
    var body: some View {
        HStack {
            Text("Your Orders")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .frame(height: 20)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct SharedSolidDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 0.5)
    }
}

// MARK: - Previews (fixture-driven, no live network)
//
// All auth previews use explicit factories (previewSignedOut / previewAuthorizing
// / etc.) so they force a specific status regardless of what's in Keychain —
// otherwise the preview canvas would show "authenticated" whenever the dev has
// a live token stored, which defeats the purpose of testing signed-out screens.

#Preview("Auth · fresh login") {
    ContentView()
        .environment(AuthState.previewSignedOut)
        .environment(OrdersState())
        .environment(OrdersPoller.previewIdle())
}

#Preview("Auth · session expired") {
    ContentView()
        .environment(AuthState.previewSessionExpired)
        .environment(OrdersState())
        .environment(OrdersPoller.previewIdle())
}

#Preview("Auth · signing in") {
    ContentView()
        .environment(AuthState.previewAuthorizing)
        .environment(OrdersState())
        .environment(OrdersPoller.previewIdle())
}

#Preview("Auth · sign-in failed") {
    ContentView()
        .environment(AuthState.previewAuthError)
        .environment(OrdersState())
        .environment(OrdersPoller.previewIdle())
}

#Preview("Orders · loading") {
    ContentView()
        .environment(AuthState.previewAuthenticated)
        .environment(OrdersState(initial: .loading))
        .environment(OrdersPoller.previewIdle())
}

#Preview("Orders · empty") {
    ContentView()
        .environment(AuthState.previewAuthenticated)
        .environment(OrdersState(initial: .empty))
        .environment(OrdersPoller.previewIdle(intervalSeconds: 300))
}

#Preview("Orders · one order") {
    ContentView()
        .environment(AuthState.previewAuthenticated)
        .environment(OrdersState(initial: .loaded(Fixtures.singleOrder)))
        .environment(OrdersPoller.previewIdle(intervalSeconds: 45))
}

#Preview("Orders · many orders") {
    ContentView()
        .environment(AuthState.previewAuthenticated)
        .environment(OrdersState(initial: .loaded(Fixtures.mixedOrders)))
        .environment(OrdersPoller.previewIdle(intervalSeconds: 45))
}

#Preview("Orders · error (cold)") {
    ContentView()
        .environment(AuthState.previewAuthenticated)
        .environment(OrdersState.previewError(midOrder: false))
        .environment(OrdersPoller.previewIdle(intervalSeconds: 120))
}

#Preview("Orders · error (mid-order)") {
    ContentView()
        .environment(AuthState.previewAuthenticated)
        .environment(OrdersState.previewError(midOrder: true))
        .environment(OrdersPoller.previewIdle(intervalSeconds: 45))
}
