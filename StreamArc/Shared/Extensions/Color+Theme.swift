import SwiftUI

extension Color {
    // Background layers
    static let saBackground  = Color(hex: "#0A0A0F")
    static let saSurface     = Color(hex: "#141420")
    static let saCard        = Color(hex: "#1C1C2E")

    // Brand accent (Apple-style indigo/purple)
    static let saAccent      = Color(hex: "#5E5CE6")

    // Text
    static let saTextPrimary   = Color.white
    static let saTextSecondary = Color(hex: "#8E8E9A")

    // Status
    static let saSuccess = Color.green
    static let saError   = Color(hex: "#FF453A")

    // Convenience initialiser for hex strings
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
