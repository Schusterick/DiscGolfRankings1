import SwiftUI

// MARK: - ClubSubscriptionView
// Admin-facing screen showing the club's hybrid-pricing subscription status.
// • Trial: shows days remaining + a friendly explainer
// • Active: shows renewal date + cancel option
// • Expiring soon: prominent renew CTA
// • Expired/cancelled: red banner + renew CTA
//
// PRODUCTION TODO: replace `simulatePayment()` with a real Stripe Checkout flow
// (a Cloud Function that creates a Checkout session, then a webhook that calls
// `FirebaseService.activateClubSubscription` after `checkout.session.completed`).

struct ClubSubscriptionView: View {
    let club: Club

    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var current:        Club
    @State private var isProcessing    = false
    @State private var showCancelConfirm = false
    @State private var errorMsg:       String?

    init(club: Club) {
        self.club = club
        _current = State(initialValue: club)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        statusBanner
                        pricingCard
                        actions
                        valueProps
                        if let errorMsg {
                            Text(errorMsg).font(.caption).foregroundStyle(.red)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
            .confirmationDialog(
                "Cancel subscription?",
                isPresented: $showCancelConfirm,
                titleVisibility: .visible
            ) {
                Button("Cancel subscription", role: .destructive) {
                    Task { await cancel() }
                }
                Button("Keep subscription", role: .cancel) { }
            } message: {
                Text("Members can still see existing data, but you'll be blocked from creating new events or messaging members until you renew.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Status banner

    @ViewBuilder
    private var statusBanner: some View {
        let state = current.subscriptionState
        VStack(spacing: 8) {
            Image(systemName: bannerIcon(state))
                .font(.system(size: 36))
                .foregroundStyle(bannerColor(state))
            Text(bannerTitle(state))
                .font(.system(size: 22, weight: .black, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            Text(state.label)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(bannerColor(state).opacity(0.12), in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(bannerColor(state).opacity(0.4), lineWidth: 1))
    }

    private func bannerColor(_ s: Club.SubscriptionState) -> Color {
        switch s {
        case .trial:        return Theme.gold
        case .active:       return Theme.success
        case .expiringSoon: return Theme.accent
        case .expired,
             .cancelled:    return .red
        }
    }
    private func bannerIcon(_ s: Club.SubscriptionState) -> String {
        switch s {
        case .trial:        return "sparkles"
        case .active:       return "checkmark.seal.fill"
        case .expiringSoon: return "exclamationmark.triangle.fill"
        case .expired,
             .cancelled:    return "xmark.octagon.fill"
        }
    }
    private func bannerTitle(_ s: Club.SubscriptionState) -> String {
        switch s {
        case .trial:        return "Free Trial Active"
        case .active:       return "Subscription Active"
        case .expiringSoon: return "Renewal Due Soon"
        case .expired:      return "Subscription Expired"
        case .cancelled:    return "Subscription Cancelled"
        }
    }

    // MARK: Pricing card

    private var pricingCard: some View {
        VStack(spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text("$\(Int(Config.clubSubscriptionAnnualFee))")
                    .font(.system(size: 48, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.gold)
                Text("/ year")
                    .font(.headline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Text("Flat annual fee. Your club keeps 100% of every member payment — DiscGolfRankings takes zero percent.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Action buttons

    @ViewBuilder
    private var actions: some View {
        let state = current.subscriptionState
        VStack(spacing: 10) {
            switch state {
            case .trial:
                Button { Task { await simulatePayment() } } label: {
                    payLabel(text: "Upgrade Now — Keep My Club")
                }
                .disabled(isProcessing)
                Text("Pay anytime during your trial — your renewal still kicks in when the trial ends, so you don't lose any free time.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)

            case .active:
                Button(role: .destructive) { showCancelConfirm = true } label: {
                    Text("Cancel Subscription")
                        .font(.subheadline.bold())
                        .foregroundStyle(.red.opacity(0.85))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }

            case .expiringSoon:
                Button { Task { await simulatePayment() } } label: {
                    payLabel(text: "Renew Now — Avoid Service Loss")
                }
                .disabled(isProcessing)

            case .expired, .cancelled:
                Button { Task { await simulatePayment() } } label: {
                    payLabel(text: "Reactivate Subscription")
                }
                .disabled(isProcessing)
            }
        }
    }

    private func payLabel(text: String) -> some View {
        Group {
            if isProcessing {
                ProgressView().tint(.white)
            } else {
                Label(text, systemImage: "creditcard.fill")
                    .font(.headline).foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Value props

    private var valueProps: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What's included").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 10) {
                bullet("Unlimited members with bag-tag rankings")
                bullet("Host leagues and tournaments — auto-ranking redistribution")
                bullet("Member messaging + event RSVPs")
                bullet("Public club profile + shareable join link")
                bullet("Stripe Connect for collecting member fees")
            }
            .padding(14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }
    @ViewBuilder
    private func bullet(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(Theme.success)
            Text(text).font(.subheadline).foregroundStyle(Theme.textPrimary)
        }
    }

    // MARK: Actions

    /// Placeholder: in production this should open Stripe Checkout (NOT Connect).
    /// The Stripe Checkout session is created server-side via a Cloud Function;
    /// after `checkout.session.completed` webhook, the backend calls
    /// `FirebaseService.activateClubSubscription(clubId:)`. For now we simulate.
    private func simulatePayment() async {
        guard let clubId = current.id else { return }
        isProcessing = true; errorMsg = nil
        do {
            // TODO: replace with real Stripe Checkout flow via CloudFunctions
            try await Task.sleep(nanoseconds: 800_000_000)
            try await service.activateClubSubscription(clubId: clubId)
            if let fresh = try? await service.fetchClub(id: clubId) {
                current = fresh
            }
        } catch {
            errorMsg = error.localizedDescription
        }
        isProcessing = false
    }

    private func cancel() async {
        guard let clubId = current.id else { return }
        isProcessing = true; errorMsg = nil
        do {
            try await service.cancelClubSubscription(clubId: clubId)
            if let fresh = try? await service.fetchClub(id: clubId) {
                current = fresh
            }
        } catch {
            errorMsg = error.localizedDescription
        }
        isProcessing = false
    }
}

// MARK: - SubscriptionStatusBanner
// Small inline banner you can drop into any admin screen to nudge action.

struct SubscriptionStatusBanner: View {
    let club: Club
    let onTap: () -> Void

    var body: some View {
        let state = club.subscriptionState
        switch state {
        case .active:
            EmptyView()                                  // no banner when healthy
        case .trial(let days) where days > 30:
            EmptyView()                                  // hide if plenty of trial left
        default:
            Button { onTap() } label: {
                HStack(spacing: 10) {
                    Image(systemName: icon(state))
                        .foregroundStyle(color(state))
                    Text(message(state))
                        .font(.caption.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                .padding(.horizontal, 12).padding(.vertical, 10)
                .background(color(state).opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(color(state).opacity(0.5), lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
    }

    private func icon(_ s: Club.SubscriptionState) -> String {
        switch s {
        case .trial:        return "sparkles"
        case .expiringSoon: return "exclamationmark.triangle.fill"
        case .expired,
             .cancelled:    return "xmark.octagon.fill"
        default:            return "info.circle"
        }
    }
    private func color(_ s: Club.SubscriptionState) -> Color {
        switch s {
        case .trial:        return Theme.gold
        case .expiringSoon: return Theme.accent
        case .expired,
             .cancelled:    return .red
        default:            return Theme.textSecondary
        }
    }
    private func message(_ s: Club.SubscriptionState) -> String {
        switch s {
        case .trial(let d):         return "Free trial: \(d) day\(d == 1 ? "" : "s") left. Tap to upgrade."
        case .expiringSoon(let d):  return "Subscription renews in \(d) day\(d == 1 ? "" : "s"). Tap to manage."
        case .expired:              return "Subscription expired. Tap to renew."
        case .cancelled:            return "Subscription cancelled. Tap to reactivate."
        case .active:               return ""
        }
    }
}
