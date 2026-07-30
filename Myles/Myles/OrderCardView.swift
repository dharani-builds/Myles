import SwiftUI

/// The orders section of the popover: header + stacked order rows with
/// dividers between them.
///
/// This intentionally does NOT provide its own background/shadow/corner-radius
/// — those live on the shared orders-container in `ContentView` so the same
/// card wraps every orders state (loading / empty / loaded / error) plus the
/// footer as one cohesive surface.
///
/// Matches the Figma "multiple orders" case (node 70:430):
///   • Header: solid divider (`border/subtle`) below
///   • Between rows: dashed divider (`border/default`)
struct OrderCardView: View {
    let orders: [Order]

    /// Passed through to each row — see `OrderRowView.SecondaryLineStyle`.
    /// Temporary, for the layout comparison.
    var secondaryLineStyle: OrderRowView.SecondaryLineStyle = .swapWhenEnRoute

    var body: some View {
        VStack(spacing: 0) {
            header
            solidDivider
            content
        }
    }

    private var header: some View {
        HStack {
            Text("Your Orders")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(Color.textSecondary)
                .frame(height: 20) // match Figma lineHeightPx
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var content: some View {
        VStack(spacing: 20) {
            ForEach(Array(orders.enumerated()), id: \.element.id) { index, order in
                OrderRowView(order: order, secondaryLineStyle: secondaryLineStyle)
                if index < orders.count - 1 {
                    DashedDivider()
                }
            }
        }
        .padding(16)
    }

    // Solid header/content divider — thin, subtle
    private var solidDivider: some View {
        Rectangle()
            .fill(Color.borderSubtle)
            .frame(height: 0.5)
    }
}

// MARK: - Dashed divider between rows

/// Thin dashed horizontal line used between order rows.
/// Matches Figma's LINE element with `border/default` stroke.
private struct DashedDivider: View {
    var body: some View {
        GeometryReader { geo in
            Path { path in
                path.move(to: .zero)
                path.addLine(to: CGPoint(x: geo.size.width, y: 0))
            }
            .stroke(
                Color.borderStrong,
                style: StrokeStyle(lineWidth: 0.5, dash: [4, 4])
            )
        }
        .frame(height: 0.5)
    }
}

// MARK: - Secondary-line comparison previews
//
// TEMPORARY. Two candidate treatments for the partner-detail line, rendered
// with the same real strings from the 2026-07-27 Instamart capture so the
// only variable is layout. Each preview shows two rows: the order before it
// leaves the store (no partner detail yet) and the same order en route.
//
// Option A — three lines: items / headline / partner. The partner detail is
// always visible, at the cost of a permanently taller row.
//
// Option B — one secondary slot that swaps: items before dispatch, partner
// detail once en route. Row height matches Food; the trade is that what
// was ordered stops being visible in the second half of the delivery.
//
// Delete both of these, `secondaryLineStyle`, and the losing branch once
// one is chosen.

private func comparisonCard(_ style: OrderRowView.SecondaryLineStyle) -> some View {
    OrderCardView(orders: Fixtures.instamartStages, secondaryLineStyle: style)
        .background(Color.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .frame(width: 350)
        .padding(20)
}

#Preview("Secondary line · A — three lines") {
    comparisonCard(.threeLine)
}

#Preview("Secondary line · B — swap when en route") {
    comparisonCard(.swapWhenEnRoute)
}
