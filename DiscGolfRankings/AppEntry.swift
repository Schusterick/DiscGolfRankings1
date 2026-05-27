import SwiftUI
import FirebaseCore
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif
#if canImport(FBSDKCoreKit)
import FBSDKCoreKit
#endif

@main
struct DiscGolfRankingsApp: App {
    @StateObject private var auth = AuthService()
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    init() {
        FirebaseApp.configure()
        // Initialize Stripe (logs the key prefix; real SDK line is commented until SPM package is added)
        // TODO: After adding Stripe SDK via SPM, uncomment the import in StripeService.swift
        //       and the STPAPIClient line inside StripeService.configure()
        StripeService.shared.configure()
        #if canImport(FBSDKCoreKit)
        // Facebook SDK initializes itself from the AppDelegate-style call below — we
        // pass a minimal launchOptions dict because we don't have a real UIApplicationDelegate
        // in this SwiftUI app.
        ApplicationDelegate.shared.application(UIApplication.shared, didFinishLaunchingWithOptions: nil)
        #endif
    }

    var body: some Scene {
        WindowGroup {
            Group {
                // Routing order: sign-in always comes first.
                //  - Not signed in → SignInView (immediate account prompt)
                //  - Signed in + onboarding not yet seen → OnboardingView (post-signup tour)
                //  - Signed in + onboarding done → MainTabView
                if !auth.isSignedIn {
                    SignInView()
                        .environmentObject(auth)
                } else if !hasSeenOnboarding {
                    OnboardingView()
                        .environmentObject(auth)
                } else {
                    MainTabView()
                        .environmentObject(auth)
                }
            }
            .preferredColorScheme(.dark)
            // Route OAuth callbacks from Google and Facebook back into their SDKs
            .onOpenURL { url in
                #if canImport(GoogleSignIn)
                if GIDSignIn.sharedInstance.handle(url) { return }
                #endif
                #if canImport(FBSDKCoreKit)
                _ = ApplicationDelegate.shared.application(
                    UIApplication.shared,
                    open: url,
                    sourceApplication: nil,
                    annotation: [UIApplication.OpenURLOptionsKey.annotation]
                )
                #endif
            }
        }
    }
}

// MARK: - MainTabView

struct MainTabView: View {
    @EnvironmentObject var auth: AuthService
    @State private var selectedTab = 0
    @AppStorage("onboardingIntent") private var onboardingIntent = ""
    @State private var showRequestClubFromIntent = false

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem { Label("Home",        systemImage: "house.fill") }
                .tag(0)
            LeaderboardView()
                .tabItem { Label("Leaderboard", systemImage: "list.number") }
                .tag(1)
            ProfileView()
                .tabItem { Label("Profile",     systemImage: "person.circle.fill") }
                .tag(2)
            if auth.isSuperAdmin {
                SuperAdminView()
                    .tabItem { Label("Super",   systemImage: "crown.fill") }
                    .tag(3)
            } else if auth.isAppAdmin {
                AdminTabView()
                    .tabItem { Label("Admin",   systemImage: "shield.checkered") }
                    .tag(3)
            }
        }
        .tint(Theme.accent)
        .onAppear {
            // Honor onboarding intent — if the user tapped "Request a Club" on the
            // last page of onboarding, drop them straight into the request form.
            if onboardingIntent == "request" {
                showRequestClubFromIntent = true
            }
            onboardingIntent = ""           // clear so it only fires once
        }
        .sheet(isPresented: $showRequestClubFromIntent) {
            RequestClubView().environmentObject(auth)
        }
    }
}

// MARK: - ProfileView

struct ProfileView: View {
    @EnvironmentObject var auth: AuthService
    private let service = FirebaseService.shared

    @State private var clubMemberships: [ClubWithMembership] = []
    @State private var stats:           UserStats?
    @State private var isLoading        = false
    @State private var showClubRequest  = false
    @State private var showClubSearch   = false
    @State private var showEditProfile  = false
    @State private var showChallenges   = false
    @State private var pendingChallengeCount = 0
    @State private var upcomingEvents:   [Event] = []
    @State private var clubsById:        [String: Club] = [:]   // for event-row club name lookup
    @State private var profileClub:      Club? = nil            // tapped club profile sheet
    @State private var openEvent:        Event? = nil            // tapped event detail sheet

