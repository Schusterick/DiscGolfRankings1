import SwiftUI

// MARK: - DaltonHomeView

struct DaltonHomeView: View {
    @EnvironmentObject var auth: AuthService
    private let service = FirebaseService.shared

    @State private var club: Club?
    @State private var myMembership: Membership?
    @State private var isLoading = false
    @State private var isJoining = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else {
                    ScrollView {
                        VStack(spacing: 24) {
                            clubHeaderCard
                            membershipCard
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Dalton Disc Golf Club")
            .navigationBarTitleDisplayMode(.large)
            .task { await loadData() }
            .refreshable { await loadData() }
        }
    }

    private var clubHeaderCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.disc.sports")
                .font(.system(size: 56))
                .foregroundStyle(.green)

            if let club {
                HStack(spacing: 24) {
                    VStack {
                        Text(club.location)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Label("Location", systemImage: "mappin.and.ellipse")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Divider().frame(height: 36)
                    VStack {
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

    @ViewBuilder
    private var membershipCard: some View {
        if let membership = myMembership {
            VStack(spacing: 8) {
                Text("Your Tag")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("#\(membership.tagNumber)")
                    .font(.system(size: 72, weight: .black, design: .rounded))
                    .foregroundStyle(.green)
                Text("Member since \(membership.joinedAt.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(24)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(.green.opacity(0.3), lineWidth: 1))
        } else {
            VStack(spacing: 12) {
                Text("You're not a member yet.")
                    .foregroundStyle(.secondary)

                if let error {
                    Text(error).foregroundStyle(.red).font(.caption)
                }

                Button {
                    joinClub()
                } label: {
                    Group {
                        if isJoining {
                            ProgressView()
                        } else {
                            Text("Join Dalton DGC")
                                .fontWeight(.semibold)
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

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        guard let uid = auth.currentUser?.uid else { return }
        async let clubFetch = service.fetchClub(id: service.daltonClubID)
        async let memberFetch = service.fetchMembership(userId: uid, clubId: service.daltonClubID)
        club = (try? await clubFetch) ?? nil
        myMembership = (try? await memberFetch) ?? nil
    }

    private func joinClub() {
        guard let uid = auth.currentUser?.uid else { return }
        let name = auth.appUser?.displayName ?? auth.currentUser?.displayName ?? "Player"
        isJoining = true
        error = nil
        Task {
            do {
                try await service.joinDaltonClub(userId: uid, userFullName: name)
                await loadData()
            } catch {
                self.error = error.localizedDescription
            }
            isJoining = false
        }
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
                } else if leaderboard.isEmpty {
                    ContentUnavailableView("No Members Yet", systemImage: "person.2")
                } else {
                    List {
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
        HStack(spacing: 12) {
            Text("#\(membership.tagNumber)")
                .font(.title3.monospacedDigit().bold())
                .foregroundStyle(tagColor)
                .frame(width: 52, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(membership.userFullName)
                        .fontWeight(isCurrentUser ? .bold : .regular)
                    if isCurrentUser {
                        Text("(You)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if rank == 1 {
                Text("🏆")
                    .font(.title3)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(isCurrentUser ? Color.green.opacity(0.08) : nil)
    }

    private var tagColor: Color {
        switch rank {
        case 1: return .yellow
        case 2: return .gray
        case 3: return .brown
        default: return .primary
        }
    }
}
