import SwiftUI

/// The popover card. Header + stacked order rows with dividers between them.
///
/// Matches the Figma "multiple orders" case (node 70:430):
///   • 350pt wide, 12pt corner radius
///   • White background, 0.5pt subtle inside border
///   • Drop shadow: rgba(0,0,0,0.08), offset (1,2), radius 2
///   • Header: solid divider (`border/subtle`) below
///   • Between rows: dashed divider (`border/default`)
struct OrderCardView: View {
    let orders: [Order]

    var body: some View {
        VStack(spacing: 0) {
            header
            solidDivider
            content
        }
        .background(Color.surfaceBackground)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.08), radius: 2, x: 1, y: 2)
        .frame(width: 350)
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
                OrderRowView(order: order)
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
