import SwiftUI

// MARK: - DaltonHomeView

struct DaltonHomeView: View {
    @EnvironmentObject var auth: AuthService
    private let service = FirebaseService.shared

    @State private var club: Club?
    @State private var myMembership: Membership?
    @State private var isLoading    = false
    @State private var isJoining    = false
    @State private var joinError: String?
    @State private var showGroupRound  = false
    @State private var showClubSearch  = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && club == nil {
                    ProgressView()
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            clubHeaderCard
                            membershipCard
                            findClubsButton
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Dalton Disc Golf Club")
            .navigationBarTitleDisplayMode(.large)
            .task { await loadData() }
            .refreshable { await loadData() }
            .sheet(isPresented: $showGroupRound, onDismiss: {
                Task { await loadData() }
            }) {
                GroupRoundView()
            }
            .sheet(isPresented: $showClubSearch, onDismiss: {
                Task { await loadData() }
            }) {
                ClubSearchView()
            }
        }
    }

    // MARK: Club Header

    private var clubHeaderCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.disc.sports")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            if let club {
                HStack(spacing: 24) {
                    VStack(spacing: 2) {
                        Text(club.location)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label("Location", systemImage: "mappin.and.ellipse")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Divider().frame(height: 36)
                    VStack(spacing: 2) {
                        Text("\(club.memberCount)")
                            .font(.title3.bold())
                        Label("Members", systemImage: "person.2")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(20)
        .background(.green.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Membership Card

    @ViewBuilder
    private var membershipCard: some View {
        if let membership = myMembership {
            VStack(spacing: 12) {
                Text("Your Tag")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("#\(membership.tagNumber)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(.green)
                Text("Member since \(membership.joinedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider().padding(.vertical, 4)

                Button {
                    showGroupRound = true
                } label: {
                    Label("Play for Tags", systemImage: "flag.checkered.2.crossed")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.blue)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.green.opacity(0.3), lineWidth: 1))
        } else {
            VStack(spacing: 12) {
                Text("You're not a member yet.")
                    .foregroundStyle(.secondary)

                if let joinError {
                    Text(joinError).foregroundStyle(.red).font(.caption)
                }

                Button { joinDalton() } label: {
                    Group {
                        if isJoining { ProgressView() } else {
                            Text("Join Dalton DGC").fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isJoining)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        }
    }

    // MARK: Find Clubs Button

    private var findClubsButton: some View {
        Button { showClubSearch = true } label: {
            Label("Search for Clubs", systemImage: "magnifyingglass")
                .fontWeight(.semibold)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .tint(.green)
    }

    // MARK: Data

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        guard let uid = auth.currentUser?.uid else { return }
        async let clubFetch   = service.fetchClub(id: service.daltonClubID)
        async let memberFetch = service.fetchMembership(userId: uid, clubId: service.daltonClubID)
        club         = (try? await clubFetch)   ?? nil
        myMembership = (try? await memberFetch) ?? nil
    }

    private func joinDalton() {
        guard let uid = auth.currentUser?.uid else { return }
        let name = auth.appUser?.displayName ?? auth.currentUser?.displayName ?? "Player"
        isJoining = true
        joinError = nil
        Task {
            do {
                try await service.joinDaltonClub(userId: uid, userFullName: name)
                await loadData()
            } catch {
                joinError = error.localizedDescription
            }
            isJoining = false
        }
    }
}

// MARK: - ClubSearchView

struct ClubSearchView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var clubs: [Club]         = []
    @State private var memberships: [Membership] = []
    @State private var isLoading             = false
    @State private var joiningClubId: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && clubs.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if clubs.isEmpty {
                    ContentUnavailableView(
                        "No clubs available yet.",
                        systemImage: "magnifyingglass",
                        description: Text("Check back after a club has been approved.")
                    )
                } else {
                    List(clubs) { club in
                        ClubSearchRowView(
                            club: club,
                            membership: memberships.first { $0.clubId == club.id },
                            isJoining: joiningClubId == club.id
                        ) {
                            await joinClub(club)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Search for Clubs")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        guard let uid = auth.currentUser?.uid else { isLoading = false; return }
        async let clubsFetch  = service.fetchApprovedClubs()
        async let memberFetch = service.fetchUserMemberships(userId: uid)
        clubs       = (try? await clubsFetch)  ?? []
        memberships = (try? await memberFetch) ?? []
        isLoading = false
    }

    private func joinClub(_ club: Club) async {
        guard let clubId = club.id, let uid = auth.currentUser?.uid else { return }
        let name = auth.appUser?.displayName ?? auth.currentUser?.displayName ?? "Player"
        joiningClubId = clubId
        try? await service.joinClub(userId: uid, userFullName: name, clubId: clubId)
        // Refresh membership list so the row updates immediately
        memberships = (try? await service.fetchUserMemberships(userId: uid)) ?? []
        joiningClubId = nil
    }
}

// MARK: - ClubSearchRowView

struct ClubSearchRowView: View {
    let club: Club
    let membership: Membership?
    let isJoining: Bool
    let onJoin: () async -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Club info
            VStack(alignment: .leading, spacing: 4) {
                Text(club.name)
                    .font(.headline)
                Text(club.location)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("\(club.memberCount) member\(club.memberCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Member badge OR join button
            if let m = membership {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("#\(m.tagNumber)")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(.green)
                    Text("Member")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                }
            } else {
                Button {
                    Task { await onJoin() }
                } label: {
                    if isJoining {
                        ProgressView()
                            .frame(width: 60)
                    } else {
                        Text("Join")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 8)
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isJoining)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - LeaderboardView

struct LeaderboardView: View {
    @EnvironmentObject var auth: AuthService
    private let service = FirebaseService.shared

    @State private var leaderboard: [Membership] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading && leaderboard.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if leaderboard.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "person.2")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No members yet.")
                            .font(.title3.bold())
                        Text("Be the first to join!")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        Section {
                            Text("\(leaderboard.count) Member\(leaderboard.count == 1 ? "" : "s")")
                                .font(.subheadline.bold())
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .center)
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                        }
                        ForEach(Array(leaderboard.enumerated()), id: \.element.id) { idx, member in
                            LeaderboardRowView(
                                rank: idx + 1,
                                membership: member,
                                isCurrentUser: member.userId == auth.currentUser?.uid
                            )
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Leaderboard")
            .task { await load() }
            .refreshable { await load() }
        }
    }

    private func load() async {
        isLoading = true
        leaderboard = (try? await service.fetchLeaderboard(clubID: service.daltonClubID)) ?? []
        isLoading = false
    }
}

// MARK: - LeaderboardRowView

struct LeaderboardRowView: View {
    let rank: Int
    let membership: Membership
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 14) {
            Text("#\(membership.tagNumber)")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 11)
                .padding(.vertical, 7)
                .background(badgeColor.opacity(0.14), in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(badgeColor)
                .frame(minWidth: 62, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(membership.userFullName)
                    .fontWeight(isCurrentUser ? .bold : .regular)
                if isCurrentUser {
                    Text("You")
                        .font(.caption2.bold())
                        .foregroundStyle(.green)
                }
            }

            Spacer()

            if let medal = medalEmoji {
                Text(medal).font(.title3)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(isCurrentUser ? Color.green.opacity(0.08) : Color.clear)
    }

    private var badgeColor: Color {
        switch rank {
        case 1:  return .yellow
        case 2:  return Color(white: 0.55)
        case 3:  return .brown
        default: return isCurrentUser ? .green : .primary
        }
    }

    private var medalEmoji: String? {
        switch rank {
        case 1: return "🏆"
        case 2: return "🥈"
        case 3: return "🥉"
        default: return nil
        }
    }
}
