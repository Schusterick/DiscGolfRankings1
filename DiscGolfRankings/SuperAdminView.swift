import SwiftUI

// MARK: - SuperAdminView
// Shown in place of the standard AdminTabView when the signed-in user's email is in
// AuthService.superAdminEmails. Gives full control over every club, user, and round.

struct SuperAdminView: View {
    @EnvironmentObject var auth: AuthService
    @State private var selectedTab = 0

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                TabView(selection: $selectedTab) {
                    SuperAdminClubsTab()
                        .tabItem { Label("Clubs", systemImage: "person.3.fill") }
                        .tag(0)
                    SuperAdminRoundsTab()
                        .tabItem { Label("Rounds", systemImage: "flag.checkered") }
                        .tag(1)
                    SuperAdminUsersTab()
                        .tabItem { Label("Users", systemImage: "person.text.rectangle") }
                        .tag(2)
                    AdminTabView()        // existing club applications view, reused
                        .tabItem { Label("Apps", systemImage: "tray.and.arrow.down") }
                        .tag(3)
                }
                .tint(Theme.accent)
            }
            .navigationTitle("Super Admin")
            .navigationBarTitleDisplayMode(.large)
            .darkNavBar()
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Tab 1: All Clubs

struct SuperAdminClubsTab: View {
    @EnvironmentObject var auth: AuthService
    private let service = FirebaseService.shared

    @State private var clubs:        [Club] = []
    @State private var isLoading     = false
    @State private var searchText    = ""
    @State private var editingClub:  Club?
    @State private var adminingClub: Club?
    @State private var deletingClub: Club?
    @State private var showDeleteConfirm = false
    @State private var errorMsg:    String?
    @State private var showResetConfirm = false
    @State private var isResetting       = false
    @State private var resetMessage:     String?

    private var filtered: [Club] {
        searchText.isEmpty ? clubs
            : clubs.filter { $0.name.localizedCaseInsensitiveContains(searchText)
                          || $0.location.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {

                // Reset trials — gold pill button, prominent
                Button { showResetConfirm = true } label: {
                    HStack(spacing: 8) {
                        if isResetting {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "arrow.clockwise.circle.fill")
                            Text("Reset Trials for All Clubs (\(Config.clubTrialDurationDays) days)")
                        }
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.gold, in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isResetting)
                .padding(.horizontal).padding(.top, 8)

                if let resetMessage {
                    Text(resetMessage)
                        .font(.caption.bold()).foregroundStyle(Theme.success)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal).padding(.top, 6)
                }

                // Search
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Search clubs…", text: $searchText)
                        .foregroundStyle(Theme.textPrimary)
                        .autocorrectionDisabled()
                }
                .padding(10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal).padding(.vertical, 8)

                if let errorMsg {
                    Text(errorMsg).font(.caption).foregroundStyle(.red).padding(.horizontal)
                }

                Text("\(filtered.count) Club\(filtered.count == 1 ? "" : "s")")
                    .font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 4)

                if isLoading && clubs.isEmpty {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView("No clubs", systemImage: "tag.slash")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    List(filtered) { club in
                        SuperAdminClubRow(
                            club: club,
                            onEditFee: { editingClub = club },
                            onOpenAdmin: { adminingClub = club },
                            onDelete: { deletingClub = club; showDeleteConfirm = true }
                        )
                        .listRowBackground(Theme.card)
                        .listRowSeparatorTint(Theme.divider)
                    }
                    .darkListStyle()
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(item: $editingClub, onDismiss: { Task { await load() } }) { club in
            SuperAdminFeeEditor(club: club).environmentObject(auth)
        }
        .sheet(item: $adminingClub, onDismiss: { Task { await load() } }) { club in
            AdminDashboardView(club: club).environmentObject(auth)
        }
        .confirmationDialog(
            "Reset trials for every club?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset All Trials", role: .destructive) {
                Task { await resetTrials() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Every club gets a fresh \(Config.clubTrialDurationDays)-day free trial starting today. Active subscriptions will be reverted to trial — use this only at launch to grandfather existing clubs in.")
        }
        .confirmationDialog(
            "Permanently delete \(deletingClub?.name ?? "club")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete Club & All Data", role: .destructive) {
                Task { await deleteClub() }
            }
            Button("Cancel", role: .cancel) { deletingClub = nil }
        } message: {
            Text("This removes the club, every membership, every pending round, and every join request. This cannot be undone.")
        }
    }

    private func load() async {
        isLoading = true
        errorMsg  = nil
        do { clubs = try await service.fetchAllClubsForSuperAdmin() }
        catch { errorMsg = error.localizedDescription }
        isLoading = false
    }

    private func deleteClub() async {
        guard let club = deletingClub, let clubId = club.id else { return }
        errorMsg = nil
        do {
            try await service.superAdminDeleteClub(clubId: clubId)
            await load()
        } catch { errorMsg = error.localizedDescription }
        deletingClub = nil
    }

