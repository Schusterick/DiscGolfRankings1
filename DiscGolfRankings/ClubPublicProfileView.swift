import SwiftUI

// MARK: - ClubPublicProfileView
// Sharable club page. Anyone (even non-members) can view this — admins paste the
// share link on socials to attract new members. Club members see RSVP buttons on
// upcoming events.

struct ClubPublicProfileView: View {
    let club: Club

    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var admin:           AppUser?
    @State private var events:          [Event] = []
    @State private var amMember:        Bool    = false
    @State private var pendingRequest:  JoinRequest?
    @State private var isLoading        = false
    @State private var isJoining        = false
    @State private var openEvent:       Event?
    @State private var showPaymentView  = false
    @State private var joinErrorMsg:    String?

    private var feeLabel: String {
        if let fee = club.joinFee, fee > 0 {
            return String(format: "$%.0f to join", fee)
        }
        return "Free to join"
    }

    private var shareURL: URL? {
        guard let id = club.id else { return nil }
        return URL(string: "discgolfranks://club/\(id)")
    }

    private var shareText: String {
        "Check out \(club.name) on DiscGolfRankings — \(feeLabel)."
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.homeGradient.ignoresSafeArea()
                ScrollView {
                    VStack(spacing: 22) {
                        header
                        statRow
                        joinBlock
                        if let mission = club.missionStatement, !mission.isEmpty {
                            section("Mission") {
                                Text(mission)
                                    .font(.body)
                                    .foregroundStyle(Theme.textPrimary)
                            }
                        }
                        adminBlock
                        contactBlock
                        eventsBlock
                    }
                    .padding(.vertical, 24)
                    .padding(.horizontal, 20)
                }
            }
            .navigationTitle("Club Profile")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(Theme.accent)
                }
                ToolbarItem(placement: .primaryAction) {
                    if let url = shareURL {
                        ShareLink(item: url, message: Text(shareText)) {
                            Image(systemName: "square.and.arrow.up").foregroundStyle(Theme.accent)
                        }
                    }
                }
            }
            .task { await load() }
            .sheet(item: $openEvent) { event in
                EventDetailView(event: event, club: club, isClubMember: amMember)
                    .environmentObject(auth)
            }
            .sheet(isPresented: $showPaymentView, onDismiss: { Task { await load() } }) {
                PaymentPreviewView(club: club).environmentObject(auth)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Join block

    private var hasFee:          Bool { (club.joinFee ?? 0) > 0 }
    private var stripeConnected: Bool {
        guard let id = club.stripeConnectedAccountId else { return false }
        return !id.isEmpty
    }

    @ViewBuilder
    private var joinBlock: some View {
        if auth.currentUser == nil {
            EmptyView()                                                // not signed in — no action
        } else if amMember {
            // Already a member — show a badge instead of a button
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(Theme.success)
                Text("You're a member of this club")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.success)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.success.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        } else if pendingRequest?.status == .pending {
            HStack(spacing: 8) {
                Image(systemName: "clock.fill").foregroundStyle(Theme.gold)
                Text("Request pending — the admin will review it shortly.")
                    .font(.caption.bold()).foregroundStyle(Theme.gold)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.gold.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
        } else if hasFee && !stripeConnected {
            // Paid club but admin hasn't connected Stripe yet
            VStack(spacing: 4) {
                Text("Coming Soon")
                    .font(.subheadline.bold()).foregroundStyle(Theme.textSecondary)
                Text("Payments not yet enabled for this club.")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.divider, lineWidth: 1))
        } else {
            Button { Task { await handleJoin() } } label: {
                Group {
                    if isJoining {
                        ProgressView().tint(.white)
                    } else if hasFee, let fee = club.joinFee {
                        Label(String(format: "Pay $%.0f & Join", fee),
                              systemImage: "creditcard.fill")
                            .font(.headline).foregroundStyle(.white)
                    } else {
                        Label("Join Club", systemImage: "person.fill.badge.plus")
                            .font(.headline).foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isJoining)

            if let joinErrorMsg {
                Text(joinErrorMsg).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func handleJoin() async {
        guard let clubId = club.id, let uid = auth.currentUser?.uid else { return }
        let name  = auth.appUser?.displayName ?? auth.currentUser?.displayName ?? "Player"
        let email = auth.currentUser?.email ?? ""

        if hasFee {
            showPaymentView = true
            return
        }
        // Free club — join immediately
        isJoining = true; joinErrorMsg = nil
        do {
            try await service.joinClub(userId: uid, userFullName: name,
                                       clubId: clubId, userEmail: email)
            amMember = true
        } catch {
            joinErrorMsg = error.localizedDescription
        }
        isJoining = false
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(LinearGradient(colors: [Theme.accent, Theme.gold],
                                         startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 96, height: 96)
                Image(systemName: "figure.disc.sports")
                    .font(.system(size: 40))
                    .foregroundStyle(.white)
            }
            .shadow(color: Theme.accent.opacity(0.4), radius: 14)

            Text(club.name)
                .font(.system(size: 28, weight: .black, design: .rounded))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)

            HStack(spacing: 6) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.caption).foregroundStyle(Theme.textSecondary)
                Text(club.location)
                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: Stats

    private var statRow: some View {
        HStack(spacing: 0) {
            statCell(value: "\(club.memberCount)",
                     label: club.memberCount == 1 ? "Member" : "Members")
            Divider().frame(height: 36).background(Theme.divider)
            statCell(value: club.joinFee.map { $0 == 0 ? "Free" : String(format: "$%.0f", $0) } ?? "Free",
                     label: "Join Fee")
            Divider().frame(height: 36).background(Theme.divider)
            statCell(value: "\(events.filter { $0.isUpcoming }.count)",
                     label: "Upcoming")
        }
        .padding(.vertical, 12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 18, weight: .black, design: .rounded))
                .foregroundStyle(Theme.gold)
            Text(label).font(.caption2).foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: Admin block

    @ViewBuilder
    private var adminBlock: some View {
        if let admin {
            section("Run by") {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(LinearGradient(colors: [Theme.accent, Theme.gold],
                                                 startPoint: .topLeading, endPoint: .bottomTrailing))
                            .frame(width: 44, height: 44)
                        if let urlStr = admin.photoURL, !urlStr.isEmpty, let url = URL(string: urlStr) {
                            AsyncImage(url: url) { phase in
                                if case .success(let img) = phase {
                                    img.resizable().scaledToFill()
                                } else { adminInitial }
                            }
                            .frame(width: 42, height: 42)
                            .clipShape(Circle())
                        } else {
                            adminInitial
                        }
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(admin.displayName)
                            .font(.subheadline.bold()).foregroundStyle(Theme.textPrimary)
                        Text("Club Admin")
                            .font(.caption).foregroundStyle(Theme.accent)
                    }
                    Spacer()
                }
            }
        }
    }

    @ViewBuilder
    private var adminInitial: some View {
        Text(String(admin?.displayName.first ?? "?").uppercased())
            .font(.headline).foregroundStyle(.white)
    }

    // MARK: Contact

    @ViewBuilder
    private var contactBlock: some View {
        let hasAnyContact = !(club.contactEmail ?? "").isEmpty
                         || !(club.contactPhone ?? "").isEmpty
                         || !(club.website     ?? "").isEmpty
        if hasAnyContact {
            section("Contact") {
                VStack(alignment: .leading, spacing: 10) {
                    if let email = club.contactEmail, !email.isEmpty {
                        contactRow(icon: "envelope.fill", text: email,
                                   url: URL(string: "mailto:\(email)"))
                    }
                    if let phone = club.contactPhone, !phone.isEmpty {
                        let cleaned = phone.filter { "+0123456789".contains($0) }
                        contactRow(icon: "phone.fill", text: phone,
                                   url: URL(string: "tel:\(cleaned)"))
                    }
                    if let site = club.website, !site.isEmpty {
                        let withScheme = site.lowercased().hasPrefix("http") ? site : "https://\(site)"
                        contactRow(icon: "globe", text: site,
                                   url: URL(string: withScheme))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func contactRow(icon: String, text: String, url: URL?) -> some View {
        Button {
            if let url { UIApplication.shared.open(url) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(Theme.accent).frame(width: 24)
                Text(text).font(.subheadline).foregroundStyle(Theme.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.right").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: Events

    @ViewBuilder
    private var eventsBlock: some View {
        section("Upcoming Events") {
            let upcoming = events.filter { $0.isUpcoming }
            if upcoming.isEmpty {
                Text("No upcoming events.").font(.caption).foregroundStyle(Theme.textSecondary)
            } else {
                VStack(spacing: 8) {
                    ForEach(upcoming) { e in
                        Button { openEvent = e } label: {
                            EventListRow(event: e, showStatus: false)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                                .background(Theme.cardAlt, in: RoundedRectangle(cornerRadius: 10))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Generic section wrapper

    @ViewBuilder
    private func section<Content: View>(_ title: String,
                                        @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundStyle(Theme.textSecondary)
            VStack(alignment: .leading, spacing: 8) {
                content()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Loading

    private func load() async {
        isLoading = true
        defer { isLoading = false }

        if let clubId = club.id {
            async let evtFetch = service.fetchEvents(clubId: clubId)
            events = (try? await evtFetch) ?? []
        }

        // Admin user
        if !club.adminUID.isEmpty {
            admin = try? await service.fetchUser(uid: club.adminUID)
        }

        // Is the current viewer a member / has a pending request?
        if let me = auth.currentUser?.uid, let clubId = club.id {
            async let mFetch = service.fetchMembership(userId: me, clubId: clubId)
            async let rFetch = service.checkJoinRequest(userId: me, clubId: clubId)
            let m = try? await mFetch
            amMember = m != nil
            pendingRequest = try? await rFetch
        }
    }
}
