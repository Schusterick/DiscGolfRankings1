import Foundation

// MARK: - Firebase Cloud Functions Client
//
// BACKEND SETUP REQUIRED — deploy these to your Firebase project:
//   firebase init functions  (choose TypeScript or JavaScript)
//   firebase deploy --only functions
//
// Example Node.js Cloud Function (functions/index.js):
// ─────────────────────────────────────────────────────
// const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);
//
// exports.createPaymentIntent = functions.https.onCall(async (data, context) => {
//   const { amount, clubId, connectedAccountId } = data;
//   const platformFee = Math.round(amount * 0.10);
//   const intent = await stripe.paymentIntents.create({
//     amount,
//     currency: 'usd',
//     application_fee_amount: platformFee,
//     transfer_data: { destination: connectedAccountId },
//   });
//   return { clientSecret: intent.client_secret };
// });
//
// exports.createConnectAccount = functions.https.onCall(async (data, context) => {
//   const account = await stripe.accounts.create({ type: 'express', email: data.email });
//   return { accountId: account.id };
// });
//
// exports.getConnectAccountLink = functions.https.onCall(async (data, context) => {
//   const link = await stripe.accountLinks.create({
//     account: data.accountId,
//     refresh_url: data.refreshURL,
//     return_url:  data.returnURL,
//     type: 'account_onboarding',
//   });
//   return { url: link.url };
// });
// ─────────────────────────────────────────────────────
//
// TODO: Replace the placeholder URL below with your real Firebase project URL.
// Format: "https://us-central1-YOUR_PROJECT_ID.cloudfunctions.net"

private let cloudFunctionsBaseURL = "https://us-central1-TODO_REPLACE_PROJECT_ID.cloudfunctions.net"

// MARK: - CloudFunctions

enum CloudFunctions {

    // MARK: Create Payment Intent
    /// Creates a Stripe PaymentIntent for a paid club membership.
    /// - Returns: `clientSecret` — pass this to Stripe's PaymentSheet to complete the charge.
    static func createPaymentIntent(
        amount: Int,               // cents  (e.g. $10.00 → 1000)
        clubId: String,
        connectedAccountId: String // club admin's Stripe Connect account ID
    ) async throws -> String {
        // TODO: Uncomment when Cloud Function is deployed:
        // let url = URL(string: "\(cloudFunctionsBaseURL)/createPaymentIntent")!
        // var req  = URLRequest(url: url)
        // req.httpMethod = "POST"
        // req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // req.httpBody = try JSONSerialization.data(withJSONObject: [
        //     "amount": amount, "clubId": clubId, "connectedAccountId": connectedAccountId
        // ])
        // let (data, _) = try await URLSession.shared.data(for: req)
        // let json      = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        // return json["clientSecret"] as! String

        print("[CloudFunctions] createPaymentIntent  amount=\(amount)¢  club=\(clubId)")
        try await Task.sleep(nanoseconds: 800_000_000) // simulate latency
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(24)
        return "pi_mock_\(id)_secret_mock"
    }

    // MARK: Create Connect Account
    /// Creates a Stripe Connect Express account for a club admin so they can receive payouts.
    /// - Returns: Stripe account ID (e.g. `"acct_1AbcDef…"`)
    static func createConnectAccount(
        email: String,
        clubId: String
    ) async throws -> String {
        // TODO: Uncomment when Cloud Function is deployed:
        // let url = URL(string: "\(cloudFunctionsBaseURL)/createConnectAccount")!
        // ... (same URLSession pattern)
        // return json["accountId"] as! String

        print("[CloudFunctions] createConnectAccount  email=\(email)  club=\(clubId)")
        try await Task.sleep(nanoseconds: 500_000_000)
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(16)
        return "acct_mock_\(id)"
    }

    // MARK: Get Connect Account Onboarding Link
    /// Returns a one-time Stripe Connect onboarding URL for the admin to link their bank account.
    static func getConnectAccountLink(
        accountId:  String,
        clubId:     String,
        returnURL:  String = "discgolfranks://stripe-return",
        refreshURL: String = "discgolfranks://stripe-refresh"
    ) async throws -> URL {
        // TODO: Uncomment when Cloud Function is deployed:
        // let url = URL(string: "\(cloudFunctionsBaseURL)/getConnectAccountLink")!
        // ... (same URLSession pattern)
        // return URL(string: json["url"] as! String)!

        print("[CloudFunctions] getConnectAccountLink  accountId=\(accountId)")
        try await Task.sleep(nanoseconds: 500_000_000)
        // Mock: Stripe's test onboarding page
        return URL(string: "https://connect.stripe.com/setup/e/mock_\(accountId)")!
    }
}
