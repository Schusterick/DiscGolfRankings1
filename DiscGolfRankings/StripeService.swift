import Foundation

// MARK: - StripeService
//
// HOW TO ADD THE STRIPE SDK (required before going live):
// ────────────────────────────────────────────────────────
// 1. Xcode → File → Add Package Dependencies
// 2. URL: https://github.com/stripe/stripe-ios
// 3. Select products: Stripe, StripePaymentSheet
// 4. After install, uncomment the SDK lines marked TODO below
// ────────────────────────────────────────────────────────
//
// TODO: After adding Stripe SDK via SPM, add these imports:
// import Stripe
// import StripePaymentSheet

@MainActor
final class StripeService: ObservableObject {
    static let shared = StripeService()

    @Published var isLoading    = false
    @Published var errorMessage: String?

    // MARK: Configure
    /// Call once at app launch (AppEntry.swift) to initialize the Stripe SDK.
    func configure() {
        // TODO: Uncomment once Stripe SDK is added:
        // STPAPIClient.shared.publishableKey = Config.stripePublishableKey
        print("[StripeService] configure() — key prefix: \(Config.stripePublishableKey.prefix(20))…")
        print("[StripeService] NOTE: Add Stripe SDK via SPM to enable real payments.")
    }

    // MARK: Prepare Payment Sheet
    /// Fetches a PaymentIntent client secret from the backend.
    /// Use the returned secret to present Stripe's PaymentSheet.
    ///
    /// TODO: Once Stripe SDK is added, replace MockCardPaymentView with:
    ///
    ///   var config = PaymentSheet.Configuration()
    ///   config.merchantDisplayName = Config.appDisplayName
    ///   config.applePay = .init(
    ///       merchantId: "merchant.com.discgolfranks",  // TODO: register in Apple Dev Portal
    ///       merchantCountryCode: "US"
    ///   )
    ///   let sheet = PaymentSheet(paymentIntentClientSecret: clientSecret, configuration: config)
    ///   sheet.present(from: viewController) { result in
    ///       switch result {
    ///       case .completed:        // ✅ payment succeeded — create membership
    ///       case .canceled:         // user closed the sheet
    ///       case .failed(let err):  // show error
    ///       }
    ///   }
    func preparePaymentSheet(
        amount: Int,               // cents
        clubId: String,
        connectedAccountId: String
    ) async throws -> String {     // clientSecret
        isLoading = true
        defer { isLoading = false }
        return try await CloudFunctions.createPaymentIntent(
            amount: amount,
            clubId: clubId,
            connectedAccountId: connectedAccountId
        )
    }
}
