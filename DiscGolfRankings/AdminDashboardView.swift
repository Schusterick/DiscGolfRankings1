import SwiftUI

// MARK: - AdminDashboardView

struct AdminDashboardView: View {
    let club: Club
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var selectedTab = 0
    @State private var showSubscription = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Subscription nudge banner (hidden when active + plenty of trial)
                    SubscriptionStatusBanner(club: club,
                                             onTap: { showSubscription = true })
                        .padding(.horizontal).padding(.top, 8)

                    TabView(selection: $selectedTab) {
                        MembersTabView(club: club)
                            .tabItem { Label("Members", systemImage: "person.3") }
                            .tag(0)
                        ClubSettingsTabView(club: club)
                            .tabItem { Label("Settings", systemImage: "gear") }
                            .tag(1)
                        ApplicationsTabView(club: club)
                            .tabItem { Label("Applications", systemImage: "tray.and.arrow.down") }
                            .tag(2)
                        PaymentsTabView(club: club)
                            .tabItem { Label("Payments", systemImage: "creditcard.fill") }
                            .tag(3)
                        EventsTabView(club: club)
                            .tabItem { Label("Events", systemImage: "calendar") }
                            .tag(4)
                    }
                    .tint(Theme.accent)
                }
            }
            .sheet(isPresented: $showSubscription) {
                ClubSubscriptionView(club: club).environmentObject(auth)
            }
            .navigationTitle("Admin Dashboard")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Tab 1: Members

struct MembersTabView: View {
    let club: Club
    private let service = FirebaseService.shared
    @EnvironmentObject var auth: AuthService

    @State private var members:    [Membership] = []
    @State private var isLoading   = false
    @State private var searchText  = ""
    @State private var errorMsg:   String?
    @State private var showBroadcast = false

    private var filtered: [Membership] {
        searchText.isEmpty ? members
            : members.filter { $0.userFullName.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                // Broadcast button
                Button { showBroadcast = true } label: {
                    Label("Message All Members", systemImage: "megaphone.fill")
                        .font(.subheadline.bold())
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal)
                .padding(.top, 8)

                // Search bar
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(Theme.textSecondary)
                    TextField("Search members…", text: $searchText)
                        .foregroundStyle(Theme.textPrimary)
                        .autocorrectionDisabled()
                }
                .padding(10)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                .padding(.horizontal)
                .padding(.vertical, 8)

                if let errorMsg {
                    Text(errorMsg).font(.caption).foregroundStyle(.red).padding(.horizontal)
                }

                // Count header
                Text("\(filtered.count) Member\(filtered.count == 1 ? "" : "s")")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.bottom, 4)

                if isLoading && members.isEmpty {
                    ProgressView().tint(Theme.accent).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(filtered) { member in
                        MemberAdminRow(member: member, club: club) {
                            await loadMembers()
                        }
                        .listRowBackground(Theme.card)
                        .listRowSeparatorTint(Theme.divider)
                    }
                    .darkListStyle()
                }
            }
        }
        .task { await loadMembers() }
        .refreshable { await loadMembers() }
        .sheet(isPresented: $showBroadcast) {
            BroadcastMessageSheet(club: club, memberCount: members.count)
        }
    }

    private func loadMembers() async {
        guard let clubId = club.id else { return }
        isLoading = true
        members = (try? await service.fetchClubMembers(clubId: clubId)) ?? []
        isLoading = false
    }
}

struct MemberAdminRow: View {
    let member: Membership
    let club: Club
    let onUpdate: () async -> Void
    private let service = FirebaseService.shared

    @State private var isRemoving  = false
    @State private var isPromoting = false

    var body: some View {
        HStack(spacing: 12) {
            // Tag badge
            Text("#\(member.tagNumber)")
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(Theme.gold)
                .frame(minWidth: 44)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Theme.gold.opacity(0.15), in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(member.userFullName)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.textPrimary)
                if let email = member.email {
                    Text(email).font(.caption).foregroundStyle(Theme.textSecondary)
                }
                if member.isAdmin == true {
                    Label("Admin", systemImage: "shield.fill")
                        .font(.caption2.bold())
                        .foregroundStyle(Theme.accent)
                }
            }

            Spacer()