    private func resetTrials() async {
        isResetting = true; resetMessage = nil; errorMsg = nil
        do {
            let count = try await service.resetTrialsForAllClubs()
            resetMessage = "Reset \(count) club\(count == 1 ? "" : "s") to a fresh \(Config.clubTrialDurationDays)-day trial."
            await load()
        } catch {
            errorMsg = error.localizedDescription
        }
        isResetting = false
        // Auto-clear the success message after 4 seconds so it doesn't linger
        Task {
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            resetMessage = nil
        }
    }
}

struct SuperAdminClubRow: View {
    let club: Club
    let onEditFee:    () -> Void
    let onOpenAdmin:  () -> Void
    let onDelete:     () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(club.name)
                        .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                    Text(club.location)
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 8) {
                        Text(club.status.rawValue.uppercased())
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(statusColor(club.status).opacity(0.15), in: Capsule())
                            .foregroundStyle(statusColor(club.status))
                        Text("\(club.memberCount) members")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                        if let fee = club.joinFee, fee > 0 {
                            Text(String(format: "$%.0f", fee))
                                .font(.caption2.bold()).foregroundStyle(Theme.gold)
                        }
                    }
                }
                Spacer()
                Menu {
                    Button { onOpenAdmin() } label: {
                        Label("Open Admin Dashboard", systemImage: "shield.fill")
                    }
                    Button { onEditFee() } label: {
                        Label("Edit Join Fee", systemImage: "dollarsign.circle")
                    }
                    Button(role: .destructive) { onDelete() } label: {
                        Label("Delete Club", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Theme.textSecondary).font(.title3)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusColor(_ s: Club.ClubStatus) -> Color {
        switch s {
        case .approved: return Theme.success
        case .pending:  return Theme.gold
        case .rejected: return .red
        }
    }
}

// MARK: - Fee Editor Sheet

struct SuperAdminFeeEditor: View {
    let club: Club
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var feeStr      = ""
    @State private var isSaving    = false
    @State private var errorMsg:    String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Form {
                    Section("Current") {
                        HStack {
                            Text(club.name).foregroundStyle(Theme.textPrimary)
                            Spacer()
                            Text(String(format: "$%.2f", club.joinFee ?? 0))
                                .foregroundStyle(Theme.gold)
                        }
                    }
                    .listRowBackground(Theme.card)

                    Section("New Join Fee") {
                        HStack {
                            Text("$").foregroundStyle(Theme.textSecondary)
                            TextField("0", text: $feeStr)
                                .foregroundStyle(Theme.textPrimary)
                                .keyboardType(.decimalPad)
                        }
                    }
                    .listRowBackground(Theme.card)

                    if let errorMsg {
                        Section { Text(errorMsg).foregroundStyle(.red).font(.caption) }
                            .listRowBackground(Theme.card)
                    }

                    Section {
                        Button { Task { await save() } } label: {
                            Group {
                                if isSaving { ProgressView().tint(.white) }
                                else { Text("Save").fontWeight(.semibold).foregroundStyle(.white) }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .disabled(isSaving)
                    }
                    .listRowBackground(Theme.accent.opacity(0.85))
                }
                .darkListStyle()
            }
            .navigationTitle("Edit Fee")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
            .onAppear { feeStr = String(format: "%.2f", club.joinFee ?? 0) }
        }
        .preferredColorScheme(.dark)
    }

    private func save() async {
        guard let clubId = club.id else { return }
        let fee = Double(feeStr) ?? 0
        isSaving = true; errorMsg = nil
        do {
            try await service.setClubJoinFee(clubId: clubId, fee: fee)
            dismiss()
        } catch { errorMsg = error.localizedDescription }
        isSaving = false
    }
}

// MARK: - Tab 2: All Pending Rounds

struct SuperAdminRoundsTab: View {
    private let service = FirebaseService.shared

    @State private var rounds:      [PendingRound] = []
    @State private var isLoading    = false
    @State private var processingId: String?
    @State private var errorMsg:    String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if isLoading && rounds.isEmpty {
                ProgressView().tint(Theme.accent)
            } else if rounds.isEmpty {
                ContentUnavailableView(
                    "No Pending Rounds",
                    systemImage: "checkmark.seal.fill",
                    description: Text("Every round across every club has been confirmed.")
                )
                .foregroundStyle(Theme.textSecondary)
            } else {
                List(rounds) { round in
                    SuperAdminRoundRow(
                        round: round,
                        isProcessing: processingId == round.id,
                        onForce:      { await force(round) }
                    )
                    .listRowBackground(Theme.card)
                    .listRowSeparatorTint(Theme.divider)
                }
                .darkListStyle()
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .overlay(alignment: .top) {
            if let errorMsg {
                Text(errorMsg).font(.caption).foregroundStyle(.red).padding()
            }
        }
    }

    private func load() async {
        isLoading = true; errorMsg = nil
        do { rounds = try await service.fetchAllPendingRoundsForSuperAdmin() }
        catch { errorMsg = error.localizedDescription }
        isLoading = false
    }

