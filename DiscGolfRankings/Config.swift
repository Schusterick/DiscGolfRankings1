import Foundation

// MARK: - App Configuration
// The publishable key (pk_live_...) is safe to include in the iOS app.
// NEVER put the secret key (sk_live_...) here — that belongs on your backend only.

enum Config {
    /// Stripe publishable key — public, safe to ship in the app bundle
    static let stripePublishableKey = "pk_live_51TXBVtEHuqAQDa5AoF5kCNEUvbcMyIRCuIMJQJPm6qMP7RF6U7l9eaRtqSJW1hDENJ099LiKShQi9eH9VC3ZP8H800PD7jtcZd"

    /// Percentage the platform takes on every membership payment (10%)
    static let stripePlatformFee: Double = 0.10

    /// Displayed in Stripe's payment UI
    static let appDisplayName = "DiscGolfRankings"
}