            // Promote / Remove
            Menu {
                Button {
                    Task {
                        guard let mid = member.id, let cid = club.id else { return }
                        isPromoting = true
                        let makeAdmin = member.isAdmin != true
                        try? await service.setMemberAdmin(membershipId: mid, clubId: cid,
                                                          userId: member.userId, isAdmin: makeAdmin)
                        await onUpdate()
                        isPromoting = false
                    }
                } label: {
                    Label(member.isAdmin == true ? "Remove Admin" : "Make Admin",
                          systemImage: member.isAdmin == true ? "shield.slash" : "shield.fill")
                }

                Button(role: .destructive) {
                    Task {
                        guard let mid = member.id else { return }
                        isRemoving = true
                        try? await service.removeMember(membershipId: mid)
                        await onUpdate()
                        isRemoving = false
                    }
                } label: {
                    Label("Remove Member", systemImage: "person.badge.minus")
                }
            } label: {
                if isRemoving || isPromoting {
                    ProgressView().tint(Theme.accent)
                } else {
                    Image(systemName: "ellipsis.circle")
                        .foregroundStyle(Theme.textSecondary)
                        .font(.title3)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tab 2: Club Settings

struct ClubSettingsTabView: View {
    let club: Club
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var name             = ""
    @State private var location         = ""
    @State private var joinFeeStr       = "0"
    @State private var missionStatement = ""
    @State private var website          = ""
    @State private var contactEmail     = ""
    @State private var contactPhone     = ""
    @State private var logoURL          = ""
    @State private var foundedYearStr   = ""
    @State private var isSaving         = false
    @State private var showSuccess      = false
    @State private var errorMsg: String?
    @State private var showSubscription = false

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
            Form {
                Section("Club Identity") {
                    darkField("Club Name", text: $name)
                    darkField("Location (City, State)", text: $location)
                    darkField("Website", text: $website)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    darkField("Founded year (e.g. 2018)", text: $foundedYearStr)
                        .keyboardType(.numberPad)
                }
                .listRowBackground(Theme.card)

                Section(header: Text("Club Logo").foregroundStyle(Theme.textSecondary),
                        footer: Text("Tap the circle to upload from your camera roll. Shown on the club profile and in share previews.")
                                    .font(.caption2).foregroundStyle(Theme.textSecondary)) {
                    if let clubId = club.id {
                        VStack {
                            PhotoUploadAvatar(
                                storagePath: "clubs/\(clubId)/logo.jpg",
                                photoURL: $logoURL,
                                initials: String(name.prefix(2)).uppercased(),
                                diameter: 96
                            )
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                }
                .listRowBackground(Theme.card)

                Section("Mission Statement") {
                    TextField("Describe your club…", text: $missionStatement, axis: .vertical)
                        .lineLimit(3...6)
                        .foregroundStyle(Theme.textPrimary)
                }
                .listRowBackground(Theme.card)

                Section("Public Contact Info") {
                    darkField("Contact email", text: $contactEmail)
                        .keyboardType(.emailAddress)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    darkField("Contact phone", text: $contactPhone)
                        .keyboardType(.phonePad)
                }
                .listRowBackground(Theme.card)

                Section("Subscription") {
                    Button { showSubscription = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Manage Subscription")
                                    .foregroundStyle(Theme.textPrimary)
                                Text(club.subscriptionState.label)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .listRowBackground(Theme.card)

                Section(header: Text("Membership Fee").foregroundStyle(Theme.textSecondary)) {
                    HStack {
                        Text("$").foregroundStyle(Theme.textSecondary)
                        TextField("0", text: $joinFeeStr)
                            .keyboardType(.decimalPad)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    Text(joinFeeStr == "0" || joinFeeStr.isEmpty
                         ? "Free to join" : "Members pay $\(joinFeeStr) to join")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                .listRowBackground(Theme.card)

                if let errorMsg {
                    Section { Text(errorMsg).foregroundStyle(.red).font(.caption) }
                        .listRowBackground(Theme.card)
                }
            }
            .darkListStyle()

            // Sticky bottom action bar — explicit Cancel + Save
            HStack(spacing: 10) {
                Button(role: .cancel) { dismiss() } label: {
                    Text("Cancel")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.divider, lineWidth: 1))
                }

                Button { Task { await save() } } label: {
                    Group {
                        if isSaving {
                            ProgressView().tint(.white)
                        } else if showSuccess {
                            Label("Saved!", systemImage: "checkmark.circle.fill")
                                .font(.headline)
                                .foregroundStyle(.white)
                        } else {
                            Text("Save")
                                .font(.headline)
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(showSuccess ? Theme.success : Theme.accent,
                                in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(isSaving)
                .animation(.easeInOut(duration: 0.2), value: showSuccess)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)
            .background(Theme.background)
            }
        }
        .onAppear {
            name             = club.name
            location         = club.location
            joinFeeStr       = String(format: "%.0f", club.joinFee ?? 0)
            missionStatement = club.missionStatement ?? ""
            website          = club.website ?? ""
            contactEmail     = club.contactEmail ?? ""
            contactPhone     = club.contactPhone ?? ""
            logoURL          = club.logoURL ?? ""
            foundedYearStr   = club.foundedYear.map { String($0) } ?? ""
        }
        .sheet(isPresented: $showSubscription) {
            ClubSubscriptionView(club: club)
        }
    }

    @ViewBuilder
    private func darkField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .foregroundStyle(Theme.textPrimary)
    }

    private func save() async {
        guard let clubId = club.id else {
            errorMsg = "Cannot save — club ID is missing."
            return
        }
        isSaving = true
        errorMsg = nil
        let fee = Double(joinFeeStr) ?? 0
        do {
            try await service.updateClub(clubId: clubId, name: name, location: location,
                                         joinFee: fee, missionStatement: missionStatement,
                                         website: website,
                                         contactEmail: contactEmail.trimmingCharacters(in: .whitespaces),
                                         contactPhone: contactPhone.trimmingCharacters(in: .whitespaces),
                                         logoURL: logoURL.trimmingCharacters(in: .whitespaces),
                                         foundedYear: Int(foundedYearStr.trimmingCharacters(in: .whitespaces)))
            isSaving = false
            // Flash the green "Saved!" button for 2 seconds, then revert.
            withAnimation { showSuccess = true }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            withAnimation { showSuccess = false }
        } catch {
            errorMsg = "Save failed: \(error.localizedDescription)"
            isSaving = false
        }
    }
}

// MARK: - Tab 3: Applications

struct ApplicationsTabView: View {
    let club: Club
    private let service = FirebaseService.shared

    @State private var requests:  [JoinRequest] = []
    @State private var isLoading  = false
    @State private var processingId: String?

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            Group {
                if let fee = club.joinFee, fee == 0 {
                    ContentUnavailableView(
                        "Free Club",
                        systemImage: "checkmark.circle",
                        description: Text("This is a free club. Members join instantly — no approval needed.")
                    )
                    .foregroundStyle(Theme.textSecondary)
                } else if isLoading && requests.isEmpty {
                    ProgressView().tint(Theme.accent)
                } else if requests.isEmpty {
                    ContentUnavailableView(
                        "No Pending Applications",
                        systemImage: "tray",
                        description: Text("All requests have been reviewed.")
                    )
                    .foregroundStyle(Theme.textSecondary)
                } else {
                    List(requests) { req in
                        JoinRequestRow(
                            request: req,
                            isProcessing: processingId == req.id
                        ) { approve in
                            await handle(request: req, approve: approve)
                        }
                        .listRowBackground(Theme.card)
                        .listRowSeparatorTint(Theme.divider)
                    }
                    .darkListStyle()
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
    }

    private func load() async {
        guard let clubId = club.id else { return }
        isLoading = true
        requests  = (try? await service.fetchJoinRequests(clubId: clubId)) ?? []
        isLoading = false
    }

    private func handle(request: JoinRequest, approve: Bool) async {
        processingId = request.id
        if approve {
            try? await service.approveJoinRequest(request)
        } else {
            if let rid = request.id { try? await service.denyJoinRequest(requestId: rid) }
        }
        await load()
        processingId = nil
    }
}

struct JoinRequestRow: View {
    let request: JoinRequest
    let isProcessing: Bool
    let onAction: (Bool) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(request.userFullName)
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text(request.userEmail)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(request.requestedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
            }

            HStack(spacing: 10) {
                Button(role: .destructive) {
                    Task { await onAction(false) }
                } label: {
                    Text(isProcessing ? "" : "Deny")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay { if isProcessing { ProgressView().tint(.white) } }
                }
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.8))
                .disabled(isProcessing)

                Button {
                    Task { await onAction(true) }
                } label: {
                    Text(isProcessing ? "" : "Approve")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .overlay { if isProcessing { ProgressView().tint(.white) } }
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.success)
                .disabled(isProcessing)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Tab 4: Payments

struct PaymentsTabView: View {
    let club: Club
    private let service = FirebaseService.shared

    @EnvironmentObject var auth: AuthService

    @State private var currentClub:         Club?
    @State private var isLoading            = false
    @State private var isSaving             = false
    @State private var joinFeeStr           = ""
    @State private var isLoadingOnboarding  = false
    @State private var showStripeOnboarding = false
    @State private var onboardingURL:        URL?
    @State private var errorMsg:             String?

    private var displayClub:      Club { currentClub ?? club }
    private var isPaid:           Bool { (displayClub.joinFee ?? 0) > 0 }
    private var hasStripeAccount: Bool {
        guard let id = displayClub.stripeConnectedAccountId else { return false }
        return !id.isEmpty
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if isLoading {
                ProgressView().tint(Theme.accent)
            } else if !isPaid {
                enablePaymentsView
            } else if !hasStripeAccount {
                connectBankView
            } else {
                paymentsActiveView
            }
        }
        .task { await loadClub() }
        .refreshable { await loadClub() }
        .sheet(isPresented: $showStripeOnboarding, onDismiss: { Task { await loadClub() } }) {
            if let url = onboardingURL {
                SafariView(url: url).ignoresSafeArea()
            }
        }
    }

    // MARK: State 1 — Free Club

    private var enablePaymentsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                VStack(spacing: 10) {
                    Image(systemName: "dollarsign.circle.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(Theme.gold)
                        .shadow(color: Theme.gold.opacity(0.3), radius: 12)
                    Text("Enable Paid Memberships")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Charge a one-time fee for members to join your club.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 28)

                // Fee input
                VStack(alignment: .leading, spacing: 8) {
                    Text("MEMBERSHIP FEE")
                        .font(.caption.bold())
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: 8) {
                        Text("$").foregroundStyle(Theme.textSecondary).font(.title.bold())
                        TextField("0", text: $joinFeeStr)
                            .foregroundStyle(Theme.textPrimary)
                            .font(.title.bold())
                            .keyboardType(.decimalPad)
                    }
                    .padding(14)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.divider, lineWidth: 1))

                    if let fee = Double(joinFeeStr), fee > 0 {
                        Label(String(format: "Club keeps 100%% — $%.2f per member", fee),
                              systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(Theme.success)
                    }
                }

                // Info card — flat-fee model, no per-transaction cut
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Theme.accent).font(.headline)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Club Keeps 100%")
                            .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                        Text("DiscGolfRankings does NOT take a percentage of member payments. Your club receives every dollar members pay you. The platform is funded by a flat $\(Int(Config.clubSubscriptionAnnualFee))/year club subscription.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(14)
                .background(Theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))

                if let errorMsg { Text(errorMsg).font(.caption).foregroundStyle(.red) }

                Button { Task { await enablePayments() } } label: {
                    Group {
                        if isSaving { ProgressView().tint(.white) }
                        else {
                            Text("Enable Paid Memberships")
                                .font(.headline).foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(
                        (Double(joinFeeStr) ?? 0) > 0 ? Theme.accent : Theme.accent.opacity(0.4),
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .disabled((Double(joinFeeStr) ?? 0) <= 0 || isSaving)
            }
            .padding(24)
        }
    }

    // MARK: State 2 — Paid, no Stripe account

    private var connectBankView: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange).font(.title3)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Action Required")
                            .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                        Text("Connect your bank to start receiving payments.")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                }
                .padding(14)
                .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 24)

                VStack(spacing: 4) {
                    Text(String(format: "$%.0f", displayClub.joinFee ?? 0))
                        .font(.system(size: 52, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.gold)
                    Text("Current membership fee")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }

                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "info.circle.fill").foregroundStyle(Theme.accent)
                    Text("You receive 100% of every membership payment. Stripe handles payouts, fraud protection, and compliance. DiscGolfRankings is funded by a flat $\(Int(Config.clubSubscriptionAnnualFee))/year club subscription — no per-transaction cut.")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                }
                .padding(14)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))

