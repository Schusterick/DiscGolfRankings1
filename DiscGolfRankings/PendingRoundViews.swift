import SwiftUI

// MARK: - PendingRoundsView

struct PendingRoundsView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var rounds:            [PendingRound] = []
    @State private var isLoading                         = false
    @State private var respondingRoundId: String?
    @State private var showDisputeConfirm                = false
    @State private var roundToDispute:    PendingRound?

    private var myUID: String { auth.currentUser?.uid ?? "" }

    private var needsMyAction: [PendingRound] {
        rounds.filter { $0.needsResponse(from: myUID) && $0.submittedBy != myUID }
    }
    private var mySubmissions: [PendingRound] {
        rounds.filter { $0.submittedBy == myUID }
    }
    private var alreadyResponded: [PendingRound] {
        rounds.filter { !$0.needsResponse(from: myUID) && $0.submittedBy != myUID }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Group {
                    if isLoading && rounds.isEmpty {
                        ProgressView().tint(Theme.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if rounds.isEmpty {
                        ContentUnavailableView(
                            "All Caught Up!",
                            systemImage: "checkmark.seal.fill",
                            description: Text("No rounds are waiting for confirmation.")
                        )
                        .foregroundStyle(Theme.textSecondary)
                    } else {
                        List {
                            if !needsMyAction.isEmpty {
                                Section("Waiting for You (\(needsMyAction.count))") {
                                    ForEach(needsMyAction) { round in
                                        PendingRoundRowView(
                                            round: round,
                                            myUID: myUID,
                                            isResponding: respondingRoundId == round.id,
                                            onConfirm: { await respond(to: round, confirmed: true) },
                                            onDispute: {
                                                roundToDispute = round
                                                showDisputeConfirm = true
                                            }
                                        )
                                        .listRowBackground(Theme.card)
                                        .listRowSeparatorTint(Theme.divider)
                                    }
                                }
                            }

                            if !mySubmissions.isEmpty {
                                Section("Submitted by You") {
                                    ForEach(mySubmissions) { round in
                                        PendingRoundRowView(
                                            round: round,
                                            myUID: myUID,
                                            isResponding: false,
                                            onConfirm: { },
                                            onDispute: { }
                                        )
                                        .listRowBackground(Theme.card)
                                        .listRowSeparatorTint(Theme.divider)
                                    }
                                }
                            }

                            if !alreadyResponded.isEmpty {
                                Section("Already Responded") {
                                    ForEach(alreadyResponded) { round in
                                        PendingRoundRowView(
                                            round: round,
                                            myUID: myUID,
                                            isResponding: false,
                                            onConfirm: { },
                                            onDispute: { }
                                        )
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
            .navigationTitle("Confirm Scores")
            .navigationBarTitleDisplayMode(.large)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
            .task { await load() }
            .refreshable { await load() }
            .confirmationDialog(
                "Dispute These Scores?",
                isPresented: $showDisputeConfirm,
                titleVisibility: .visible
            ) {
                Button("Dispute", role: .destructive) {
                    guard let r = roundToDispute else { return }
                    Task { await respond(to: r, confirmed: false) }
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("Disputing will cancel the round. No tags will be swapped and the group will need to re-enter scores.")
            }
        }
        .preferredColorScheme(.dark)
    }

    private func load() async {
        isLoading = true
        rounds    = (try? await service.fetchPendingRoundsForUser(userId: myUID)) ?? []
        isLoading = false
    }

    private func respond(to round: PendingRound, confirmed: Bool) async {
        guard let roundId = round.id else { return }
        respondingRoundId = roundId
        try? await service.respondToPendingRound(roundId: roundId, userId: myUID, confirmed: confirmed)
        await load()
        respondingRoundId = nil
        if confirmed {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
    }
}

// MARK: - PendingRoundRowView

struct PendingRoundRowView: View {
    let round: PendingRound
    let myUID: String
    let isResponding: Bool
    let onConfirm: () async -> Void
    let onDispute: () -> Void

    private var iAlreadyConfirmed: Bool { round.confirmationsMap[myUID] == true  }
    private var iDisputed:         Bool { round.confirmationsMap[myUID] == false }
    private var isMySubmission:    Bool { round.submittedBy == myUID }
    private var waitingOnCount:    Int  { round.awaitingCount() }

    private var sortedPlayerIds: [String] {
        round.playerIds.sorted {
            (round.scores[$0] ?? 999) < (round.scores[$1] ?? 999)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerRow
            Divider().background(Theme.divider)
            scoresTable
            Divider().background(Theme.divider)
            confirmationStatus
            actionArea
        }
        .padding(.vertical, 6)
    }

    // MARK: Header

    private var headerRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(isMySubmission ? "You submitted these scores" : "Submitted by \(round.submittedByName)")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text(round.submittedAt.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            if waitingOnCount > 0 {
                Text("\(waitingOnCount) pending")
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Theme.gold.opacity(0.15), in: Capsule())
                    .foregroundStyle(Theme.gold)
            }
        }
    }

    // MARK: Scores Table

    private var scoresTable: some View {
        VStack(spacing: 6) {
            HStack {
                Text("Player")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textSecondary)
                Spacer()
                Text("Score")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 46, alignment: .center)
                Text("Tag")
                    .font(.caption.bold())
                    .foregroundStyle(Theme.textSecondary)
                    .frame(width: 84, alignment: .trailing)
            }
            ForEach(sortedPlayerIds, id: \.self) { pid in
                scoreRow(for: pid)
            }
        }
    }

    @ViewBuilder
    private func scoreRow(for pid: String) -> some View {
        let name     = round.playerNames[pid] ?? "Player"
        let score    = round.scores[pid]     ?? 0
        let oldTag   = round.tagsBefore[pid] ?? 0
        let newTag   = round.tagsAfter[pid]  ?? 0
        let improved = newTag < oldTag
        let same     = newTag == oldTag
        let isMe     = pid == myUID

        HStack {
            HStack(spacing: 4) {
                Text(name)
                    .font(.subheadline)
                    .fontWeight(isMe ? .bold : .regular)
                    .foregroundStyle(Theme.textPrimary)
                if isMe {
                    Text("(You)")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
            Text("\(score)")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 46, alignment: .center)
            HStack(spacing: 3) {
                Text("#\(oldTag)")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Image(systemName: same ? "equal" : (improved ? "arrow.down" : "arrow.up"))
                    .font(.caption.bold())
                    .foregroundStyle(same ? Theme.textSecondary : (improved ? Theme.success : Theme.accent))
                Text("#\(newTag)")
                    .font(.subheadline.bold().monospacedDigit())
                    .foregroundStyle(same ? Theme.textPrimary : (improved ? Theme.success : Theme.accent))
            }
            .frame(width: 84, alignment: .trailing)
        }
    }

    // MARK: Confirmation Status

    private var confirmationStatus: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(round.playerIds, id: \.self) { pid in
                confirmationRow(for: pid)
            }
        }
    }

    @ViewBuilder
    private func confirmationRow(for pid: String) -> some View {
        let name = round.playerNames[pid] ?? "Player"
        HStack(spacing: 6) {
            if let val = round.confirmationsMap[pid] {
                Image(systemName: val ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(val ? Theme.success : Theme.accent)
                    .font(.caption)
                Text(name)
                    .font(.caption)
                    .foregroundStyle(val ? Theme.textPrimary : Theme.accent)
                Text(val ? "confirmed" : "disputed")
                    .font(.caption)
                    .foregroundStyle(val ? Theme.textSecondary : Theme.accent)
            } else {
                Image(systemName: "clock")
                    .foregroundStyle(Theme.gold)
                    .font(.caption)
                Text(name).font(.caption).foregroundStyle(Theme.textPrimary)
                Text("waiting…").font(.caption).foregroundStyle(Theme.textSecondary)
            }
        }
    }

    // MARK: Action Area

    @ViewBuilder
    private var actionArea: some View {
        if iAlreadyConfirmed || isMySubmission {
            Label(
                isMySubmission ? "You submitted — waiting for others" : "You confirmed these scores",
                systemImage: "checkmark.circle.fill"
            )
            .font(.footnote.bold())
            .foregroundStyle(Theme.success)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 4)
        } else if iDisputed {
            Label("You disputed this round", systemImage: "xmark.circle.fill")
                .font(.footnote.bold())
                .foregroundStyle(Theme.accent)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.vertical, 4)
        } else {
            HStack(spacing: 10) {
                Button(role: .destructive) {
                    onDispute()
                } label: {
                    Label("Dispute", systemImage: "xmark.circle")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.8))
                .disabled(isResponding)

                Button {
                    Task { await onConfirm() }
                } label: {
                    Group {
                        if isResponding {
                            ProgressView().tint(.white)
                        } else {
                            Label("Confirm", systemImage: "checkmark.circle")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.success)
                .disabled(isResponding)
            }
        }
    }
}
