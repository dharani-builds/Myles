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

    var body: some View {
        HStack(alignment: .center, spacing: 24) {
            leftColumn
                .frame(maxWidth: .infinity, alignment: .leading)
            ETABadge(minutes: order.eta, platform: order.platform)
        }
    }

    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(order.context)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundStyle(Color.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(height: 13) // 1.2× line height ratio (Figma spec was 10pt/12pt)
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
            Text(minutes.map(String.init) ?? "—")
                .font(.system(size: 20, weight: .bold))
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
    let progress: ProgressStage

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.borderSubtle)
                Capsule()
                    .fill(Color.swiggy500)
                    .frame(width: geo.size.width * progress.fraction)
            }
        }
        .frame(height: 6)
    }
}
