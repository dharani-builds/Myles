import SwiftUI
import AppKit

// MARK: - Helpers

private extension NSColor {
    /// Build an NSColor from a #RRGGBB hex string.
    convenience init(hex: String) {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var rgb: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&rgb)
        let r = CGFloat((rgb & 0xFF0000) >> 16) / 255.0
        let g = CGFloat((rgb & 0x00FF00) >> 8)  / 255.0
        let b = CGFloat(rgb  & 0x0000FF)        / 255.0
        self.init(red: r, green: g, blue: b, alpha: 1)
    }
}

extension Color {
    /// Build a SwiftUI Color that automatically swaps between light and dark macOS appearances.
    init(light: String, dark: String) {
        let nsColor = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(hex: isDark ? dark : light)
        }
        self.init(nsColor: nsColor)
    }
}

// MARK: - Primitives (from `NL — Primitives` in Figma)
// Raw tonal ramps. Prefer the semantic tokens below in views.

extension Color {

    // Slate (Radix) — the only ramp that actually inverts in dark mode
    static let slate0  = Color(light: "#FFFFFF", dark: "#111113")
    static let slate1  = Color(light: "#FCFCFD", dark: "#111113")
    static let slate2  = Color(light: "#F9F9FB", dark: "#18191B")
    static let slate3  = Color(light: "#EFF0F3", dark: "#212225")
    static let slate4  = Color(light: "#E7E8EC", dark: "#272A2D")
    static let slate5  = Color(light: "#E0E1E6", dark: "#2E3135")
    static let slate6  = Color(light: "#D8D9E0", dark: "#363A3F")
    static let slate7  = Color(light: "#CDCED7", dark: "#43484E")
    static let slate8  = Color(light: "#B9BBC6", dark: "#5A6169")
    static let slate9  = Color(light: "#8B8D98", dark: "#696E77")
    static let slate10 = Color(light: "#80828D", dark: "#777B84")
    static let slate11 = Color(light: "#60646C", dark: "#B0B4BA")
    static let slate12 = Color(light: "#1C2024", dark: "#EDEEF0")

    // Swiggy Orange — brand ramp, same in both modes
    static let swiggy50  = Color(light: "#FFF5F0", dark: "#FFF5F0")
    static let swiggy100 = Color(light: "#FFE7DB", dark: "#FFE7DB")
    static let swiggy200 = Color(light: "#FFCBB2", dark: "#FFCBB2")
    static let swiggy300 = Color(light: "#FFA880", dark: "#FFA880")
    static let swiggy400 = Color(light: "#FF864D", dark: "#FF864D")
    static let swiggy500 = Color(light: "#FF5200", dark: "#FF5200")
    static let swiggy600 = Color(light: "#D64500", dark: "#D64500")
    static let swiggy700 = Color(light: "#AD3800", dark: "#AD3800")
    static let swiggy800 = Color(light: "#852B00", dark: "#852B00")
    static let swiggy900 = Color(light: "#5C1E00", dark: "#5C1E00")

    // Instamart Blue — brand ramp, same in both modes
    static let instamart50  = Color(light: "#F0F5FF", dark: "#F0F5FF")
    static let instamart100 = Color(light: "#DBE7FF", dark: "#DBE7FF")
    static let instamart200 = Color(light: "#B2CBFF", dark: "#B2CBFF")
    static let instamart300 = Color(light: "#80A8FF", dark: "#80A8FF")
    static let instamart400 = Color(light: "#4D85FF", dark: "#4D85FF")
    static let instamart500 = Color(light: "#0051FF", dark: "#0051FF")
    static let instamart600 = Color(light: "#0044D6", dark: "#0044D6")
    static let instamart700 = Color(light: "#0037AD", dark: "#0037AD")
    static let instamart800 = Color(light: "#002A85", dark: "#002A85")
    static let instamart900 = Color(light: "#001D5C", dark: "#001D5C")

    // Status Green — utility ramp, same in both modes
    static let statusGreen50  = Color(light: "#F2FCF6", dark: "#F2FCF6")
    static let statusGreen100 = Color(light: "#E2F9EA", dark: "#E2F9EA")
    static let statusGreen200 = Color(light: "#C0F2D2", dark: "#C0F2D2")
    static let statusGreen300 = Color(light: "#8DE7AE", dark: "#8DE7AE")
    static let statusGreen400 = Color(light: "#4EDA81", dark: "#4EDA81")
    static let statusGreen500 = Color(light: "#25B159", dark: "#25B159")
    static let statusGreen600 = Color(light: "#1E8F48", dark: "#1E8F48")
    static let statusGreen700 = Color(light: "#187239", dark: "#187239")
    static let statusGreen800 = Color(light: "#12542A", dark: "#12542A")
    static let statusGreen900 = Color(light: "#0C3B1E", dark: "#0C3B1E")
}

// MARK: - Semantic Tokens (from `NL — Semantic` in Figma)
// Use these in views — they're the language the design speaks.

extension Color {

    // Brand · Swiggy
    static let brandSwiggyPrimary        = swiggy500
    static let brandSwiggyPrimaryHover   = swiggy600
    static let brandSwiggyPrimaryPressed = swiggy700
    static let brandSwiggySurface        = swiggy50
    // Fixed white — the brand orange doesn't invert in dark mode, so the text
    // on it shouldn't either. Using `textInverse`/`slate0` here flips to
    // near-black in dark mode and reads as haunting on the orange fill.
    static let brandSwiggyOnPrimary      = Color(light: "#FFFFFF", dark: "#FFFFFF")

    // Brand · Instamart
    static let brandInstamartPrimary        = instamart500
    static let brandInstamartPrimaryHover   = instamart600
    static let brandInstamartPrimaryPressed = instamart700
    static let brandInstamartSurface        = instamart50
    static let brandInstamartOnPrimary      = Color(light: "#FFFFFF", dark: "#FFFFFF")

    // Status
    static let statusSuccess        = statusGreen500
    static let statusSuccessSurface = statusGreen50
    static let statusSuccessStrong  = statusGreen700

    // Text
    static let textPrimary   = slate12
    static let textSecondary = slate11
    static let textTertiary  = slate10
    static let textDisabled  = slate9
    static let textInverse   = slate0
    /// Inline link color (e.g. "Help me fix it" in error screens). Same in
    /// light + dark for now; can specialise per-mode if we add more links.
    static let textLink      = Color(light: "#0579BC", dark: "#0579BC")

    // Surface
    static let surfaceBackground = slate0
    static let surfaceCard       = slate2
    static let surfaceRaised     = slate3
    static let surfaceSunken     = slate2

    // Border
    static let borderSubtle  = slate4
    static let borderDefault = slate5
    static let borderStrong  = slate6
}
