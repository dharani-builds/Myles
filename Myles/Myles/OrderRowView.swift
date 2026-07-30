import SwiftUI

/// One order row inside the popover card.
///
/// Matches the "order status" component in Figma exactly:
///   HStack (spacing 24, aligned center)
///     ├── left column [VStack, spacing 12]
///     │       ├── content group [VStack, spacing 2]
///     │       │       ├── context text  (10pt Regular, text/tertiary)
///     │       │       └── status text   (14pt Bold, kerning -0.14)
///     │       └── progress bar
///     └── ETA badge (62×60, gradient)
struct OrderRowView: View {
    let order: Order

    /// Hide the ETA badge when Swiggy explicitly stops estimating — that
    /// happens once the partner is standing at the user's door and the
    /// remaining time is meaningless. Detected via keyword match on the
    /// status text (Swiggy sends "Arrived at location") combined with a
    /// nil ETA, so a nil ETA from a mid-flight state (e.g. transient
    /// delivery-status fetch failure) still shows the badge with "—".
    /// When hidden, the left column expands to fill the row.
    private var showsETABadge: Bool {
        !(order.eta == nil && order.status.lowercased().contains("arrived"))
    }

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            leftColumn
                .frame(maxWidth: .infinity, alignment: .leading)
            if showsETABadge {
                ETABadge(minutes: order.eta, platform: order.platform)
                    .transition(.opacity.combined(with: .scale(scale: 0.85)))
            }
        }
        .animation(.spring(response: 0.5, dampingFraction: 0.85), value: showsETABadge)
    }

    /// The small line above the headline, which changes with the stage:
    /// what was ordered while it's still being put together, then the
    /// delivery-partner detail once it's moving.
    ///
    /// The reasoning: before dispatch nothing is happening yet, so the
    /// contents are the only useful thing to show. Once it's en route the
    /// live question is who has it and where they are, and the items stop
    /// earning the space. Because the headline changes at the same moment,
    /// the swap reads as the row entering a new state rather than as the
    /// items going missing.
    ///
    /// Food always falls through to `context` — its MCP exposes no partner
    /// info, so `partnerDetail` is nil there.
    private var topLine: String {
        if order.isEnRoute, let detail = order.partnerDetail {
            return detail
        }
        return order.context
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(topLine)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 14) // 1.2× line height ratio (Figma spec was 10pt/12pt)
                Text(order.status)
                    .font(.system(size: 15, weight: .bold))
                    .kerning(-0.15)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(2)
                    .lineSpacing(4)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ProgressBarView(progress: order.progress)
        }
    }
}

// MARK: - ETA badge

/// The gradient-filled rounded badge on the right of each order row.
/// Gradient stops hardcoded to match Figma exactly (deviates slightly from
/// the `statusGreen/*` and `instamart/*` token ramps — see design tokens
/// reconciliation note in project docs).
private struct ETABadge: View {
    let minutes: Int?
    let platform: OrderPlatform

    var body: some View {
        VStack(spacing: 0) {
            // Slot-machine reel — see RollingNumberReel below for how it works.
            // Nil ETA (rare — usually terminal state) falls back to a static
            // em-dash matched to the same viewport height so the badge layout
            // doesn't jump when a value arrives.
            if let m = minutes, m >= 0 {
                RollingNumberReel(value: m, maxValue: 99)
            } else {
                Text("—")
                    .font(.system(size: 20, weight: .bold))
                    .frame(height: RollingNumberReel.rowHeight)
            }
            Text("mins")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundStyle(.white)
        .frame(width: 60, height: 60)
        .background(gradient)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var gradient: LinearGradient {
        let stops: [Gradient.Stop] = {
            switch platform {
            case .food:
                // Figma food gradient — Frame 5 in "order status" (food variant)
                return [
                    .init(color: Color(nsColor: NSColor(red: 0.114, green: 0.606, blue: 0.294, alpha: 1)), location: 0.0),
                    .init(color: Color(nsColor: NSColor(red: 0.126, green: 0.594, blue: 0.298, alpha: 1)), location: 0.5),
                    .init(color: Color(nsColor: NSColor(red: 0.070, green: 0.330, blue: 0.165, alpha: 1)), location: 1.0)
                ]
            case .instamart:
                // Figma instamart gradient — Frame 6 in "order status" (instamart variant)
                return [
                    .init(color: Color(nsColor: NSColor(red: 0.000, green: 0.317, blue: 1.000, alpha: 1)), location: 0.0),
                    .init(color: Color(nsColor: NSColor(red: 0.000, green: 0.298, blue: 0.940, alpha: 1)), location: 0.568),
                    .init(color: Color(nsColor: NSColor(red: 0.000, green: 0.190, blue: 0.600, alpha: 1)), location: 1.0)
                ]
            }
        }()
        return LinearGradient(stops: stops, startPoint: .top, endPoint: .bottom)
    }
}

// MARK: - Progress bar

/// Thin pill-shaped progress bar. Always Swiggy-orange fill, regardless of platform.
/// Reserving orange for progress (and green/blue for badge) keeps the card from
/// reading as one-note in any single platform's color.
private struct ProgressBarView: View {
    /// Fraction 0.0 – 1.0. Spring-animated on change so every poll cycle
    /// slides the fill smoothly instead of snapping.
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.borderSubtle)
                Capsule()
                    .fill(Color.swiggy500)
                    .frame(width: geo.size.width * progress)
                    .animation(.spring(response: 0.7, dampingFraction: 0.9), value: progress)
            }
        }
        .frame(height: 6)
    }
}

// MARK: - Rolling number reel (slot-machine style)
//
// One tall VStack containing every possible value stacked vertically, clipped
// down to a single-row viewport. `.offset(y:)` picks which row is visible.
// When `value` changes, SwiftUI animates the offset with a spring — the reel
// physically scrolls, digits above and below get pulled through the viewport,
// same feel as an iOS picker wheel or a slot-machine drum settling.
//
// Trade-off: this creates `maxValue + 1` Text views up front (default 100).
// That's fine for a single badge in a menu bar — SwiftUI happily virtualizes
// the render — but it's why the reel is NOT arbitrary-range: keep maxValue
// sensible. Deliveries never exceed ~90min, so 99 is plenty of headroom.
private struct RollingNumberReel: View {
    let value: Int
    let maxValue: Int

    /// Viewport height = one row. Sized generously enough for a 20pt bold
    /// digit — the reel below scrolls at exactly this pitch.
    static let rowHeight: CGFloat = 24

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0...maxValue, id: \.self) { n in
                Text("\(n)")
                    .font(.system(size: 20, weight: .bold))
                    .frame(height: Self.rowHeight)
            }
        }
        // Reel is [0, 1, 2, ..., maxValue] from top to bottom. To show value V,
        // translate the reel UP by V rows so V lands at the viewport's top.
        // When V decreases (countdown tick), the offset becomes less negative,
        // the reel scrolls DOWN visually, the lower digit slides in from
        // above — matching an iOS picker scrolled toward smaller values.
        .offset(y: -CGFloat(value) * Self.rowHeight)
        // Spring keeps the motion mechanical-feeling: a bit of overshoot then
        // settles. `response` = how long the settle takes; `dampingFraction`
        // = how much bounce. Tuned so a 45s poll cycle doesn't visually
        // over-stay its welcome.
        .animation(.spring(response: 0.65, dampingFraction: 0.75), value: value)
        .frame(height: Self.rowHeight, alignment: .top)
        .clipped()
    }
}