    private var displayName: String {
        auth.appUser?.displayName ?? auth.currentUser?.displayName ?? "Player"
    }
    private var initials: String {
        let parts = displayName.split(separator: " ")
        let first = parts.first?.prefix(1) ?? "?"
        let last  = parts.count > 1 ? parts.last!.prefix(1) : Substring("")
        return "\(first)\(last)".uppercased()
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.homeGradient.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        avatarSection
                        if let stats { statsRow(stats) }
                        if isLoading && clubMemberships.isEmpty {
                            ProgressView().tint(Theme.accent)
                        } else if clubMemberships.isEmpty {
                            emptyClubsCard
                        } else {
                            ForEach(clubMemberships) { item in
                                ProfileClubCard(item: item, onTap: { profileClub = item.club })
                            }
                        }

                        // Upcoming events across all of my clubs
                        if !upcomingEvents.isEmpty { upcomingEventsSection }

                        actionButtons
                    }
                    .padding()
                }
            }
            .navigationTitle("Profile")
            .navigationBarTitleDisplayMode(.large)
            .darkNavBar()
            .task { await loadData() }
            .refreshable { await loadData() }
            .sheet(isPresented: $showClubRequest, onDismiss: { Task { await loadData() } }) {
                RequestClubView()
            }
            .sheet(isPresented: $showClubSearch, onDismiss: { Task { await loadData() } }) {
                ClubSearchView()
            }
            .sheet(isPresented: $showEditProfile, onDismiss: { Task { await loadData() } }) {
                EditProfileView().environmentObject(auth)
            }
            .sheet(isPresented: $showChallenges, onDismiss: { Task { await loadData() } }) {
                MyChallengesView().environmentObject(auth)
            }
            .sheet(item: $profileClub) { club in
                ClubPublicProfileView(club: club).environmentObject(auth)
            }
            .sheet(item: $openEvent) { event in
                if let club = clubsById[event.clubId] {
                    EventDetailView(event: event, club: club, isClubMember: true)
                        .environmentObject(auth)
                }
            }
        }
    }

    // MARK: Upcoming events section

    @ViewBuilder
    private var upcomingEventsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "calendar").foregroundStyle(Theme.gold)
                Text("Upcoming Events").font(.headline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(upcomingEvents.count)")
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Theme.gold.opacity(0.18), in: Capsule())
                    .foregroundStyle(Theme.gold)
            }
            VStack(spacing: 8) {
                ForEach(upcomingEvents.prefix(5)) { event in
                    Button { openEvent = event } label: {
                        HStack(spacing: 10) {
                            VStack(spacing: 2) {
                                Text(event.startDate.formatted(.dateTime.month(.abbreviated)).uppercased())
                                    .font(.caption2.bold())
                                    .foregroundStyle(Theme.accent)
                                Text(event.startDate.formatted(.dateTime.day()))
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(Theme.textPrimary)
                            }
                            .frame(width: 44)
                            .padding(.vertical, 6)
                            .background(Theme.background, in: RoundedRectangle(cornerRadius: 8))

                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.subheadline.bold())
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                Text(clubsById[event.clubId]?.name ?? "")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                Text(event.startDate.formatted(date: .omitted, time: .shortened))
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            if let r = event.rsvps, let uid = auth.currentUser?.uid, r.contains(uid) {
                                Label("Going", systemImage: "checkmark.circle.fill")
                                    .font(.caption2.bold())
                                    .foregroundStyle(Theme.success)
                            }
                            Image(systemName: "chevron.right")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(12)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: Avatar

    private var avatarSection: some View {
        VStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.accent, Theme.gold],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 96, height: 96)

                if let urlStr = auth.appUser?.photoURL, let url = URL(string: urlStr), !urlStr.isEmpty {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .empty:
                            ProgressView().tint(.white)
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Text(initials)
                                .font(.system(size: 34, weight: .black, design: .rounded))
                                .foregroundStyle(.white)
                        @unknown default:
                            EmptyView()
                        }
                    }
                    .frame(width: 92, height: 92)
                    .clipShape(Circle())
                } else {
                    Text(initials)
                        .font(.system(size: 34, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .shadow(color: Theme.accent.opacity(0.5), radius: 12)

            Button { showEditProfile = true } label: {
                HStack(spacing: 6) {
                    Text(displayName)
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Image(systemName: "pencil.circle.fill")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit profile")
            .accessibilityHint("Opens your profile editor")

            // Your own email is shown to you only (private — never shown on PublicProfileView)
            Text(auth.currentUser?.email ?? "")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            // Social links
            if let user = auth.appUser, hasAnySocial(user) {
                SocialLinksRow(user: user).padding(.top, 4)
            }

            // Bio
            if let bio = auth.appUser?.bio, !bio.isEmpty {
                Text(bio)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                    .padding(.top, 4)
            }

            // Disc-golf fun facts
            if let user = auth.appUser, hasAnyFunFact(user) {
                HStack(spacing: 14) {
                    if let course = user.favoriteCourse, !course.isEmpty {
                        Label(course, systemImage: "flag.fill")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.gold.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.gold)
                    }
                    if let years = user.yearsPlaying {
                        Label(years == 1 ? "1 yr playing" : "\(years) yrs playing",
                              systemImage: "calendar")
                            .font(.caption.bold())
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Theme.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                }
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func hasAnySocial(_ u: AppUser) -> Bool {
        ![u.instagram, u.facebook, u.twitter, u.tiktok].compactMap { $0 }
            .filter { !$0.isEmpty }.isEmpty
    }

    private func hasAnyFunFact(_ u: AppUser) -> Bool {
        !(u.favoriteCourse?.isEmpty ?? true) || u.yearsPlaying != nil
    }

    // MARK: Stats Row

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
    }

    @ViewBuilder
    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 20, weight: .black, design: .rounded))
                .foregroundStyle(Theme.gold)
            Text(label)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Empty state

    private var emptyClubsCard: some View {
        VStack(spacing: 12) {
            Image(systemName: "tag.slash")
                .font(.system(size: 36))
                .foregroundStyle(Theme.textSecondary)
            Text("No Club Memberships")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("Search for a club on the Home tab.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(24)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    // MARK: Action Buttons

    private var actionButtons: some View {
        VStack(spacing: 12) {
            // 2×2 grid of primary actions
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                      spacing: 10) {
                // Challenges (with badge)
                Button { showChallenges = true } label: {
                    VStack(spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: "flag.checkered")
                            Text("Challenges")
                            if pendingChallengeCount > 0 {
                                Text("\(pendingChallengeCount)")
                                    .font(.caption2.bold())
                                    .padding(.horizontal, 6).padding(.vertical, 1)
                                    .background(Theme.accent, in: Capsule())
                                    .foregroundStyle(.white)
                            }
                        }
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent, lineWidth: 1.5))
                }

                Button { showEditProfile = true } label: {
                    Label("Edit Profile", systemImage: "pencil.circle")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent, lineWidth: 1.5))
                }

                Button { showClubSearch = true } label: {
                    Label("Search", systemImage: "magnifyingglass")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent, lineWidth: 1.5))
                }

                Button { showClubRequest = true } label: {
                    Label("Request", systemImage: "plus.circle")
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent, lineWidth: 1.5))
                }
            }

            Button(role: .destructive) { auth.signOut() } label: {
                Text("Sign Out")
                    .font(.footnote)
                    .foregroundStyle(Theme.accent.opacity(0.8))
            }
            .padding(.top, 4)
        }
    }

    // MARK: Data

    private func loadData() async {
        guard let uid = auth.currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        async let memberFetch  = service.fetchUserMemberships(userId: uid)
        async let statsFetch   = service.fetchUserStats(userId: uid)
        async let pendingFetch = service.pendingChallengeCount(userId: uid)
        let memberships = (try? await memberFetch) ?? []
        stats = try? await statsFetch
        pendingChallengeCount = (try? await pendingFetch) ?? 0
        var items: [ClubWithMembership] = []
        for m in memberships {
            if let club = try? await service.fetchClub(id: m.clubId) {
                items.append(ClubWithMembership(club: club, membership: m))
            }
        }
        clubMemberships = items.sorted { $0.membership.tagNumber < $1.membership.tagNumber }

        // Build clubId → Club map so the event rows can look up the club name
        var map: [String: Club] = [:]
        for item in clubMemberships {
            if let id = item.club.id { map[id] = item.club }
        }
        clubsById = map

        // Fetch upcoming events across every joined club (parallel)
        var allEvents: [Event] = []
        await withTaskGroup(of: [Event].self) { group in
            for item in clubMemberships {
                if let clubId = item.club.id {
                    group.addTask {
                        (try? await self.service.fetchUpcomingEvents(clubId: clubId)) ?? []
                    }
                }
            }
            for await events in group { allEvents += events }
        }
        upcomingEvents = allEvents.sorted { $0.startDate < $1.startDate }

        // Refresh user doc so newly edited photo/bio/socials appear immediately
        await auth.reloadAppUser()
    }
}

