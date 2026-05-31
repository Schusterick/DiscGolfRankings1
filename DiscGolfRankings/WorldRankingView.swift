import SwiftUI

// MARK: - WorldRankingView
// Global leaderboard of every user on DiscGolfRankings, ranked by signup order
// (lower worldRank = signed up earlier = better rank).
//
// Users can opt out via Edit Profile — those rows are filtered server-side via the
// FirebaseService.fetchWorldRanking() helper.

struct WorldRankingView: View {
    @EnvironmentObject var auth: AuthService
    private let service = FirebaseService.shared

    @State private var rows:        [AppUser] = []
    @State private var isLoading    = false
    @State private var isLoadingMore = false
    @State private var hasMore      = true
    @State private var errorMsg:    String?
    @State private var profileUser: AppUser? = nil

    private let pageSize = 50

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.homeGradient.ignoresSafeArea()

                if isLoading && rows.isEmpty {
                    ProgressView().tint(Theme.accent)
                } else if rows.isEmpty {
                    emptyState
                } else {
                    list
                }
            }
            .navigationTitle("World")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("World Ranking")
                        .font(.system(size: 17, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                }
            }
            .task { if rows.isEmpty { await loadFirstPage() } }
            .refreshable { await loadFirstPage() }
            .sheet(item: $profileUser) { user in
                if let uid = user.id {
                    PublicProfileView(userId: uid).environmentObject(auth)
                }
            }
        }
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                // Hero card showing the current user's own world rank (if set)
                if let me = auth.appUser, let myRank = me.worldRank {
                    myRankCard(user: me, rank: myRank)
                        .padding(.horizontal, 12)
                        .padding(.top, 8)
                }

                ForEach(rows) { user in
                    Button { profileUser = user } label: {
                        rankRow(user: user)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 12)
                    .onAppear { loadMoreIfNeeded(currentUser: user) }
                }

                if isLoadingMore {
                    ProgressView().tint(Theme.accent).padding(.vertical, 12)
                }
            }
            .padding(.vertical, 8)
        }
    }

    // MARK: Rows

    @ViewBuilder
    private func rankRow(user: AppUser) -> some View {
        let rank = user.worldRank ?? 0
        let isMe = user.id == auth.currentUser?.uid

        HStack(spacing: 12) {
            // Rank badge
            Text("#\(rank)")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .foregroundStyle(rankColor(rank))
                .frame(minWidth: 54, alignment: .leading)

            // Avatar
            avatar(for: user)

            VStack(alignment: .leading, spacing: 2) {
                Text(user.displayName)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let course = user.favoriteCourse, !course.isEmpty {
                    Text(course)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            if isMe {
                Text("YOU")
                    .font(.caption2.bold())
                    .foregroundStyle(Theme.accent)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.accent.opacity(0.15), in: Capsule())
            } else {
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(12)
        .background(
            isMe ? Theme.accent.opacity(0.10) : Theme.card,
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isMe ? Theme.accent.opacity(0.5) : Color.clear, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func myRankCard(user: AppUser, rank: Int) -> some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("YOUR WORLD RANK")
                    .font(.caption.bold())
                    .foregroundStyle(.white.opacity(0.85))
                Text("#\(rank)")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
            Spacer()
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 44))
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(18)
        .background(
            LinearGradient(colors: [Theme.accent, Theme.gold],
                           startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 16)
        )
    }

    // MARK: Avatar

    @ViewBuilder
    private func avatar(for user: AppUser) -> some View {
        let initials: String = {
            let parts = user.displayName.split(separator: " ")
            let first = parts.first?.prefix(1) ?? "?"
            let last  = parts.count > 1 ? parts.last!.prefix(1) : Substring("")
            return "\(first)\(last)".uppercased()
        }()
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Theme.accent, Theme.gold],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 36, height: 36)
            if let urlStr = user.photoURL, let url = URL(string: urlStr), !urlStr.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let img): img.resizable().scaledToFill()
                    default:
                        Text(initials).font(.caption.bold()).foregroundStyle(.white)
                    }
                }
                .frame(width: 34, height: 34)
                .clipShape(Circle())
            } else {
                Text(initials).font(.caption.bold()).foregroundStyle(.white)
            }
        }
    }

    // MARK: Empty state

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "globe.americas.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.textSecondary.opacity(0.6))
            Text("No Rankings Yet")
                .font(.title3.bold())
                .foregroundStyle(Theme.textPrimary)
            Text("World rankings will appear here as users join the app.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // MARK: Rank tint

    private func rankColor(_ rank: Int) -> Color {
        switch rank {
        case 1...10:   return Theme.gold
        case 11...100: return Theme.accent
        default:       return Theme.textPrimary
        }
    }

    // MARK: Data

    private func loadFirstPage() async {
        isLoading = true; errorMsg = nil
        defer { isLoading = false }
        do {
            let page = try await service.fetchWorldRanking(limit: pageSize)
            rows = page
            hasMore = page.count == pageSize
        } catch {
            errorMsg = error.localizedDescription
        }
    }

    private func loadMoreIfNeeded(currentUser user: AppUser) {
        // Trigger when the second-to-last row appears
        guard hasMore, !isLoadingMore,
              let idx = rows.firstIndex(where: { $0.id == user.id }),
              idx >= rows.count - 3 else { return }
        Task { await loadMore() }
    }

    private func loadMore() async {
        guard hasMore, !isLoadingMore, let last = rows.last?.worldRank else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await service.fetchWorldRanking(limit: pageSize, startAfter: last)
            // Dedupe in case Firestore returns overlaps
            let existingIds = Set(rows.compactMap(\.id))
            let new = page.filter { user in
                guard let id = user.id else { return false }
                return !existingIds.contains(id)
            }
            rows.append(contentsOf: new)
            hasMore = page.count == pageSize
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
