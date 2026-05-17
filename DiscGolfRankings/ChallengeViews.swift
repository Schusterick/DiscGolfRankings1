import SwiftUI

// MARK: - SendChallengeView
// Presented from the Leaderboard when a player taps "Challenge" next to another member.
// Captures a short message + optional location/date, then creates the Challenge doc
// and a notification on the defendant.

struct SendChallengeView: View {
    let club:      Club
    let challenger: Membership      // current user's membership
    let defendant:  Membership      // target player's membership

    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var message:          String = ""
    @State private var proposedLocation: String = ""
    @State private var proposedDate:     Date   = Date().addingTimeInterval(60 * 60 * 24 * 3) // +3 days
    @State private var includeDate:      Bool   = false
    @State private var isSending         = false
    @State private var errorMsg:         String?
    @State private var showSuccess       = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Form {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("#\(defendant.tagNumber)")
                                    .font(.title2.bold().monospacedDigit())
                                    .foregroundStyle(Theme.gold)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(defendant.userFullName)
                                        .font(.headline).foregroundStyle(Theme.textPrimary)
                                    Text(club.name)
                                        .font(.caption).foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Theme.card)

                    Section("Message (optional)") {
                        TextField("Bring your A-game…", text: $message, axis: .vertical)
                            .lineLimit(2...5)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .listRowBackground(Theme.card)

                    Section("Where (optional)") {
                        TextField("Course or location", text: $proposedLocation)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .listRowBackground(Theme.card)

                    Section {
                        Toggle("Suggest a date", isOn: $includeDate)
                            .foregroundStyle(Theme.textPrimary)
                            .tint(Theme.accent)
                        if includeDate {
                            DatePicker("Date", selection: $proposedDate,
                                       in: Date()..., displayedComponents: [.date, .hourAndMinute])
                                .foregroundStyle(Theme.textPrimary)
                        }
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
                                else { Text("Send Challenge").fontWeight(.semibold).foregroundStyle(.white) }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .disabled(isSending)
                    }
                    .listRowBackground(Theme.accent.opacity(0.85))
                }
                .darkListStyle()
            }
            .navigationTitle("Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
            .alert("Challenge Sent!", isPresented: $showSuccess) {
                Button("OK") { dismiss() }
            } message: {
                Text("\(defendant.userFullName) will see this in their notifications.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func send() async {
        guard let clubId = club.id else { return }
        isSending = true; errorMsg = nil

        // Look up the defendant's email so the accept flow can mailto them
        let defendantUser = try? await service.fetchUser(uid: defendant.userId)

        let challenge = Challenge(
            id: nil,
            clubID:           clubId,
            clubName:         club.name,
            challengerUID:    challenger.userId,
            challengerName:   challenger.userFullName,
            challengerTag:    challenger.tagNumber,
            challengerEmail:  auth.currentUser?.email,
            defendantUID:     defendant.userId,
            defendantName:    defendant.userFullName,
            defendantTag:     defendant.tagNumber,
            defendantEmail:   defendantUser?.email ?? defendant.email,
            status:           .pending,
            createdAt:        Date(),
            resolvedAt:       nil,
            winnerUID:        nil,
            courseName:       nil,
            notes:            nil,
            message:          message.trimmingCharacters(in: .whitespaces),
            proposedLocation: proposedLocation.trimmingCharacters(in: .whitespaces),
            proposedDate:     includeDate ? proposedDate : nil
        )

        do {
            _ = try await service.sendChallenge(challenge)
            showSuccess = true
        } catch {
            errorMsg = error.localizedDescription
        }
        isSending = false
    }
}

// MARK: - MyChallengesView
// Opened from Profile → "Challenges". Shows incoming + outgoing with Accept/Decline actions.

struct MyChallengesView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var challenges: [Challenge] = []
    @State private var isLoading  = false
    @State private var processing: String?
    @State private var errorMsg:   String?

    private var myUID: String { auth.currentUser?.uid ?? "" }
    private var incoming: [Challenge] {
        challenges.filter { $0.defendantUID == myUID && $0.status == .pending }
    }
    private var outgoing: [Challenge] {
        challenges.filter { $0.challengerUID == myUID && $0.status == .pending }
    }
    private var history: [Challenge] {
        challenges.filter { $0.status != .pending }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                if isLoading && challenges.isEmpty {
                    ProgressView().tint(Theme.accent)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if challenges.isEmpty {
                    ContentUnavailableView(
                        "No Challenges",
                        systemImage: "flag.checkered",
                        description: Text("Challenge a player from the Leaderboard tab.")
                    )
                    .foregroundStyle(Theme.textSecondary)
                } else {
                    List {
                        if !incoming.isEmpty {
                            Section("Incoming (\(incoming.count))") {
                                ForEach(incoming) { c in
                                    ChallengeRow(
                                        challenge: c,
                                        isIncoming: true,
                                        isProcessing: processing == c.id,
                                        onAccept:  { await respond(c, accept: true) },
                                        onDecline: { await respond(c, accept: false) }
                                    )
                                    .listRowBackground(Theme.card)
                                }
                            }
                        }
                        if !outgoing.isEmpty {
                            Section("Sent (\(outgoing.count))") {
                                ForEach(outgoing) { c in
                                    ChallengeRow(
                                        challenge: c,
                                        isIncoming: false,
                                        isProcessing: false,
                                        onAccept: { }, onDecline: { }
                                    )
                                    .listRowBackground(Theme.card)
                                }
                            }
                        }
                        if !history.isEmpty {
                            Section("History") {
                                ForEach(history) { c in
                                    ChallengeRow(
                                        challenge: c,
                                        isIncoming: c.defendantUID == myUID,
                                        isProcessing: false,
                                        onAccept: { }, onDecline: { }
                                    )
                                    .listRowBackground(Theme.card)
                                }
                            }
                        }

                        if let errorMsg {
                            Section { Text(errorMsg).foregroundStyle(.red).font(.caption) }
                                .listRowBackground(Theme.card)
                        }
                    }
                    .darkListStyle()
                }
            }
            .navigationTitle("Challenges")
            .navigationBarTitleDisplayMode(.large)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
            .task { await load() }
            .refreshable { await load() }
        }
        .preferredColorScheme(.dark)
    }