// MARK: - ProfileClubCard

struct ProfileClubCard: View {
    let item: ClubWithMembership
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            HStack(spacing: 16) {
                // Tag badge
                VStack(spacing: 2) {
                    Text("#\(item.membership.tagNumber)")
                        .font(.system(size: 26, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.gold)
                    Text("Tag")
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.textSecondary)
                }
                .frame(minWidth: 60)
                .padding(.vertical, 10)
                .padding(.horizontal, 8)
                .background(Theme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.club.name)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Ranked #\(item.membership.tagNumber) of \(item.club.memberCount)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if item.membership.isAdmin == true {
                        Label("Club Admin", systemImage: "shield.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(Theme.accent)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.gold.opacity(0.2), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(onTap == nil)
    }
}

// MARK: - RequestClubView

struct RequestClubView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    /// 50 US state abbreviations + DC, alphabetical. "Other" is appended in the Picker.
    static let usStates: [String] = [
        "AL","AK","AZ","AR","CA","CO","CT","DE","DC","FL","GA","HI","ID","IL","IN",
        "IA","KS","KY","LA","ME","MD","MA","MI","MN","MS","MO","MT","NE","NV","NH",
        "NJ","NM","NY","NC","ND","OH","OK","OR","PA","RI","SC","SD","TN","TX","UT",
        "VT","VA","WA","WV","WI","WY"
    ]

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
            ZStack {
                Theme.background.ignoresSafeArea()
                Form {
                    Section("Club Info") {
                        TextField("Club Name *", text: $clubName).foregroundStyle(Theme.textPrimary)
                        TextField("City *", text: $city).foregroundStyle(Theme.textPrimary)
                        Picker("State *", selection: $state) {
                            Text("Select…").tag("")
                            ForEach(Self.usStates, id: \.self) { Text($0).tag($0) }
                            Text("Other").tag("Other")
                        }
                        .pickerStyle(.menu)
                        .tint(Theme.accent)
                        .foregroundStyle(Theme.textPrimary)
                    }
                    .listRowBackground(Theme.card)

                    Section("Details") {
                        TextField("Description *", text: $description, axis: .vertical)
                            .lineLimit(3...6).foregroundStyle(Theme.textPrimary)
                        TextField("Website (optional)", text: $website)
                            .keyboardType(.URL).autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .listRowBackground(Theme.card)

                    Section("Contact") {
                        TextField("Contact Email *", text: $contactEmail)
                            .keyboardType(.emailAddress).autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .listRowBackground(Theme.card)

                    if let errorMessage {
                        Section { Text(errorMessage).foregroundStyle(.red).font(.caption) }
                            .listRowBackground(Theme.card)
                    }
                }
                .darkListStyle()
            }
            .navigationTitle("Request a Club")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accent)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSubmitting { ProgressView().tint(Theme.accent) }
                    else { Button("Submit") { submit() }.disabled(!isValid).foregroundStyle(Theme.accent) }
                }
            }
            .alert("Request Submitted!", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("We'll review it and get back to you within 2 business days.")
            }
            .onAppear { contactEmail = auth.currentUser?.email ?? "" }
        }
        .preferredColorScheme(.dark)
    }

    private func submit() {
        isSubmitting = true; errorMessage = nil
        Task {
            do {
                try await service.submitClubApplication(
                    clubName: clubName.trimmingCharacters(in: .whitespaces),
                    city: city.trimmingCharacters(in: .whitespaces),
                    state: state.trimmingCharacters(in: .whitespaces),
                    description: description.trimmingCharacters(in: .whitespaces),
                    website: website.trimmingCharacters(in: .whitespaces),
                    contactEmail: contactEmail.trimmingCharacters(in: .whitespaces),
                    applicantUserId: auth.currentUser?.uid ?? "",
                    applicantName: auth.appUser?.displayName ?? auth.currentUser?.displayName ?? ""
                )
                showSuccess = true
            } catch { errorMessage = error.localizedDescription }
            isSubmitting = false
        }
    }
}
