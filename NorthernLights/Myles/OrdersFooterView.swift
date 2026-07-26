import SwiftUI
import AppKit

/// Bottom bar of the orders popover.
///
/// **Left:** live countdown to the next automatic refresh — reads timing
/// state directly off `OrdersPoller`.
/// **Right:** "More" menu (native `Menu`) with feedback / log out / quit.
///
/// The countdown ticks visibly every second via `TimelineView(.periodic)`.
/// Copy rules (see the polling spec):
///   • Poll in flight, never yet completed  → "Checking…"
///   • Poll in flight, has completed before → "Updating…"
///   • Remaining ≥ 60s AND interval > 60s   → "Next update in {N} min"
///   • Anything else                        → "Next update in {N}s"
struct OrdersFooterView: View {
    @Environment(OrdersPoller.self) private var poller
    @Environment(AuthState.self) private var authState

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            TimelineView(.periodic(from: .now, by: 1.0)) { context in
                // No content transition / animation on this text — the
                // countdown should be the calmest thing on screen. Digit
                // changes happen instantly, not with a bounce or slide.
                Text(copyForTick(now: context.date))
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            MoreMenu(
                openFeedback: {
                    if let url = URL(string: "https://x.com/Dharani_design") {
                        NSWorkspace.shared.open(url)
                    }
                },
                logOut: { authState.signOut() },
                quitApp: { NSApp.terminate(nil) }
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private func copyForTick(now: Date) -> String {
        if poller.isPolling {
            return poller.hasEverPolled ? "Updating…" : "Checking…"
        }
        guard let nextAt = poller.nextPollAt else {
            return poller.hasEverPolled ? "Updating…" : "Checking…"
        }
        let remaining = Int(nextAt.timeIntervalSince(now).rounded())
        if remaining <= 0 {
            return "Updating…"
        }
        // Only use minutes format when the interval was actually long enough
        // to spend time above 60s. A 60s interval stays in seconds throughout.
        let intervalWasLong = poller.currentIntervalSeconds > 60
        if intervalWasLong && remaining >= 60 {
            let minutes = remaining / 60
            return "Next update in \(minutes)m"
        }
        return "Next update in \(remaining)s"
    }
}

// MARK: - More menu
//
// Native SwiftUI `Menu` — renders as a real NSMenu on macOS, so the dropdown
// look (icon column, section dividers, ⌘Q keyboard chip) is provided by the
// system. We just declare the items.
//
// Label is a "More ⌄" pill button matching Figma node 160:717:
//   • Rounded (100 corner radius = fully-round ends)
//   • surfaceCard background with borderSubtle stroke
//   • SF Pro Medium 12, textTertiary color

private struct MoreMenu: View {
    let openFeedback: () -> Void
    let logOut: () -> Void
    let quitApp: () -> Void

    var body: some View {
        Menu {
            Section {
                Button(action: openFeedback) {
                    Label("Have feedback? I'd love to hear it.", systemImage: "heart")
                }
                Button(action: logOut) {
                    Label("Log out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
            Section {
                Button(action: quitApp) {
                    Label("Quit Myles", systemImage: "power")
                }
                .keyboardShortcut("q", modifiers: .command)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color.textTertiary)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
    }
}

// MARK: - Previews

#Preview("Footer · idle 5 min") {
    OrdersFooterView()
        .environment(AuthState.previewAuthenticated)
        .environment(OrdersPoller.previewIdle(intervalSeconds: 300))
        .frame(width: 350)
        .background(Color.surfaceBackground)
}

#Preview("Footer · idle 60s") {
    OrdersFooterView()
        .environment(AuthState.previewAuthenticated)
        .environment(OrdersPoller.previewIdle(intervalSeconds: 60))
        .frame(width: 350)
        .background(Color.surfaceBackground)
}
