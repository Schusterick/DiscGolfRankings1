import Foundation

// MARK: - App Configuration
// The publishable key (pk_live_...) is safe to include in the iOS app.
// NEVER put the secret key (sk_live_...) here — that belongs on your backend only.

enum Config {
    /// Stripe publishable key — public, safe to ship in the app bundle.
    static let stripePublishableKey = "pk_live_51TXBVtEHuqAQDa5AoF5kCNEUvbcMyIRCuIMJQJPm6qMP7RF6U7l9eaRtqSJW1hDENJ099LiKShQi9eH9VC3ZP8H800PD7jtcZd"

    /// Displayed in Stripe's payment UI.
    static let appDisplayName = "DiscGolfRankings"

    // MARK: - Flat-Fee Pricing Model

    /// Member-fee transactions are charged 100% to the club. DiscGolfRankings does
    /// NOT take a percentage cut — revenue comes entirely from the flat annual fee.
    /// Kept as a constant (set to 0) so existing Stripe Connect code still compiles.
    static let stripePlatformFee: Double = 0.0

    /// Annual subscription cost ($/year) every club pays AFTER their free trial.
    static let clubSubscriptionAnnualFee: Double = 50.0

    /// Length of the free trial every new club gets when they join the platform.
    /// 60 days.
    static let clubTrialDurationDays: Int = 60

    /// How many days before expiration to start showing the renewal warning banner.
    static let renewalWarningWindowDays: Int = 14
}
