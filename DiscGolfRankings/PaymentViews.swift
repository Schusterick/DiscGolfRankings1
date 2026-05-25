import SwiftUI
import SafariServices

// MARK: - PaymentPreviewView
// Shown when a user taps "Pay & Join" on a paid club.
// Displays fee breakdown and offers Apple Pay or card entry.

struct PaymentPreviewView: View {
    let club: Club

    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var step: Step              = .preview
    @State private var tagNumber               = 0
    @State private var showApplePayAlert       = false

    enum Step { case preview, cardEntry, success }

    private var joinFee:      Double { club.joinFee ?? 0 }
    private var feeRate:      Double { club.effectivePlatformFeeRate }   // 0% during trial
    private var platformFee:  Double { joinFee * feeRate }
    private var clubReceives: Double { joinFee - platformFee }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                switch step {
                case .preview:
                    previewContent
                case .cardEntry:
                    MockCardPaymentView(
                        club: club,
                        amount: joinFee,
                        onSuccess: { tag in tagNumber = tag; step = .success },
                        onCancel:  { step = .preview }
                    )
                    .environmentObject(auth)
                case .success:
                    PaymentSuccessView(
                        clubName:  club.name,
                        tagNumber: tagNumber,
                        onDone:    { dismiss() }
                    )
                }
            }
        }
        .preferredColorScheme(.dark)
        .alert("Apple Pay", isPresented: $showApplePayAlert) {
            Button("Use Card Instead") { step = .cardEntry }
            Button("OK") { }
        } message: {
            Text("Apple Pay setup is in progress. Use card payment for now.")
        }
    }

    // MARK: Preview Content

    private var previewContent: some View {
        ScrollView {
            VStack(spacing: 28) {

                // Club logo placeholder
                ZStack {
                    Circle()
                        .fill(LinearGradient(colors: [Theme.accent, Theme.gold],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 88, height: 88)
                    Image(systemName: "figure.disc.sports")
                        .font(.system(size: 40))
                        .foregroundStyle(.white)
                }
                .shadow(color: Theme.accent.opacity(0.4), radius: 16)
                .padding(.top, 32)

                // Fee amount
                VStack(spacing: 8) {
                    Text(String(format: "$%.2f", joinFee))
                        .font(.system(size: 56, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("One-time fee to join \(club.name)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }

                // Fee breakdown — clubs always keep 100% under the flat-fee model
                VStack(spacing: 0) {
                    feeRow(icon: "building.2.fill",
                           label: "Club receives",
                           value: String(format: "$%.2f", clubReceives),
                           color: Theme.success)
                }
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.divider, lineWidth: 1))

                // Payment buttons
                VStack(spacing: 12) {
                    // Apple Pay
                    Button { showApplePayAlert = true } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "apple.logo").font(.headline)
                            Text("Pay with Apple Pay").font(.headline)
                        }
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14))
                    }

                    // Card payment
                    Button { step = .cardEntry } label: {
                        Label("Pay with Card", systemImage: "creditcard.fill")
                            .font(.headline)
                            .foregroundStyle(Theme.accent)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .overlay(RoundedRectangle(cornerRadius: 14)
                                .stroke(Theme.accent, lineWidth: 1.5))
                    }

                    Button { dismiss() } label: {
                        Text("Cancel")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.top, 4)
                }

                // Secure badge
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Theme.textSecondary)
                    Text("Secure payment powered by Stripe")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                .padding(.bottom, 32)
            }
            .padding(.horizontal, 28)
        }
        .navigationTitle("Join \(club.name)")
        .navigationBarTitleDisplayMode(.inline)
        .darkNavBar()
    }

    @ViewBuilder
    private func feeRow(icon: String, label: String, value: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(Theme.textSecondary)
                .font(.subheadline)
                .frame(width: 20)
            Text(label)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.bold())
                .foregroundStyle(color)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

