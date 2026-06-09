import SwiftUI

// MARK: - ClubSubscriptionView
// Admin-facing screen showing the club's "Club Dues" status. READ-ONLY — dues
// are paid on the web via Stripe Checkout (createClubDuesCheckout) and the club
// doc is flipped to active by the stripeWebhook Cloud Function. There is NO
// in-app purchase here (keeps us clear of Apple's IAP rules). Admins get a
// secure pay link by email (dailySubscriptionCheck) and at discgolfrankings.com.
// • Trial: days remaining  • Active: paid + expiry  • Expiring/Expired: status only

struct ClubSubscriptionView: View {
    let club: Club

    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss

    @State private var current: Club

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
                        manageOnWeb
                        valueProps
                    }
                    .padding()
                }
            }
            .navigationTitle("Club Dues")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
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
        case .active:       return "Club Dues Paid"
        case .expiringSoon: return "Dues Due Soon"
        case .expired:      return "Club Dues Expired"
        case .cancelled:    return "Club Dues Lapsed"
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

    // MARK: Manage-on-web notice
    // Club dues are paid on the web (Stripe Checkout), never via an in-app
    // purchase — this keeps us clear of Apple's IAP rules. The club doc's
    // status is updated by the Stripe webhook after payment.

    private var manageOnWeb: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "globe").foregroundStyle(Theme.accent)
                Text("Dues are managed on the web")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.textPrimary)
            }
            Text("We'll email the club admin a secure payment link before your free trial ends — and again if dues come due. You can also pay anytime at discgolfrankings.com. Your paid year is added on top of any trial time remaining, so you never lose free days.")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.25), lineWidth: 1))
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
        case .trial(let d):         return "Free trial: \(d) day\(d == 1 ? "" : "s") left. Tap for details."
        case .expiringSoon(let d):  return "Club dues due in \(d) day\(d == 1 ? "" : "s"). Check your email to pay."
        case .expired:              return "Club dues expired. Check your email to pay."
        case .cancelled:            return "Club dues lapsed. Check your email to pay."
        case .active:               return ""
        }
    }
}
