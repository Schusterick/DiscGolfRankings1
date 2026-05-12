import SwiftUI
import FirebaseCore

@main
struct DiscGolfRankingsApp: App {
    @StateObject private var auth = AuthService()

    init() {
        FirebaseApp.configure()
    }

    var body: some Scene {
        WindowGroup {
            if auth.isSignedIn {
                MainTabView()
                    .environmentObject(auth)
            } else {
                SignInView()
                    .environmentObject(auth)
            }
        }
    }
}

// MARK: - MainTabView

struct MainTabView: View {
    var body: some View {
        TabView {
            DaltonHomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            LeaderboardView()
                .tabItem {
                    Label("Leaderboard", systemImage: "list.number")
                }

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person.circle")
                }
        }
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    @EnvironmentObject var auth: AuthService
    private let service = FirebaseService.shared

    @State private var membership: Membership?
    @State private var isLoading = false
    @State private var isJoining = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                clubHeader
                Spacer()
                tagSection
                Spacer()
                accountSection
                signOutButton
                    .padding(.bottom, 32)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadMembership() }
            .refreshable { await loadMembership() }
        }
    }

    private var clubHeader: some View {
        VStack(spacing: 4) {
            Text("Dalton Disc Golf Club")
                .font(.title2.bold())
                .padding(.top, 24)
            Text("Tag Match System")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 16)
    }

    @ViewBuilder
    private var tagSection: some View {
        if isLoading {
            ProgressView()
        } else if let membership {
            VStack(spacing: 6) {
                Text("#\(membership.tagNumber)")
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .foregroundStyle(.green)
                Text("Your Current Tag")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "tag.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Tag Yet")
                    .font(.title3.bold())
                Button {
                    joinClub()
                } label: {
                    Group {
                        if isJoining { ProgressView() } else {
                            Text("Join Dalton DGC")
                                .fontWeight(.semibold)
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
                .disabled(isJoining)
            }
        }
    }

    private var accountSection: some View {
        VStack(spacing: 4) {
            Text(auth.appUser?.displayName ?? auth.currentUser?.displayName ?? "—")
                .font(.headline)
            Text(auth.currentUser?.email ?? "—")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 24)
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            auth.signOut()
        } label: {
            Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .padding(.horizontal, 32)
    }

    private func loadMembership() async {
        guard let uid = auth.currentUser?.uid else { return }
        isLoading = true
        membership = try? await service.fetchMembership(userId: uid, clubId: service.daltonClubID)
        isLoading = false
    }

    private func joinClub() {
        guard let uid = auth.currentUser?.uid else { return }
        let name = auth.appUser?.displayName ?? auth.currentUser?.displayName ?? "Player"
        isJoining = true
        Task {
            try? await service.joinDaltonClub(userId: uid, userFullName: name)
            await loadMembership()
            isJoining = false
        }
    }
}
