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
    @EnvironmentObject var auth: AuthService

    var body: some View {
        TabView {
            DaltonHomeView()
                .tabItem { Label("Home", systemImage: "house") }

            LeaderboardView()
                .tabItem { Label("Leaderboard", systemImage: "list.number") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.circle") }

            if auth.isAppAdmin {
                AdminTabView()
                    .tabItem { Label("Admin", systemImage: "shield.checkered") }
            }
        }
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    @EnvironmentObject var auth: AuthService
    private let service = FirebaseService.shared

    @State private var clubMemberships: [ClubWithMembership] = []
    @State private var selectedIndex    = 0
    @State private var isLoading        = false
    @State private var isJoining        = false
    @State private var showClubRequest  = false

    private var selected: ClubWithMembership? {
        guard !clubMemberships.isEmpty, selectedIndex < clubMemberships.count else { return nil }
        return clubMemberships[selectedIndex]
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Club picker — only visible when member of 2+ clubs
                if clubMemberships.count > 1 {
                    clubPicker.padding(.top, 8)
                }

                Spacer()
                tagSection
                Spacer()
                accountSection

                requestClubButton
                    .padding(.bottom, 12)

                signOutButton
                    .padding(.bottom, 32)
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadData() }
            .refreshable { await loadData() }
            .sheet(isPresented: $showClubRequest) {
                RequestClubView()
            }
        }
    }

    // MARK: Sub-views

    @ViewBuilder
    private var clubPicker: some View {
        // Segmented for 2–3 clubs, menu picker for 4+
        if clubMemberships.count <= 3 {
            Picker("Club", selection: $selectedIndex) {
                ForEach(clubMemberships.indices, id: \.self) { i in
                    Text(clubMemberships[i].club.name).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
        } else {
            Picker("Club", selection: $selectedIndex) {
                ForEach(clubMemberships.indices, id: \.self) { i in
                    Text(clubMemberships[i].club.name).tag(i)
                }
            }
            .pickerStyle(.menu)
            .padding(.horizontal)
        }
    }

    @ViewBuilder
    private var tagSection: some View {
        if isLoading {
            ProgressView()
        } else if let item = selected {
            VStack(spacing: 8) {
                Text(item.club.name)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Text("#\(item.membership.tagNumber)")
                    .font(.system(size: 96, weight: .black, design: .rounded))
                    .foregroundStyle(.green)

                Text("Your Current Tag")
                    .font(.headline)
                    .foregroundStyle(.secondary)

                Text("\(item.club.memberCount) member\(item.club.memberCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "tag.slash")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("No Club Memberships")
                    .font(.title3.bold())
                Text("Head to the Home tab to join Dalton DGC.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
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

    private var requestClubButton: some View {
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

    private func loadData() async {
        guard let uid = auth.currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }

        let memberships = (try? await service.fetchUserMemberships(userId: uid)) ?? []

        var items: [ClubWithMembership] = []
        for m in memberships {
            if let club = try? await service.fetchClub(id: m.clubId) {
                items.append(ClubWithMembership(club: club, membership: m))
            }
        }
        // Sort by tag number so best rank appears first in the picker
        clubMemberships = items.sorted { $0.membership.tagNumber < $1.membership.tagNumber }

        // Keep selected index in bounds after a refresh
        if selectedIndex >= clubMemberships.count { selectedIndex = 0 }
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
                        Text(errorMessage).foregroundStyle(.red).font(.caption)
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
                        Button("Submit") { submit() }.disabled(!isValid)
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
        isSubmitting = true
        errorMessage = nil
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