                if let errorMsg { Text(errorMsg).font(.caption).foregroundStyle(.red) }

                Button { Task { await openStripeOnboarding() } } label: {
                    Group {
                        if isLoadingOnboarding { ProgressView().tint(.white) }
                        else {
                            Label("Connect Bank Account", systemImage: "building.columns.fill")
                                .font(.headline).foregroundStyle(.white)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(isLoadingOnboarding)

                HStack(spacing: 6) {
                    Image(systemName: "lock.fill").font(.caption2).foregroundStyle(Theme.textSecondary)
                    Text("Secured by Stripe Connect").font(.caption2).foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(24)
        }
    }

    // MARK: State 3 — Stripe connected & active

    private var paymentsActiveView: some View {
        ScrollView {
            VStack(spacing: 20) {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.success)
                    Text("Payments Active").font(.headline.bold()).foregroundStyle(Theme.success)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Theme.success.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                .padding(.top, 24)

                // Stats row
                HStack(spacing: 0) {
                    payStat(String(format: "$%.2f", displayClub.totalRevenue ?? 0), label: "Revenue")
                    Divider().frame(height: 40).background(Theme.divider)
                    payStat("$0.00", label: "Pending")      // TODO: fetch from Stripe API
                    Divider().frame(height: 40).background(Theme.divider)
                    payStat(String(format: "$%.0f", displayClub.joinFee ?? 0), label: "Join Fee")
                }
                .padding(.vertical, 12)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))

                // TODO: Replace with real payout data from payments collection once live
                Text("Live payout data will appear here after real Stripe payments are processed.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center).padding(.horizontal)

                // Stripe Express Dashboard
                Button {
                    let accountId = displayClub.stripeConnectedAccountId ?? ""
                    // TODO: Use Stripe's Express Dashboard link for production
                    if let url = URL(string: "https://dashboard.stripe.com/express/\(accountId)") {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Label("View Stripe Dashboard", systemImage: "arrow.up.right.square.fill")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color(hex: "635BFF"), in: RoundedRectangle(cornerRadius: 14))
                }

                if let accountId = displayClub.stripeConnectedAccountId {
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.shield.fill")
                            .foregroundStyle(Theme.success).font(.caption2)
                        Text("Stripe account: \(accountId.prefix(20))…")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func payStat(_ value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 16, weight: .black, design: .rounded))
                .foregroundStyle(Theme.gold)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Actions

    private func loadClub() async {
        guard let clubId = club.id else { return }
        isLoading = true
        currentClub = try? await service.fetchClub(id: clubId)
        isLoading = false
    }

    private func enablePayments() async {
        guard let clubId = club.id else { return }
        let fee = Double(joinFeeStr) ?? 0
        guard fee > 0 else { return }
        isSaving = true; errorMsg = nil
        do {
            try await service.updateClub(clubId: clubId, name: displayClub.name,
                                         location: displayClub.location, joinFee: fee,
                                         missionStatement: displayClub.missionStatement ?? "",
                                         website: "")
            try await service.setPaymentsEnabled(clubId: clubId, enabled: true)
            await loadClub()
        } catch { errorMsg = error.localizedDescription }
        isSaving = false
    }

    private func openStripeOnboarding() async {
        guard let clubId = club.id else { return }
        let email = auth.currentUser?.email ?? ""
        isLoadingOnboarding = true; errorMsg = nil
        do {
            // Step 1 — Create (or retrieve) Stripe Connect account
            let accountId = try await CloudFunctions.createConnectAccount(email: email, clubId: clubId)
            // Step 2 — Persist account ID in Firestore
            try await service.updateStripeConnectedAccount(clubId: clubId, accountId: accountId)
            // Step 3 — Fetch hosted onboarding URL
            let url = try await CloudFunctions.getConnectAccountLink(accountId: accountId, clubId: clubId)
            onboardingURL        = url
            showStripeOnboarding = true
            await loadClub()
        } catch { errorMsg = error.localizedDescription }
        isLoadingOnboarding = false
    }
}

// MARK: - BroadcastMessageSheet
// Opened from the Members tab. Lets the club admin send a single in-app notification
// to every active member of the club at once.

struct BroadcastMessageSheet: View {
    let club: Club
    let memberCount: Int

    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var message:  String = ""
    @State private var isSending = false
    @State private var sentCount = 0
    @State private var errorMsg: String?
    @State private var showSuccess = false

    private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool   { !trimmed.isEmpty && !isSending && memberCount > 0 }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Form {
                    Section {
                        HStack(spacing: 12) {
                            Image(systemName: "megaphone.fill").foregroundStyle(Theme.accent)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(club.name).font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                                Text("\(memberCount) member\(memberCount == 1 ? "" : "s") will be notified")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .listRowBackground(Theme.card)

                    Section("Message") {
                        TextField("e.g. League night this Saturday at 10am!",
                                  text: $message, axis: .vertical)
                            .lineLimit(3...8)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .listRowBackground(Theme.card)

                    Section {
                        Label("Each member sees this in their bell-icon notifications. No email is sent.",
                              systemImage: "info.circle")
                            .font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Theme.card)

                    if let errorMsg {
                        Section { Text(errorMsg).foregroundStyle(.red).font(.caption) }
                            .listRowBackground(Theme.card)
                    }

                    Section {
                        Button { Task { await send() } } label: {
                            Group {
                                if isSending { ProgressView().tint(.white) }
                                else { Text("Send to \(memberCount) Member\(memberCount == 1 ? "" : "s")")
                                        .fontWeight(.semibold).foregroundStyle(.white) }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .disabled(!canSend)
                    }
                    .listRowBackground(canSend ? Theme.accent.opacity(0.85) : Theme.accent.opacity(0.3))
                }
                .darkListStyle()
            }
            .navigationTitle("Broadcast")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
            .alert("Sent!", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("Delivered to \(sentCount) member\(sentCount == 1 ? "" : "s").")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func send() async {
        guard let clubId = club.id else { return }
        isSending = true; errorMsg = nil
        do {
            sentCount = try await service.sendNotificationToAllClubMembers(
                clubId:  clubId,
                message: "📣 \(club.name): \(trimmed)"
            )
            showSuccess = true
        } catch {
            errorMsg = error.localizedDescription
        }
        isSending = false
    }
}

// MARK: - Tab 5: Events

struct EventsTabView: View {
    let club: Club
    private let service = FirebaseService.shared

    @EnvironmentObject var auth: AuthService

    @State private var events:       [Event] = []
    @State private var isLoading     = false
    @State private var showCreate    = false
    @State private var managingEvent: Event?
    @State private var errorMsg:      String?

    private var upcoming:  [Event] { events.filter { $0.status == .upcoming  }.sorted { $0.startDate < $1.startDate } }
    private var completed: [Event] { events.filter { $0.status == .completed }.sorted { $0.startDate > $1.startDate } }
    private var cancelled: [Event] { events.filter { $0.status == .cancelled }.sorted { $0.startDate > $1.startDate } }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 0) {
                Button { showCreate = true } label: {
                    Label("Create Event", systemImage: "plus.circle.fill")
                        .font(.subheadline.bold()).foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                }
                .padding(.horizontal).padding(.top, 8)

                if isLoading && events.isEmpty {
                    ProgressView().tint(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if events.isEmpty {
                    ContentUnavailableView(
                        "No Events Yet",
                        systemImage: "calendar",
                        description: Text("Create a league or tournament to get started.")
                    )
                    .foregroundStyle(Theme.textSecondary)
                } else {
                    List {
                        if !upcoming.isEmpty {
                            Section("Upcoming (\(upcoming.count))") {
                                ForEach(upcoming) { e in
                                    Button { managingEvent = e } label: {
                                        EventListRow(event: e, showStatus: false)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Theme.card)
                                    .listRowSeparatorTint(Theme.divider)
                                }
                            }
                        }
                        if !completed.isEmpty {
                            Section("Completed (\(completed.count))") {
                                ForEach(completed) { e in
                                    Button { managingEvent = e } label: {
                                        EventListRow(event: e)
                                    }
                                    .buttonStyle(.plain)
                                    .listRowBackground(Theme.card)
                                    .listRowSeparatorTint(Theme.divider)
                                }
                            }
                        }
                        if !cancelled.isEmpty {
                            Section("Cancelled") {
                                ForEach(cancelled) { e in
                                    EventListRow(event: e)
                                        .listRowBackground(Theme.card)
                                        .listRowSeparatorTint(Theme.divider)
                                }
                            }
                        }
                    }
                    .darkListStyle()
                }
            }
        }
        .task { await load() }
        .refreshable { await load() }
        .sheet(isPresented: $showCreate, onDismiss: { Task { await load() } }) {
            CreateEventView(club: club).environmentObject(auth)
        }
        .sheet(item: $managingEvent, onDismiss: { Task { await load() } }) { event in
            EventManageView(event: event, club: club).environmentObject(auth)
        }
    }

    private func load() async {
        guard let clubId = club.id else { return }
        isLoading = true
        events = (try? await service.fetchEvents(clubId: clubId)) ?? []
        isLoading = false
    }
}
