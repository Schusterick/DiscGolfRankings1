import SwiftUI

// MARK: - ChallengesTabView

struct ChallengesTabView: View {
    @EnvironmentObject var auth: AuthService
    private let service = FirebaseService.shared

    @State private var myMemberships: [Membership] = []
    @State private var selectedMembership: Membership?
    @State private var challenges: [Challenge] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if myMemberships.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Club Memberships",
                        systemImage: "figure.disc.sports",
                        description: Text("Join a club to start tracking challenges.")
                    )
                } else {
                    VStack(spacing: 0) {
                        if myMemberships.count > 1 {
                            Picker("Club", selection: $selectedMembership) {
                                ForEach(myMemberships, id: \.id) { m in
                                    Text(m.clubId).tag(Optional(m))
                                }
                            }
                            .pickerStyle(.segmented)
                            .padding()
                        }

                        List {
                            Section("Active") {
                                let active = challenges.filter { $0.isActive }
                                if active.isEmpty {
                                    Text("No active challenges").foregroundStyle(.secondary)
                                } else {
                                    ForEach(active) { c in
                                        ChallengeRowView(challenge: c)
                                    }
                                }
                            }
                            Section("History") {
                                let history = challenges.filter { !$0.isActive }
                                if history.isEmpty {
                                    Text("No completed challenges").foregroundStyle(.secondary)
                                } else {
                                    ForEach(history) { c in
                                        ChallengeRowView(challenge: c)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Challenges")
            .overlay { if isLoading { ProgressView() } }
            .task { await loadData() }
            .refreshable { await loadData() }
            .onChange(of: selectedMembership) { _, _ in
                Task { await loadChallenges() }
            }
        }
    }

    private func loadData() async {
        isLoading = true
        defer { isLoading = false }
        guard let uid = auth.currentUser?.uid else { return }
        do {
            if let m = try await service.fetchMembership(userId: uid, clubId: service.daltonClubID) {
                myMemberships = [m]
                if selectedMembership == nil { selectedMembership = m }
            }
            await loadChallenges()
        } catch {
            // silently fail — empty state handles it
        }
    }

    private func loadChallenges() async {
        guard let m = selectedMembership else { return }
        challenges = (try? await service.fetchChallenges(clubID: m.clubId, userId: m.userId)) ?? []
    }
}

// MARK: - ChallengeRowView

struct ChallengeRowView: View {
    let challenge: Challenge
    @EnvironmentObject var auth: AuthService
    private let service = FirebaseService.shared
    @State private var showResolve = false

    private var isChallenger: Bool { challenge.challengerUID == auth.currentUser?.uid }
    private var isDefendant: Bool { challenge.defendantUID == auth.currentUser?.uid }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading) {
                    Text("\(challenge.challengerName) (#\(challenge.challengerTag))")
                        .fontWeight(isChallenger ? .bold : .regular)
                    Text("vs")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("\(challenge.defendantName) (#\(challenge.defendantTag))")
                        .fontWeight(isDefendant ? .bold : .regular)
                }
                Spacer()
                statusBadge
            }

            if let course = challenge.courseName, !course.isEmpty {
                Label(course, systemImage: "mappin").font(.caption).foregroundStyle(.secondary)
            }

            actionButtons
        }
        .padding(.vertical, 4)
        .sheet(isPresented: $showResolve) {
            ResolveChallengeView(challenge: challenge)
        }
    }

    @ViewBuilder
    private var statusBadge: some View {
        let (label, color) = statusInfo
        Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var statusInfo: (String, Color) {
        switch challenge.status {
        case .pending: return ("Pending", .orange)
        case .accepted: return ("Accepted", .blue)
        case .completed:
            let won = challenge.winnerUID == auth.currentUser?.uid
            return (won ? "Won" : "Lost", won ? .green : .red)
        case .declined: return ("Declined", .red)
        case .cancelled: return ("Cancelled", .gray)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        if challenge.status == .pending && isDefendant {
            HStack {
                Button("Accept") {
                    Task { try? await service.respondToChallenge(challenge.id ?? "", accept: true) }
                }
                .buttonStyle(.bordered).tint(.green)

                Button("Decline") {
                    Task { try? await service.respondToChallenge(challenge.id ?? "", accept: false) }
                }
                .buttonStyle(.bordered).tint(.red)
            }
        } else if challenge.status == .accepted && (isChallenger || isDefendant) {
            Button("Enter Result") { showResolve = true }
                .buttonStyle(.borderedProminent).tint(.blue)
        } else if challenge.status == .pending && isChallenger {
            Button("Cancel") {
                Task { try? await service.cancelChallenge(challenge.id ?? "") }
            }
            .buttonStyle(.bordered).tint(.gray)
        }
    }
}

// MARK: - CreateChallengeView

struct CreateChallengeView: View {
    let club: Club
    let myMembership: Membership
    let leaderboard: [Membership]

    @Environment(\.dismiss) var dismiss
    private let service = FirebaseService.shared

    @State private var selectedDefendant: Membership?
    @State private var courseName = ""
    @State private var notes = ""
    @State private var isSubmitting = false
    @State private var error: String?

    private var eligibleOpponents: [Membership] {
        leaderboard.filter { $0.userId != myMembership.userId && $0.tagNumber < myMembership.tagNumber }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Challenge Who?") {
                    if eligibleOpponents.isEmpty {
                        Text("You hold the #1 tag — no one to challenge!")
                            .foregroundStyle(.secondary)
                    } else {
                        Picker("Opponent", selection: $selectedDefendant) {
                            Text("Select player").tag(Optional<Membership>.none)
                            ForEach(eligibleOpponents, id: \.id) { m in
                                Text("#\(m.tagNumber) \(m.userFullName)").tag(Optional(m))
                            }
                        }
                    }
                }

                Section("Details (optional)") {
                    TextField("Course Name", text: $courseName)
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...5)
                }

                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
            }
            .navigationTitle("New Challenge")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") { sendChallenge() }
                        .disabled(selectedDefendant == nil || isSubmitting)
                }
            }
        }
    }

    private func sendChallenge() {
        guard let opponent = selectedDefendant, let clubID = club.id else { return }
        isSubmitting = true
        Task {
            do {
                try await service.createChallenge(
                    clubID: clubID,
                    challengerMembership: myMembership,
                    defendantMembership: opponent,
                    courseName: courseName.isEmpty ? nil : courseName,
                    notes: notes.isEmpty ? nil : notes
                )
                dismiss()
            } catch {
                self.error = error.localizedDescription
                isSubmitting = false
            }
        }
    }
}

// MARK: - ResolveChallengeView

struct ResolveChallengeView: View {
    let challenge: Challenge
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) var dismiss
    private let service = FirebaseService.shared
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 32) {
                Text("Who won?")
                    .font(.title2.bold())
                    .padding(.top, 24)

                VStack(spacing: 12) {
                    Button {
                        resolve(challengerWon: true)
                    } label: {
                        HStack {
                            Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                            Text("\(challenge.challengerName) (#\(challenge.challengerTag))")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.green.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Text("vs")
                        .foregroundStyle(.secondary)

                    Button {
                        resolve(challengerWon: false)
                    } label: {
                        HStack {
                            Image(systemName: "trophy.fill").foregroundStyle(.yellow)
                            Text("\(challenge.defendantName) (#\(challenge.defendantTag))")
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal)

                Text("If the challenger wins, tags will be swapped automatically.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer()
            }
            .navigationTitle("Enter Result")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay { if isSubmitting { ProgressView() } }
        }
    }

    private func resolve(challengerWon: Bool) {
        isSubmitting = true
        Task {
            try? await service.resolveChallenge(challenge, challengerWon: challengerWon)
            dismiss()
        }
    }
}