    private func load() async {
        guard let uid = auth.currentUser?.uid else { return }
        isLoading = true; errorMsg = nil
        do { challenges = try await service.fetchUserChallenges(userId: uid) }
        catch { errorMsg = error.localizedDescription }
        isLoading = false
    }

    private func respond(_ challenge: Challenge, accept: Bool) async {
        guard let cid = challenge.id else { return }
        processing = cid
        do {
            try await service.updateChallengeStatus(
                challengeId: cid,
                status: accept ? .accepted : .declined
            )
            // If accepted, launch the user's mail app to coordinate
            if accept, let email = challenge.challengerEmail, !email.isEmpty {
                openMail(to: email, challenge: challenge)
            }
            await load()
        } catch { errorMsg = error.localizedDescription }
        processing = nil
    }

    /// Opens the user's default mail client with a pre-filled subject and body.
    private func openMail(to email: String, challenge: Challenge) {
        let subject = "Disc Golf Tag Challenge — \(challenge.clubName ?? "Club")"
        var body = "Hey \(challenge.challengerName),\n\nI accept your challenge!\n\n"
        if let loc = challenge.proposedLocation, !loc.isEmpty {
            body += "Where: \(loc)\n"
        }
        if let date = challenge.proposedDate {
            body += "When: \(date.formatted(date: .abbreviated, time: .shortened))\n"
        }
        body += "\nLet's lock in the details.\n"

        let encSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        let encBody    = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        if let url = URL(string: "mailto:\(email)?subject=\(encSubject)&body=\(encBody)") {
            UIApplication.shared.open(url)
        }
    }
}

// MARK: - ChallengeRow

struct ChallengeRow: View {
    let challenge:    Challenge
    let isIncoming:   Bool
    let isProcessing: Bool
    let onAccept:     () async -> Void
    let onDecline:    () async -> Void

    private var statusColor: Color {
        switch challenge.status {
        case .pending:   return Theme.gold
        case .accepted:  return Theme.success
        case .completed: return Theme.success
        case .declined:  return .red
        case .cancelled: return Theme.textSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Image(systemName: isIncoming ? "arrow.down.left" : "arrow.up.right")
                            .font(.caption)
                            .foregroundStyle(isIncoming ? Theme.accent : Theme.gold)
                        Text(isIncoming
                             ? "From \(challenge.challengerName)"
                             : "To \(challenge.defendantName)")
                            .font(.subheadline.bold())
                            .foregroundStyle(Theme.textPrimary)
                    }
                    if let club = challenge.clubName {
                        Text(club).font(.caption).foregroundStyle(Theme.textSecondary)
                    }
                    Text(challenge.createdAt.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption2).foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Text(challenge.status.rawValue.capitalized)
                    .font(.caption2.bold())
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(statusColor.opacity(0.15), in: Capsule())
                    .foregroundStyle(statusColor)
            }

            // Tag info
            HStack(spacing: 8) {
                Text("Tag #\(challenge.challengerTag)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: "arrow.right").font(.caption2).foregroundStyle(Theme.textSecondary)
                Text("Tag #\(challenge.defendantTag)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }

            if let m = challenge.message, !m.isEmpty {
                Text("\"\(m)\"")
                    .font(.caption).italic()
                    .foregroundStyle(Theme.textPrimary)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.background.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
            }

            if let loc = challenge.proposedLocation, !loc.isEmpty {
                Label(loc, systemImage: "mappin.and.ellipse")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
            if let date = challenge.proposedDate {
                Label(date.formatted(date: .abbreviated, time: .shortened),
                      systemImage: "calendar")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }

            // Action buttons — only for incoming pending challenges
            if isIncoming && challenge.status == .pending {
                HStack(spacing: 10) {
                    Button(role: .destructive) {
                        Task { await onDecline() }
                    } label: {
                        Text(isProcessing ? "" : "Decline")
                            .fontWeight(.semibold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .overlay { if isProcessing { ProgressView().tint(.white) } }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red.opacity(0.8))
                    .disabled(isProcessing)

                    Button {
                        Task { await onAccept() }
                    } label: {
                        Label(isProcessing ? "" : "Accept & Email",
                              systemImage: "envelope.fill")
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
        }
        .padding(.vertical, 6)
    }
}