    private func force(_ round: PendingRound) async {
        processingId = round.id
        errorMsg = nil
        do {
            try await service.superAdminForceConfirmRound(round)
            await load()
        } catch { errorMsg = error.localizedDescription }
        processingId = nil
    }
}

struct SuperAdminRoundRow: View {
    let round: PendingRound
    let isProcessing: Bool
    let onForce: () async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Submitted by \(round.submittedByName)")
                        .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                    Text(round.submittedAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text("\(round.awaitingCount()) pending")
                    .font(.caption.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(Theme.gold.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.gold)
            }

            // Players & score summary
            ForEach(round.playerIds, id: \.self) { pid in
                let name  = round.playerNames[pid] ?? "Player"
                let score = round.scores[pid] ?? 0
                let oldT  = round.tagsBefore[pid] ?? 0
                let newT  = round.tagsAfter[pid] ?? 0
                HStack {
                    Text(name).font(.caption).foregroundStyle(Theme.textPrimary)
                    Spacer()
                    Text("\(score)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary).frame(width: 36)
                    Text("#\(oldT) → #\(newT)")
                        .font(.caption.bold().monospacedDigit())
                        .foregroundStyle(newT < oldT ? Theme.success : (newT > oldT ? Theme.accent : Theme.textPrimary))
                }
            }

            Button { Task { await onForce() } } label: {
                Group {
                    if isProcessing { ProgressView().tint(.white) }
                    else { Label("Force Confirm All Players", systemImage: "checkmark.shield.fill") }
                }
                .font(.caption.bold()).foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
            }
            .disabled(isProcessing)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tab 3: All Users

struct SuperAdminUsersTab: View {
    private let service = FirebaseService.shared

    @State private var users:      [AppUser] = []
    @State private var isLoading   = false
    @State private var searchText  = ""
    @State private var errorMsg:    String?
    @State private var isBackfilling      = false
    @State private var backfillMessage:   String?
    @State private var showBackfillConfirm = false

    private var filtered: [AppUser] {
        searchText.isEmpty ? users
            : users.filter { $0.displayName.localizedCaseInsensitiveContains(searchText)
                          || $0.email.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {

                // Backfill World Rankings — only useful for first-time setup
                Button { showBackfillConfirm = true } label: {
                    HStack(spacing: 8) {
                        if isBackfilling {
                            ProgressView().tint(.black)
                        } else {
                            Image(systemName: "globe.americas.fill")
                            Text("Backfill World Rankings")
                        }
                    }
                    .font(.subheadline.bold())
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.gold, in: RoundedRectangle(cornerRadius: 10))
                }
                .disabled(isBackfilling)
                .padding(.horizontal).padding(.top, 8)

                if let backfillMessage {
                    Text(backfillMessage)
                        .font(.caption.bold()).foregroundStyle(Theme.success)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.horizontal).padding(.top, 6)
                }

                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Search users…", text: $searchText)
                        .foregroundStyle(Theme.textPrimary)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal).padding(.vertical, 8)

                Text("\(filtered.count) User\(filtered.count == 1 ? "" : "s")")
                    .font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal).padding(.bottom, 4)

                if let errorMsg {
                    Text(errorMsg).font(.caption).foregroundStyle(.red).padding(.horizontal)
                }

                if isLoading && users.isEmpty {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filtered.isEmpty {
                    ContentUnavailableView("No users", systemImage: "person.slash")
                        .foregroundStyle(Theme.textSecondary)
                } else {
                    List(filtered) { user in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(user.displayName)
                                .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                            Text(user.email)
                                .font(.caption).foregroundStyle(Theme.textSecondary)
                            Text("Joined \(user.createdAt.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption2).foregroundStyle(Theme.textSecondary)
                        }
                        .padding(.vertical, 4)
                        .listRowBackground(Theme.card)
                        .listRowSeparatorTint(Theme.divider)
                    }
                    .darkListStyle()
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .alert("Backfill World Rankings?", isPresented: $showBackfillConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Backfill", role: .destructive) { Task { await backfillWorldRankings() } }
        } message: {
            Text("Assigns every user a World Ranking based on signup order (earliest = #1). Overwrites any existing ranks. Run once before launch.")
        }
    }

    private func load() async {
        isLoading = true; errorMsg = nil
        do { users = try await service.fetchAllUsers() }
        catch { errorMsg = error.localizedDescription }
        isLoading = false
    }

    /// Assigns sequential worldRank values to every user, ordered by createdAt ascending,
    /// then writes the final count back to meta/worldRankCounter so new signups continue
    /// from N+1.
    private func backfillWorldRankings() async {
        isBackfilling = true; backfillMessage = nil; errorMsg = nil
        defer { isBackfilling = false }
        do {
            let count = try await service.backfillWorldRankings()
            backfillMessage = "Assigned ranks to \(count) user\(count == 1 ? "" : "s")."
            await load()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
