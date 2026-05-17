import SwiftUI

// MARK: - GroupRoundView

struct GroupRoundView: View {
    let club: Club

    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    enum Step { case selectPlayers, enterScores, reviewResults, success }

    @State private var step: Step = .selectPlayers

    // Step 1
    @State private var allMembers:       [Membership] = []
    @State private var selectedIDs:      Set<String>  = []
    @State private var isLoadingMembers              = false

    // Step 2
    @State private var scores: [String: String] = [:]

    // Step 3 / 4
    @State private var tagResults:  [TagResult] = []
    @State private var isSaving                 = false
    @State private var saveError:   String?

    private var currentUID: String { auth.currentUser?.uid ?? "" }

    private var selectedMembers: [Membership] {
        allMembers
            .filter { selectedIDs.contains($0.userId) }
            .sorted { $0.tagNumber < $1.tagNumber }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Group {
                    switch step {
                    case .selectPlayers: selectPlayersView
                    case .enterScores:   enterScoresView
                    case .reviewResults: reviewResultsView
                    case .success:       successView
                    }
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                if step != .success {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                            .foregroundStyle(Theme.accent)
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .task { await loadMembers() }
    }

    private var stepTitle: String {
        switch step {
        case .selectPlayers: return "Select Players"
        case .enterScores:   return "Enter Scores"
        case .reviewResults: return "Review Results"
        case .success:       return "Round Complete"
        }
    }

    // MARK: – Step 1: Select Players

    @ViewBuilder
    private var selectPlayersView: some View {
        VStack(spacing: 0) {
            if isLoadingMembers {
                ProgressView().tint(Theme.accent)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        Text("Select 2–8 players for this round. You are pre-selected and cannot be removed.")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .listRowBackground(Color.clear)

                    Section("\(club.name) — \(allMembers.count) Member\(allMembers.count == 1 ? "" : "s")") {
                        ForEach(allMembers) { member in
                            let isSelected = selectedIDs.contains(member.userId)
                            let isMe       = member.userId == currentUID
                            Button {
                                guard !isMe else { return }
                                if isSelected {
                                    selectedIDs.remove(member.userId)
                                } else if selectedIDs.count < 8 {
                                    selectedIDs.insert(member.userId)
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(isSelected ? Theme.accent : Theme.textSecondary)
                                        .font(.title3)

                                    Text("#\(member.tagNumber)")
                                        .font(.caption.monospacedDigit().bold())
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(Theme.gold.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
                                        .foregroundStyle(Theme.gold)

                                    Text(member.userFullName)
                                        .fontWeight(isMe ? .bold : .regular)
                                        .foregroundStyle(Theme.textPrimary)

                                    if isMe {
                                        Text("(You)")
                                            .font(.caption)
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isMe)
                            .listRowBackground(isSelected ? Theme.accent.opacity(0.08) : Theme.card)
                        }
                    }
                }
                .darkListStyle()

                Button {
                    step = .enterScores
                } label: {
                    Text("Continue with \(selectedIDs.count) Players")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                }
                .disabled(selectedIDs.count < 2)
                .padding()
            }
        }
    }

    // MARK: – Step 2: Enter Scores

    @ViewBuilder
    private var enterScoresView: some View {
        VStack(spacing: 0) {
            List {
                Section(header: Text("Strokes per player — lower score is better")
                            .foregroundStyle(Theme.textSecondary)) {
                    ForEach(selectedMembers) { member in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.userFullName)
                                    .fontWeight(member.userId == currentUID ? .bold : .regular)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("Current tag #\(member.tagNumber)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Spacer()
                            TextField("Score", text: Binding(
                                get: { scores[member.userId] ?? "" },
                                set: { scores[member.userId] = $0 }
                            ))
                            .foregroundStyle(Theme.textPrimary)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .padding(8)
                            .background(Theme.cardAlt, in: RoundedRectangle(cornerRadius: 8))
                        }
                        .listRowBackground(Theme.card)
                    }
                }
            }
            .darkListStyle()

            Button {
                computeTagResults()
                step = .reviewResults
            } label: {
                Text("Calculate Results")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!allScoresFilled)
            .padding()
        }
    }

    private var allScoresFilled: Bool {
        selectedMembers.allSatisfy {
            guard let s = scores[$0.userId], !s.isEmpty, Int(s) != nil else { return false }
            return true
        }
    }

    // MARK: – Step 3: Review & Confirm

    @ViewBuilder
    private var reviewResultsView: some View {
        VStack(spacing: 0) {
            List {
                Section(header: Text("Finish order & new tag assignments")
                            .foregroundStyle(Theme.textSecondary)) {
                    ForEach(Array(tagResults.enumerated()), id: \.element.id) { idx, result in
                        let improved = result.newTag < result.oldTag
                        let same     = result.newTag == result.oldTag

                        HStack(spacing: 12) {
                            Text("\(idx + 1).")
                                .font(.headline)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 28, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.membership.userFullName)
                                    .fontWeight(result.membership.userId == currentUID ? .bold : .regular)
                                    .foregroundStyle(Theme.textPrimary)
                                Text("\(result.score) strokes")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }

                            Spacer()

                            HStack(spacing: 4) {
                                Text("#\(result.oldTag)")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                                Image(systemName: same ? "equal" : (improved ? "arrow.down" : "arrow.up"))
                                    .font(.caption.bold())
                                    .foregroundStyle(same ? Theme.textSecondary : (improved ? Theme.success : Theme.accent))
                                Text("#\(result.newTag)")
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(same ? Theme.textPrimary : (improved ? Theme.success : Theme.accent))
                            }
                        }
                        .padding(.vertical, 2)
                        .listRowBackground(Theme.card)
                    }
                }

                if let err = saveError {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                    .listRowBackground(Theme.card)
                }
            }
            .darkListStyle()

            Button {
                Task { await saveRound() }
            } label: {
                Group {
                    if isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text("Confirm & Save Results")
                            .font(.headline)
                            .foregroundStyle(.white)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .disabled(isSaving)
            .padding()
        }
    }

    // MARK: – Step 4: Awaiting Confirmation

    @ViewBuilder
    private var successView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 32)

                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 72))
                    .foregroundStyle(Theme.success)
                    .shadow(color: Theme.success.opacity(0.4), radius: 16)