// MARK: - MockCardPaymentView
// ─────────────────────────────────────────────────────────────────────────────
// TODO: Replace this entire view with Stripe's built-in PaymentSheet once the
//       Stripe SDK is added via Swift Package Manager.
//       See StripeService.swift for step-by-step integration instructions.
//       PaymentSheet handles PCI compliance, 3DS, Apple Pay, and Link automatically.
// ─────────────────────────────────────────────────────────────────────────────

struct MockCardPaymentView: View {
    let club:      Club
    let amount:    Double
    let onSuccess: (Int) -> Void   // called with assigned tag number
    let onCancel:  () -> Void

    @EnvironmentObject var auth: AuthService
    private let service = FirebaseService.shared

    @State private var cardNumber   = ""
    @State private var expiry       = ""
    @State private var cvc          = ""
    @State private var nameOnCard   = ""
    @State private var isProcessing = false
    @State private var errorMessage: String?

    private var formattedCard: String {
        let digits = String(cardNumber.filter(\.isNumber).prefix(16))
        return stride(from: 0, to: digits.count, by: 4)
            .map { i -> String in
                let start = digits.index(digits.startIndex, offsetBy: i)
                let end   = digits.index(start, offsetBy: min(4, digits.count - i))
                return String(digits[start..<end])
            }
            .joined(separator: " ")
    }

