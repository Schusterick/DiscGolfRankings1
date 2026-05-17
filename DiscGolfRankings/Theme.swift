import SwiftUI

// MARK: - App Color Palette

enum Theme {
    static let background    = Color(hex: "1A1A2E")
    static let card          = Color(hex: "16213E")
    static let cardAlt       = Color(hex: "1E2A45")
    static let divider       = Color(hex: "2A3A5C")
    static let accent        = Color(hex: "E94560")
    static let gold          = Color(hex: "F5A623")
    static let success       = Color(hex: "4CAF50")
    static let textPrimary   = Color.white
    static let textSecondary = Color(hex: "A0A0B0")

    static let homeGradient = LinearGradient(
        colors: [Color(hex: "1A1A2E"), Color(hex: "0F3460")],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}

// MARK: - Hex Color Init

extension Color {
    init(hex: String) {
        var h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        var int: UInt64 = 0
        Scanner(string: h).scanHexInt64(&int)
        self.init(
            red:   Double((int >> 16) & 0xFF) / 255,
            green: Double((int >> 8)  & 0xFF) / 255,
            blue:  Double(int         & 0xFF) / 255
        )
    }
}

// MARK: - View Modifiers

extension View {
    /// Applies the standard dark nav-bar appearance.
    func darkNavBar() -> some View {
        self
            .toolbarBackground(Theme.card, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
    }

    /// Hides the system List background and applies the app background.
    func darkListStyle() -> some View {
        self
            .scrollContentBackground(.hidden)
            .background(Theme.background)
    }
}