                Text("Scores Submitted!")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)

                Text("Waiting for the other players to confirm the scores before tags are updated.")
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(tagResults) { result in
                        let improved = result.newTag < result.oldTag
                        let same     = result.newTag == result.oldTag
                        HStack {
                            Text(result.membership.userFullName)
                                .foregroundStyle(Theme.textPrimary)
                                .fontWeight(result.membership.userId == currentUID ? .bold : .regular)
                            Spacer()
                            Text("#\(result.oldTag) → #\(result.newTag)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(same ? Theme.textPrimary : (improved ? Theme.success : Theme.accent))
                        }
                    }
                }
                .padding()
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)

                Label("You've automatically confirmed your own scores.", systemImage: "checkmark.circle.fill")
                    .font(.footnote)
                    .foregroundStyle(Theme.success)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Text("Other players will see a confirmation request on their Home screen.")
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)

                Button("Done") { dismiss() }
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 48)
                    .padding(.vertical, 14)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                    .padding(.top, 8)
            }
            .padding(.bottom, 32)
        }
    }

    // MARK: – Helpers

    private func loadMembers() async {
        isLoadingMembers = true
        allMembers = (try? await service.fetchLeaderboard(clubID: club.id ?? "")) ?? []
        if let mine = allMembers.first(where: { $0.userId == currentUID }) {
            selectedIDs.insert(mine.userId)
        }
        isLoadingMembers = false
    }

    private func computeTagResults() {
        let sortedByScore = selectedMembers.sorted {
            (Int(scores[$0.userId] ?? "") ?? Int.max) < (Int(scores[$1.userId] ?? "") ?? Int.max)
        }
        let sortedTags = sortedByScore.map { $0.tagNumber }.sorted()

        tagResults = zip(sortedByScore, sortedTags).map { member, newTag in
            TagResult(
                membership: member,
                oldTag: member.tagNumber,
                newTag: newTag,
                score: Int(scores[member.userId] ?? "0") ?? 0
            )
        }
    }

    private func saveRound() async {
        isSaving  = true
        saveError = nil
        let intScores = scores.compactMapValues { Int($0) }
        let myName = auth.appUser?.displayName ?? auth.currentUser?.displayName ?? "Player"
        do {
            try await service.submitPendingRound(
                clubId:          club.id ?? "",
                results:         tagResults,
                scores:          intScores,
                submittedBy:     currentUID,
                submittedByName: myName
            )
            step = .success
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