    private var isValid: Bool {
        cardNumber.filter(\.isNumber).count >= 16 &&
        expiry.filter(\.isNumber).count >= 4 &&
        cvc.filter(\.isNumber).count >= 3 &&
        !nameOnCard.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {

                // TODO: Remove this banner and the entire MockCardPaymentView once
                // Stripe SDK is integrated — PaymentSheet replaces this UI entirely
                HStack(spacing: 8) {
                    Image(systemName: "hammer.fill").font(.caption)
                    Text("MOCK UI — Replace with Stripe PaymentSheet")
                        .font(.caption.bold())
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.yellow)
                .clipShape(RoundedRectangle(cornerRadius: 10))

                // Amount
                VStack(spacing: 4) {
                    Text(String(format: "$%.2f", amount))
                        .font(.system(size: 42, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text(club.name)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }

                // Card preview
                cardPreview

                // Form fields
                VStack(spacing: 14) {
                    cardField("Card Number",
                              text: Binding(
                                get: { formattedCard },
                                set: { cardNumber = $0.filter(\.isNumber) }
                              ),
                              icon: "creditcard",
                              keyboard: .numberPad)
                    HStack(spacing: 12) {
                        cardField("MM / YY", text: $expiry,
                                  icon: "calendar", keyboard: .numberPad)
                        cardField("CVC", text: $cvc,
                                  icon: "lock", keyboard: .numberPad)
                    }
                    cardField("Name on Card", text: $nameOnCard,
                              icon: "person", keyboard: .alphabet)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }

                // Pay button
                Button { Task { await processPayment() } } label: {
                    Group {
                        if isProcessing {
                            HStack(spacing: 10) {
                                ProgressView().tint(.white)
                                Text("Processing…").foregroundStyle(.white).font(.headline)
                            }
                        } else {
                            Text(String(format: "Pay $%.2f", amount))
                                .font(.headline).foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(isValid ? Theme.accent : Theme.accent.opacity(0.4),
                                in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(!isValid || isProcessing)

                Button("Back") { onCancel() }
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.bottom, 24)
            }
            .padding()
        }
        .navigationTitle("Card Payment")
        .navigationBarTitleDisplayMode(.inline)
        .darkNavBar()
    }

    // Visual card preview
    private var cardPreview: some View {
        ZStack(alignment: .bottomLeading) {
            RoundedRectangle(cornerRadius: 16)
                .fill(LinearGradient(colors: [Theme.card, Color(hex: "1E2A45")],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(height: 90)
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.divider, lineWidth: 1))

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(formattedCard.isEmpty ? "•••• •••• •••• ••••" : formattedCard)
                        .font(.system(size: 15, weight: .medium, design: .monospaced))
                        .foregroundStyle(cardNumber.isEmpty ? Theme.textSecondary : Theme.textPrimary)
                    Text(nameOnCard.isEmpty ? "YOUR NAME" : nameOnCard.uppercased())
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "creditcard.fill")
                    .font(.title2).foregroundStyle(Theme.gold)
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func cardField(_ placeholder: String, text: Binding<String>,
                           icon: String, keyboard: UIKeyboardType) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(Theme.textSecondary).frame(width: 18)
            TextField(placeholder, text: text)
                .foregroundStyle(Theme.textPrimary)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
        }
        .padding(14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.divider, lineWidth: 1))
    }

    private func processPayment() async {
        guard let uid    = auth.currentUser?.uid,
              let clubId = club.id else { return }
        let name  = auth.appUser?.displayName ?? auth.currentUser?.displayName ?? "Player"
        let email = auth.currentUser?.email ?? ""

        isProcessing = true
        errorMessage = nil

        do {
            // Step 1 — Get PaymentIntent client secret from backend
            // TODO: Use clientSecret with PaymentSheet instead of this mock flow.
            //       See StripeService.swift for the PaymentSheet integration code.
            let _ = try await CloudFunctions.createPaymentIntent(
                amount: Int(amount * 100),     // convert to cents
                clubId: clubId,
                connectedAccountId: club.stripeConnectedAccountId ?? "acct_mock"
            )

            // Step 2 — Create membership in Firestore
            try await service.joinClub(userId: uid, userFullName: name,
                                       clubId: clubId, userEmail: email)

            // Step 3 — Log payment record (0% platform fee while club is in free trial)
            try? await service.recordPayment(
                userId: uid,
                clubId: clubId,
                amount: amount,
                platformFee: amount * club.effectivePlatformFeeRate,
                stripePaymentIntentId: "pi_mock_\(UUID().uuidString.prefix(16))"
            )

            // Step 4 — Return the assigned tag number
            let membership = try? await service.fetchMembership(userId: uid, clubId: clubId)
            onSuccess(membership?.tagNumber ?? 1)

        } catch {
            errorMessage = "Payment failed: \(error.localizedDescription)"
        }

        isProcessing = false
    }
}

// MARK: - PaymentSuccessView

struct PaymentSuccessView: View {
    let clubName:  String
    let tagNumber: Int
    let onDone:    () -> Void

    @State private var checkScale:   CGFloat = 0.3
    @State private var checkOpacity: Double  = 0
    @State private var textOffset:   CGFloat = 24
    @State private var textOpacity:  Double  = 0

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Animated checkmark
            ZStack {
                Circle().fill(Theme.success.opacity(0.06)).frame(width: 180, height: 180)
                Circle().fill(Theme.success.opacity(0.10)).frame(width: 140, height: 140)
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 90))
                    .foregroundStyle(Theme.success)
                    .scaleEffect(checkScale)
                    .opacity(checkOpacity)
            }
            .padding(.bottom, 32)

            // Text
            VStack(spacing: 14) {
                Text("Welcome to \(clubName)!")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)

                HStack(spacing: 0) {
                    Text("You've been assigned ")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                    Text("tag #\(tagNumber)")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.gold)
                }
            }
            .offset(y: textOffset)
            .opacity(textOpacity)

            Spacer()

            // Buttons
            VStack(spacing: 12) {
                Button { onDone() } label: {
                    Label("View Leaderboard", systemImage: "list.number")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                Button { onDone() } label: {
                    Text("Done")
                        .font(.footnote).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 40)
            .offset(y: textOffset)
            .opacity(textOpacity)
        }
        .onAppear {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.6).delay(0.1)) {
                checkScale   = 1
                checkOpacity = 1
            }
            withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
                textOffset  = 0
                textOpacity = 1
            }
        }
    }
}

// MARK: - SafariView
// Used to open Stripe Connect onboarding URL inside the app.

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        let vc = SFSafariViewController(url: url)
        vc.preferredBarTintColor    = UIColor(Theme.background)
        vc.preferredControlTintColor = UIColor(Theme.accent)
        return vc
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
