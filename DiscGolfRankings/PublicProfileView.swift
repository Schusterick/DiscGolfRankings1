import SwiftUI

// MARK: - PublicProfileView
// Shown when one player taps another player's name (e.g. from the leaderboard).
// Read-only view of the other user's profile + a "Challenge" button when
// both players share a club.

struct PublicProfileView: View {
    let userId: String                 // the user being viewed
    var clubContext: Club? = nil       // pass the club we came from so the Challenge button has context

    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var user:        AppUser?
    @State private var theirMembership: Membership?    // their membership in clubContext, if any
    @State private var stats:       UserStats?
    @State private var isLoading    = false
    @State private var challengeTarget: Membership?    // set when Challenge button tapped
    @State private var myMembership:    Membership?   // mine in clubContext

    private var displayName: String { user?.displayName ?? "Player" }
    private var initials: String {
        let parts = displayName.split(separator: " ")
        let first = parts.first?.prefix(1) ?? "?"
        let last  = parts.count > 1 ? parts.last!.prefix(1) : Substring("")
        return "\(first)\(last)".uppercased()
    }
    private var isMyself: Bool { userId == auth.currentUser?.uid }
    private var canChallenge: Bool {
        !isMyself && theirMembership != nil && myMembership != nil && clubContext != nil
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.homeGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 22) {
                        avatar
                        nameBlock
                        if let user, hasAnySocial(user) {
                            SocialLinksRow(user: user)
                        }
                        if let bio = user?.bio, !bio.isEmpty {
                            Text(bio)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 24)
                        }

                        if let s = stats { statsRow(s) }

                        if canChallenge, let target = theirMembership {
                            Button { challengeTarget = target } label: {
                                Label("Challenge in \(clubContext?.name ?? "Club")",
                                      systemImage: "flag.checkered")
                                    .font(.headline).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 16)
                                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                            }
                            .padding(.horizontal, 24)
                        }

                        if let tag = theirMembership?.tagNumber, let clubName = clubContext?.name {
                            HStack(spacing: 6) {
                                Image(systemName: "tag.fill").foregroundStyle(Theme.gold)
                                Text("Tag #\(tag) in \(clubName)")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.top, -4)
                        }
                    }
                    .padding(.vertical, 24)
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
            .task { await load() }
            .sheet(item: $challengeTarget) { target in
                if let club = clubContext, let mine = myMembership {
                    SendChallengeView(club: club, challenger: mine, defendant: target)
                        .environmentObject(auth)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Avatar

    @ViewBuilder
    private var avatar: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Theme.accent, Theme.gold],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 110, height: 110)

            if let urlStr = user?.photoURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:     ProgressView().tint(.white)
                    case .success(let img): img.resizable().scaledToFill()
                    case .failure:   Text(initials).font(.system(size: 40, weight: .black, design: .rounded)).foregroundStyle(.white)
                    @unknown default: EmptyView()
                    }
                }
                .frame(width: 104, height: 104)
                .clipShape(Circle())
            } else {
                Text(initials)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .shadow(color: Theme.accent.opacity(0.4), radius: 14)
    }

    @ViewBuilder
    private var nameBlock: some View {
        VStack(spacing: 4) {
            Text(displayName)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
            if let email = user?.email {
                Text(email)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }

    @ViewBuilder
    private func statsRow(_ s: UserStats) -> some View {
        HStack(spacing: 0) {
            statCell(value: "\(s.clubCount)",
                     label: s.clubCount == 1 ? "Club" : "Clubs")
            Divider().frame(height: 36).background(Theme.divider)
            statCell(value: s.averageRank.map { String(format: "#%.1f", $0) } ?? "—",
                     label: "Avg Tag")
        }
        .padding(.vertical, 14)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(Theme.gold)
            Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func hasAnySocial(_ u: AppUser) -> Bool {
        ![u.instagram, u.facebook, u.twitter, u.tiktok].compactMap { $0 }
            .filter { !$0.isEmpty }.isEmpty
    }

    // MARK: Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        async let userFetch  = service.fetchUser(uid: userId)
        async let statsFetch = service.fetchUserStats(userId: userId)
        user  = try? await userFetch
        stats = try? await statsFetch

        // Look up both players' memberships in clubContext for the challenge wiring
        if let club = clubContext, let clubId = club.id {
            async let theirs = service.fetchMembership(userId: userId, clubId: clubId)
            async let mine   = service.fetchMembership(userId: auth.currentUser?.uid ?? "", clubId: clubId)
            theirMembership = try? await theirs
            myMembership    = try? await mine
        }
    }
}
