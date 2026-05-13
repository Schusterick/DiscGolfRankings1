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
                .tabItem { Label("Home", systemImage: "house") }

            LeaderboardView()
                .tabItem { Label("Leaderboard", systemImage: "list.number") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.circle") }
        }
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    @EnvironmentObject var auth: AuthService
    private let service = FirebaseService.shared

    @State private var membership:      Membership?
    @State private var isLoading        = false
    @State private var isJoining        = false
    @State private var showClubRequest  = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                clubHeader
                Spacer()
                tagSection
                Spacer()
                accountSection

                // Request a Club
                Button {
                    showClubRequest = true
                } label: {
                    Label("Request a Club", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.green)
                .padding(.horizontal, 32)
                .padding(.bottom, 12)

                signOutButton
                    .padding(.bottom, 32)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadMembership() }
            .refreshable { await loadMembership() }
            .sheet(isPresented: $showClubRequest) {
                RequestClubView()
            }
        }
    }

    // MARK: Sub-views

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
                            Text("Join Dalton DGC").fontWeight(.semibold)
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

    // MARK: Data

    private func loadMembership() async {
        guard let uid = auth.currentUser?.uid else { return }
        isLoading  = true
        membership = try? await service.fetchMembership(userId: uid, clubId: service.daltonClubID)
        isLoading  = false
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

// MARK: - RequestClubView

struct RequestClubView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var clubName     = ""
    @State private var city         = ""
    @State private var state        = ""
    @State private var description  = ""
    @State private var website      = ""
    @State private var contactEmail = ""
    @State private var isSubmitting = false
    @State private var showSuccess  = false
    @State private var errorMessage: String?

    private var isValid: Bool {
        !clubName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !city.trimmingCharacters(in: .whitespaces).isEmpty &&
        !state.trimmingCharacters(in: .whitespaces).isEmpty &&
        !description.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Club Info") {
                    TextField("Club Name *", text: $clubName)
                    TextField("City *", text: $city)
                    TextField("State *", text: $state)
                }

                Section("Details") {
                    TextField("Description *", text: $description, axis: .vertical)
                        .lineLimit(3...6)
                    TextField("Website (optional)", text: $website)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                Section("Contact") {
                    TextField("Contact Email *", text: $contactEmail)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Request a Club")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting {
                        ProgressView()
                    } else {
                        Button("Submit") { submit() }
                            .disabled(!isValid)
                    }
                }
            }
            .alert("Request Submitted!", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Your club request has been submitted! We'll review it and get back to you within 2 business days.")
            }
            .onAppear {
                contactEmail = auth.currentUser?.email ?? ""
            }
        }
    }

    private func submit() {
        isSubmitting  = true
        errorMessage  = nil
        Task {
            do {
                try await service.submitClubApplication(
                    clubName:        clubName.trimmingCharacters(in: .whitespaces),
                    city:            city.trimmingCharacters(in: .whitespaces),
                    state:           state.trimmingCharacters(in: .whitespaces),
                    description:     description.trimmingCharacters(in: .whitespaces),
                    website:         website.trimmingCharacters(in: .whitespaces),
                    contactEmail:    contactEmail.trimmingCharacters(in: .whitespaces),
                    applicantUserId: auth.currentUser?.uid ?? "",
                    applicantName:   auth.appUser?.displayName ?? auth.currentUser?.displayName ?? ""
                )
                showSuccess = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
