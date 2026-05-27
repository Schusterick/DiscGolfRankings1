import SwiftUI

// MARK: - HomeView

struct HomeView: View {
    @EnvironmentObject var auth: AuthService
    private let service = FirebaseService.shared

    @State private var clubMemberships:  [ClubWithMembership] = []
    @State private var pendingRounds:    [PendingRound]       = []
    @State private var notifications:    [AppNotification]    = []
    @State private var isLoading         = false
    @State private var showClubSearch    = false
    @State private var showPendingRounds = false
    @State private var showNotifications = false
    @State private var playingClub: Club? = nil
    @State private var adminClub:   Club? = nil
    @State private var profileClub: Club? = nil   // public club profile sheet

    private var myUID: String { auth.currentUser?.uid ?? "" }

    private var roundsNeedingMyAction: [PendingRound] {
        pendingRounds.filter { $0.needsResponse(from: myUID) && $0.submittedBy != myUID }
    }
    private var unreadCount: Int { notifications.filter { !$0.isRead }.count }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.homeGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 16) {
                        if !roundsNeedingMyAction.isEmpty { pendingBanner }
                        if clubMemberships.isEmpty && !isLoading { emptyCard }
                        ForEach(clubMemberships) { item in
                            ClubCardView(item: item,
                                         onPlayForTags: { playingClub = item.club },
                                         onAdminDash:   { adminClub   = item.club },
                                         onViewProfile: { profileClub = item.club })
                        }
                        // Search only when the user has zero memberships — otherwise
                        // it duplicates the Profile tab's Search button.
                        if clubMemberships.isEmpty { searchButton }
                    }
                    .padding()
                }
            }
            .navigationTitle("DiscGolfRankings")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showNotifications = true } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "bell.fill")
                                .foregroundStyle(Theme.textSecondary)
                            if unreadCount > 0 {
                                Circle().fill(Theme.accent)
                                    .frame(width: 8, height: 8)
                                    .offset(x: 4, y: -4)
                            }
                        }
                    }
                    .accessibilityLabel(unreadCount > 0
                        ? "Notifications, \(unreadCount) unread"
                        : "Notifications")
                }
            }
            .task { await loadData() }
            .refreshable { await loadData() }
            .sheet(isPresented: $showClubSearch, onDismiss: { Task { await loadData() } }) {
                ClubSearchView()
            }
            .sheet(item: $playingClub, onDismiss: { Task { await loadData() } }) { club in
                GroupRoundView(club: club)
            }
            .sheet(item: $adminClub, onDismiss: { Task { await loadData() } }) { club in
                AdminDashboardView(club: club)
            }
            .sheet(isPresented: $showPendingRounds, onDismiss: { Task { await loadData() } }) {
                PendingRoundsView()
            }
            .sheet(isPresented: $showNotifications, onDismiss: { Task { await loadData() } }) {
                NotificationsView()
            }
            .sheet(item: $profileClub) { club in
                ClubPublicProfileView(club: club).environmentObject(auth)
            }
        }
    }

    // MARK: Sub-views

    private var pendingBanner: some View {
        Button { showPendingRounds = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle().fill(Theme.accent.opacity(0.15)).frame(width: 44, height: 44)
                    Image(systemName: "bell.badge.fill")
                        .foregroundStyle(Theme.accent).font(.title3)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(roundsNeedingMyAction.count) Round\(roundsNeedingMyAction.count == 1 ? "" : "s") Need Confirmation")
                        .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                    Text("Tap to review and confirm scores")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent.opacity(0.4), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var emptyCard: some View {
        VStack(spacing: 16) {
            Image(systemName: "figure.disc.sports")
                .font(.system(size: 56)).foregroundStyle(Theme.accent)
            Text("No Clubs Yet")
                .font(.title3.bold()).foregroundStyle(Theme.textPrimary)
            Text("Search for clubs to find one near you.")
                .foregroundStyle(Theme.textSecondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(32)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
    }

    private var searchButton: some View {
        Button { showClubSearch = true } label: {
            Label("Search for Clubs", systemImage: "magnifyingglass")
                .fontWeight(.semibold).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 14)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
        }
    }

    // MARK: Data

    private func loadData() async {
        guard let uid = auth.currentUser?.uid else { return }
        isLoading = true
        defer { isLoading = false }
        async let mFetch = service.fetchUserMemberships(userId: uid)
        async let pFetch = service.fetchPendingRoundsForUser(userId: uid)
        async let nFetch = service.fetchNotifications(userId: uid)
        let memberships   = (try? await mFetch) ?? []
        pendingRounds     = (try? await pFetch) ?? []
        notifications     = (try? await nFetch) ?? []
        var items: [ClubWithMembership] = []
        for m in memberships {
            if let club = try? await service.fetchClub(id: m.clubId) {
                items.append(ClubWithMembership(club: club, membership: m))
            }
        }
        clubMemberships = items.sorted { $0.membership.tagNumber < $1.membership.tagNumber }
    }
}

// MARK: - ClubCardView

struct ClubCardView: View {
    let item: ClubWithMembership
    let onPlayForTags: () -> Void
    let onAdminDash:   () -> Void
    let onViewProfile: () -> Void

    @EnvironmentObject var auth: AuthService

    private var isClubAdmin: Bool {
        item.membership.isAdmin == true ||
        item.club.adminUID == auth.currentUser?.uid ||
        item.club.adminUserIds?.contains(auth.currentUser?.uid ?? "") == true
    }

    var body: some View {
        VStack(spacing: 14) {
            // Header row
            HStack(alignment: .top) {
                Button { onViewProfile() } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(item.club.name)
                                .font(.headline).foregroundStyle(Theme.textPrimary)
                            Image(systemName: "chevron.right")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Text(item.club.location)
                            .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        HStack(spacing: 8) {
                            Text("\(item.club.memberCount) member\(item.club.memberCount == 1 ? "" : "s")")
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                            if let fee = item.club.joinFee, fee > 0 {
                                Text("• $\(Int(fee)) to join")
                                    .font(.caption).foregroundStyle(Theme.gold)
                            } else {
                                Text("• Free")
                                    .font(.caption).foregroundStyle(Theme.success)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("#\(item.membership.tagNumber)")
                        .font(.system(size: 32, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.gold)
                    Text("Your Tag")
                        .font(.caption2.bold()).foregroundStyle(Theme.textSecondary)
                }
            }

            // Mission statement
            if let mission = item.club.missionStatement, !mission.isEmpty {
                Text(mission)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, -4)
            }

            Divider().background(Theme.divider)

            // Action row
            HStack(spacing: 10) {
                Button { onPlayForTags() } label: {
                    Label("Play for Tags", systemImage: "flag.checkered.2.crossed")
                        .fontWeight(.semibold).foregroundStyle(.white)
                        .frame(maxWidth: .infinity).padding(.vertical, 12)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                }

                // Share button
                if let clubId = item.club.id,
                   let url = URL(string: "discgolfranks://club/\(clubId)") {
                    ShareLink(item: url) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Theme.textSecondary)
                            .padding(12)
                            .background(Theme.cardAlt, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("Share \(item.club.name)")
                }

                // Admin gear
                if isClubAdmin {
                    Button { onAdminDash() } label: {
                        Image(systemName: "gear")
                            .foregroundStyle(Theme.gold)
                            .padding(12)
                            .background(Theme.gold.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .accessibilityLabel("\(item.club.name) admin dashboard")
                }
            }
        }
        .padding(20)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Theme.gold.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - NotificationsView

struct NotificationsView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var notifications: [AppNotification] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Group {
                    if isLoading && notifications.isEmpty {
                        ProgressView().tint(Theme.accent)
                    } else if notifications.isEmpty {
                        ContentUnavailableView("No Notifications", systemImage: "bell.slash")
                            .foregroundStyle(Theme.textSecondary)
                    } else {
                        List(notifications) { n in
                            Button { Task { await tap(n) } } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(n.isRead ? Theme.divider : Theme.accent)
                                        .frame(width: 8, height: 8)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(n.message)
                                            .font(.subheadline)
                                            .foregroundStyle(n.isRead ? Theme.textSecondary : Theme.textPrimary)
                                        Text(n.createdAt.formatted(date: .abbreviated, time: .shortened))
                                            .font(.caption2)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                }
                                .padding(.vertical, 4)
                                .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.card)
                            .listRowSeparatorTint(Theme.divider)
                        }
                        .darkListStyle()
                    }
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.large)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    if notifications.contains(where: { !$0.isRead }) {
                        Button { Task { await markAllRead() } } label: {
                            Text("Mark All Read").font(.subheadline).foregroundStyle(Theme.accent)
                        }
                        .accessibilityLabel("Mark all notifications as read")
                    }
                }
            }
            .task { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private func load() async {
        guard let uid = auth.currentUser?.uid else { return }
        isLoading = true
        notifications = (try? await service.fetchNotifications(userId: uid)) ?? []
        // NOTE: read-state is no longer auto-flipped on view appear — the user
        // explicitly marks rows read by tapping them (or all via the toolbar).
        isLoading = false
    }

    /// Per-row tap — flips just that notification to read, optimistically updating
    /// the local array so the dot greys out immediately.
    private func tap(_ n: AppNotification) async {
        guard let uid = auth.currentUser?.uid, !n.isRead else { return }
        if let idx = notifications.firstIndex(where: { $0.id == n.id }) {
            notifications[idx].isRead = true
        }
        try? await service.markNotificationRead(id: n.id, userId: uid)
    }

    /// "Mark All Read" toolbar action.
    private func markAllRead() async {
        guard let uid = auth.currentUser?.uid else { return }
        // Optimistic local update
        notifications = notifications.map { var n = $0; n.isRead = true; return n }
        try? await service.markAllNotificationsRead(userId: uid)
    }
}

// MARK: - ClubSearchView

struct ClubSearchView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var clubs:        [Club]        = []
    @State private var memberships:  [Membership]  = []
    @State private var joinRequests: [JoinRequest] = []
    @State private var isLoading     = false
    @State private var joiningClubId: String?
    @State private var showPaymentView = false
    @State private var paymentClub:    Club?
    @State private var searchText     = ""
    @State private var infoClub:       Club?

    private var filteredClubs: [Club] {
        searchText.isEmpty ? clubs : clubs.filter { c in
            c.name.localizedCaseInsensitiveContains(searchText)
            || c.location.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                VStack(spacing: 0) {
                    // Search bar
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Theme.textSecondary)
                        TextField("Search clubs by name or location…", text: $searchText)
                            .foregroundStyle(Theme.textPrimary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !searchText.isEmpty {
                            Button { searchText = "" } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .padding(10)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                    .padding(.horizontal)
                    .padding(.vertical, 8)

                    Text("\(filteredClubs.count) club\(filteredClubs.count == 1 ? "" : "s")")
                        .font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal).padding(.bottom, 4)

                    if isLoading && clubs.isEmpty {
                        ProgressView().tint(Theme.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if clubs.isEmpty {
                        ContentUnavailableView(
                            "No clubs available yet.",
                            systemImage: "magnifyingglass",
                            description: Text("Check back after a club has been approved.")
                        )
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if filteredClubs.isEmpty {
                        ContentUnavailableView(
                            "No matches",
                            systemImage: "magnifyingglass",
                            description: Text("Try a different city or club name.")
                        )
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        List(filteredClubs) { club in
                            ClubSearchRowView(
                                club: club,
                                membership:  memberships.first  { $0.clubId == club.id },
                                joinRequest: joinRequests.first { $0.clubId == club.id },
                                isJoining:   joiningClubId != nil && joiningClubId == club.id,
                                onInfo:      { infoClub = club }
                            ) {
                                await handleJoin(club)
                            }
                            .listRowBackground(Theme.card)
                            .listRowSeparatorTint(Theme.divider)
                        }
                        .darkListStyle()
                    }
                }
            }
            .navigationTitle("Search for Clubs")
            .navigationBarTitleDisplayMode(.large)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .sheet(isPresented: $showPaymentView, onDismiss: { Task { await load() } }) {
                if let club = paymentClub {
                    PaymentPreviewView(club: club)
                        .environmentObject(auth)
                }
            }
            .sheet(item: $infoClub) { club in
                ClubPublicProfileView(club: club).environmentObject(auth)
            }
        }
        .preferredColorScheme(.dark)
    }

    private func load() async {
        isLoading = true
        guard let uid = auth.currentUser?.uid else { isLoading = false; return }
        async let cFetch = service.fetchApprovedClubs()
        async let mFetch = service.fetchUserMemberships(userId: uid)
        clubs       = (try? await cFetch) ?? []
        memberships = (try? await mFetch) ?? []
        // Fetch any pending join requests for this user
        var reqs: [JoinRequest] = []
        for club in clubs {
            if let req = try? await service.checkJoinRequest(userId: uid, clubId: club.id ?? "") {
                reqs.append(req)
            }
        }
        joinRequests = reqs
        isLoading = false
    }

    private func handleJoin(_ club: Club) async {
        guard let clubId = club.id,
              let uid = auth.currentUser?.uid else { return }

        if let fee = club.joinFee, fee > 0 {
            // Paid club — launch Stripe payment flow.
            // Success haptic fires when PaymentPreviewView reports completion.
            paymentClub     = club
            showPaymentView = true
        } else {
            // Free club — join immediately
            let name  = auth.appUser?.displayName ?? auth.currentUser?.displayName ?? "Player"
            let email = auth.currentUser?.email ?? ""
            joiningClubId = clubId
            try? await service.joinClub(userId: uid, userFullName: name,
                                        clubId: clubId, userEmail: email)
            memberships = (try? await service.fetchUserMemberships(userId: uid)) ?? []
            joiningClubId = nil
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}

// MARK: - ClubSearchRowView

struct ClubSearchRowView: View {
    let club: Club
    let membership:  Membership?
    let joinRequest: JoinRequest?
    let isJoining:   Bool
    var onInfo:      (() -> Void)? = nil       // ⓘ button — opens public profile
    let onJoin:      () async -> Void

    private var hasFee: Bool { (club.joinFee ?? 0) > 0 }

    var body: some View {
        // The whole row's empty area calls onInfo(). The Join button (a SwiftUI
        // Button) sits on top and captures its own tap before the gesture fires —
        // so tapping it routes to onJoin(), not onInfo().
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(club.name)
                    .font(.headline).foregroundStyle(Theme.textPrimary)
                Text(club.location)
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                HStack(spacing: 6) {
                    Text("\(club.memberCount) member\(club.memberCount == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    if hasFee {
                        Text("• $\(Int(club.joinFee!)) fee")
                            .font(.caption).foregroundStyle(Theme.gold)
                    } else {
                        Text("• Free")
                            .font(.caption).foregroundStyle(Theme.success)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()

            if let m = membership {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("#\(m.tagNumber)")
                        .font(.title3.bold().monospacedDigit())
                        .foregroundStyle(Theme.gold)
                    Text("Member")
                        .font(.caption2.bold()).foregroundStyle(Theme.success)
                }
            } else if joinRequest?.status == .pending {
                VStack(alignment: .trailing, spacing: 2) {
                    Image(systemName: "clock.fill").foregroundStyle(Theme.gold)
                    Text("Pending")
                        .font(.caption2.bold()).foregroundStyle(Theme.gold)
                }
            } else if hasFee && (club.stripeConnectedAccountId?.isEmpty ?? true) {
                // Paid club but Stripe Connect not yet configured by admin
                VStack(spacing: 2) {
                    Text("Coming")
                    Text("Soon")
                }
                .font(.caption.bold())
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.divider, lineWidth: 1))
            } else {
                Button {
                    Task { await onJoin() }
                } label: {
                    if isJoining {
                        ProgressView().tint(.white).frame(width: 80)
                    } else {
                        Text(hasFee ? "Pay & Join" : "Join")
                            .fontWeight(.semibold).foregroundStyle(.white)
                            .padding(.horizontal, 18).padding(.vertical, 8)
                            .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                    }
                }
                .disabled(isJoining)
                .buttonStyle(.borderless)        // ensures the button consumes its tap
            }
        }
        .padding(.vertical, 6)
        .contentShape(.rect)                     // make the whole row hit-testable
        .onTapGesture { onInfo?() }
    }
}

// MARK: - LeaderboardView

struct LeaderboardView: View {
    @EnvironmentObject var auth: AuthService
    private let service = FirebaseService.shared

    @State private var userClubs:        [ClubWithMembership] = []
    @State private var selectedClubIndex = 0
    @State private var leaderboard:      [Membership] = []
    @State private var challengeTarget:  Membership?  = nil
    @State private var profileTarget:    ProfileTarget? = nil   // wraps userId for public profile sheet
    @State private var clubProfileTarget: Club?         = nil   // for the club public profile sheet
    @State private var viewMode:         LeaderboardMode = .rankings

    enum LeaderboardMode: String, CaseIterable, Identifiable {
        case rankings, activity
        var id: String { rawValue }
        var label: String { self == .rankings ? "Rankings" : "Activity" }
    }

    struct ProfileTarget: Identifiable { let id: String }   // id == userId
    @State private var recentRounds:     [RoundRecord] = []
    @State private var searchText        = ""
    @State private var isLoadingClubs    = false
    @State private var isLoadingBoard    = false
    @State private var lastUpdated:      Date?

    private var selectedClub: Club? {
        guard !userClubs.isEmpty, selectedClubIndex < userClubs.count else { return nil }
        return userClubs[selectedClubIndex].club
    }

    private var filtered: [Membership] {
        searchText.isEmpty ? leaderboard
            : leaderboard.filter { $0.userFullName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Group {
                    if isLoadingClubs && userClubs.isEmpty {
                        ProgressView().tint(Theme.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if userClubs.isEmpty {
                        ContentUnavailableView(
                            "No Club Memberships",
                            systemImage: "list.number",
                            description: Text("Join a club to see its leaderboard.")
                        )
                        .foregroundStyle(Theme.textSecondary)
                    } else {
                        VStack(spacing: 0) {
                            // Club picker
                            clubPicker
                                .padding(.horizontal)
                                .padding(.vertical, 8)

                            // Mode picker: Rankings | Activity
                            Picker("", selection: $viewMode) {
                                ForEach(LeaderboardMode.allCases) { mode in
                                    Text(mode.label).tag(mode)
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding(.horizontal)
                            .padding(.bottom, 8)

                            if viewMode == .rankings {
                                // Search bar
                                HStack {
                                    Image(systemName: "magnifyingglass")
                                        .foregroundStyle(Theme.textSecondary)
                                    TextField("Search players…", text: $searchText)
                                        .foregroundStyle(Theme.textPrimary)
                                        .autocorrectionDisabled()
                                }
                                .padding(10)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                                .padding(.horizontal)
                                .padding(.bottom, 8)
                            }

                            if let lu = lastUpdated {
                                Text("Last updated: \(lu.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption2)
                                    .foregroundStyle(Theme.textSecondary)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
                                    .padding(.horizontal)
                                    .padding(.bottom, 4)
                            }

                            Divider().background(Theme.divider)

                            if isLoadingBoard && leaderboard.isEmpty {
                                ProgressView().tint(Theme.accent)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                            } else if viewMode == .rankings {
                                rankingsList
                            } else {
                                activityList
                            }
                        }
                    }
                }
            }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .task { await loadClubs() }
            .refreshable { await loadClubs() }
            .onChange(of: selectedClubIndex) { _, _ in
                Task { await loadLeaderboard() }
            }
            .sheet(item: $challengeTarget) { target in
                if let club = selectedClub,
                   let myMembership = leaderboard.first(where: { $0.userId == auth.currentUser?.uid }) {
                    SendChallengeView(club: club,
                                      challenger: myMembership,
                                      defendant: target)
                        .environmentObject(auth)
                }
            }
            .sheet(item: $profileTarget) { target in
                PublicProfileView(userId: target.id, clubContext: selectedClub)
                    .environmentObject(auth)
            }
            .sheet(item: $clubProfileTarget) { club in
                ClubPublicProfileView(club: club).environmentObject(auth)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    if let club = selectedClub {
                        Button { clubProfileTarget = club } label: {
                            Image(systemName: "info.circle").foregroundStyle(Theme.accent)
                                .accessibilityLabel("About \(club.name)")
                        }
                    }
                }
            }
        }
    }

    // MARK: Rankings list

    @ViewBuilder
    private var rankingsList: some View {
        if filtered.isEmpty {
            ContentUnavailableView("No members yet.", systemImage: "person.2")
                .foregroundStyle(Theme.textSecondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                Section {
                    Text("\(leaderboard.count) Member\(leaderboard.count == 1 ? "" : "s")")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
                ForEach(Array(filtered.enumerated()), id: \.element.id) { idx, member in
                    LeaderboardRowView(
                        rank: idx + 1,
                        membership: member,
                        isCurrentUser: member.userId == auth.currentUser?.uid,
                        onChallenge: { challengeTarget = member },
                        onTapName:   { profileTarget = ProfileTarget(id: member.userId) }
                    )
                    .listRowBackground(idx % 2 == 0 ? Theme.card : Theme.cardAlt)
                    .listRowSeparatorTint(Theme.divider)
                }
            }
            .darkListStyle()
        }
    }

    // MARK: Activity list — running list of tag swaps

    @ViewBuilder
    private var activityList: some View {
        let changes = tagChanges
        if changes.isEmpty {
            ContentUnavailableView(
                "No Activity Yet",
                systemImage: "arrow.left.arrow.right",
                description: Text("Tag swaps from completed rounds will appear here.")
            )
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(changes) { change in
                TagChangeRow(change: change)
                    .listRowBackground(Theme.card)
                    .listRowSeparatorTint(Theme.divider)
            }
            .darkListStyle()
        }
    }

    /// Expands every recent round into one row per player tag change, sorted newest first.
    private var tagChanges: [TagChange] {
        var out: [TagChange] = []
        for round in recentRounds {
            for pid in round.playerIds {
                let oldT = round.tagsBefore[pid] ?? 0
                let newT = round.tagsAfter[pid]  ?? 0
                let name = round.playerNames?[pid] ?? "Player"
                // Skip unchanged tags so the activity feed is meaningful
                guard oldT != newT, oldT > 0, newT > 0 else { continue }
                out.append(TagChange(
                    id: "\(round.id ?? UUID().uuidString)_\(pid)",
                    playerName: name,
                    oldTag: oldT,
                    newTag: newT,
                    date: round.playedAt
                ))
            }
        }
        return out.sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private var clubPicker: some View {
        if userClubs.count <= 3 {
            Picker("Club", selection: $selectedClubIndex) {
                ForEach(userClubs.indices, id: \.self) { i in
                    Text(userClubs[i].club.name).tag(i)
                }
            }
            .pickerStyle(.segmented)
            .colorMultiply(Theme.accent)
        } else {
            HStack {
                Text("Viewing:").font(.subheadline).foregroundStyle(Theme.textSecondary)
                Picker("Club", selection: $selectedClubIndex) {
                    ForEach(userClubs.indices, id: \.self) { i in
                        Text(userClubs[i].club.name).tag(i)
                    }
                }
                .pickerStyle(.menu).tint(Theme.accent)
            }
        }
    }

    private func loadClubs() async {
        guard let uid = auth.currentUser?.uid else { return }
        isLoadingClubs = true
        let memberships = (try? await service.fetchUserMemberships(userId: uid)) ?? []
        var items: [ClubWithMembership] = []
        for m in memberships {
            if let club = try? await service.fetchClub(id: m.clubId) {
                items.append(ClubWithMembership(club: club, membership: m))
            }
        }
        userClubs = items.sorted { $0.membership.tagNumber < $1.membership.tagNumber }
        if selectedClubIndex >= userClubs.count { selectedClubIndex = 0 }
        isLoadingClubs = false
        await loadLeaderboard()
    }

    private func loadLeaderboard() async {
        guard let clubId = selectedClub?.id else { leaderboard = []; return }
        isLoadingBoard = true
        async let lFetch = service.fetchLeaderboard(clubID: clubId)
        async let rFetch = service.fetchRecentRounds(clubId: clubId, limit: 20)
        leaderboard  = (try? await lFetch) ?? []
        recentRounds = (try? await rFetch) ?? []
        lastUpdated  = Date()
        isLoadingBoard = false
    }
}

// MARK: - LeaderboardRowView

struct LeaderboardRowView: View {
    let rank: Int
    let membership: Membership
    let isCurrentUser: Bool
    var onChallenge: (() -> Void)? = nil   // nil hides the button
    var onTapName:   (() -> Void)? = nil   // nil makes name non-tappable

    var body: some View {
        HStack(spacing: 14) {
            Text("#\(membership.tagNumber)")
                .font(.system(size: 17, weight: .black, design: .rounded))
                .monospacedDigit()
                .padding(.horizontal, 11).padding(.vertical, 7)
                .background(badgeColor.opacity(0.18), in: RoundedRectangle(cornerRadius: 9))
                .foregroundStyle(badgeColor)
                .frame(minWidth: 62, alignment: .center)

            Button { onTapName?() } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(membership.userFullName)
                        .fontWeight(isCurrentUser ? .bold : .regular)
                        .foregroundStyle(Theme.textPrimary)
                    if isCurrentUser {
                        Text("You").font(.caption2.bold()).foregroundStyle(Theme.accent)
                    }
                }
            }
            .buttonStyle(.plain)
            .disabled(onTapName == nil)

            Spacer()
            if let medal = medalEmoji { Text(medal).font(.title3) }
            if !isCurrentUser, let onChallenge {
                Button(action: onChallenge) {
                    HStack(spacing: 4) {
                        Image(systemName: "flag.checkered")
                            .font(.caption2)
                        Text("Challenge").font(.caption2.bold())
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
        .listRowBackground(isCurrentUser
                           ? Theme.accent.opacity(0.1)
                           : (rank % 2 == 0 ? Theme.card : Theme.cardAlt))
    }

    private var badgeColor: Color {
        switch rank {
        case 1:  return Theme.gold
        case 2:  return Color(white: 0.65)
        case 3:  return Color(hex: "CD7F32")
        default: return isCurrentUser ? Theme.accent : Theme.textSecondary
        }
    }
    private var medalEmoji: String? {
        switch rank { case 1: return "🏆"; case 2: return "🥈"; case 3: return "🥉"; default: return nil }
    }
}

// MARK: - TagChange / TagChangeRow
// Used by the Leaderboard's "Activity" tab — one row per player whose tag changed
// in a round. Same visual format as the post-round results screen.

struct TagChange: Identifiable {
    let id: String           // round-id + player-id, stable per change
    let playerName: String
    let oldTag: Int
    let newTag: Int
    let date: Date
}

struct TagChangeRow: View {
    let change: TagChange

    private var improved: Bool { change.newTag < change.oldTag }
    private var direction: String { improved ? "arrow.down" : "arrow.up" }
    private var color: Color { improved ? Theme.success : Theme.accent }

    var body: some View {
        HStack(spacing: 12) {
            // Tag swap visual
            HStack(spacing: 4) {
                Text("#\(change.oldTag)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: direction)
                    .font(.caption.bold())
                    .foregroundStyle(color)
                Text("#\(change.newTag)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(color)
            }
            .frame(width: 90, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(change.playerName)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Text(change.date.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
