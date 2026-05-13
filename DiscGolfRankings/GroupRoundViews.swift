import SwiftUI

// MARK: - GroupRoundView

struct GroupRoundView: View {
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
            Group {
                switch step {
                case .selectPlayers: selectPlayersView
                case .enterScores:   enterScoresView
                case .reviewResults: reviewResultsView
                case .success:       successView
                }
            }
            .navigationTitle(stepTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if step != .success {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                }
            }
        }
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
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    Section {
                        Text("Select 2–8 players for this round. You are pre-selected and cannot be removed.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)

                    Section("Club Members (\(allMembers.count))") {
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
                                        .foregroundStyle(isSelected ? .green : .secondary)
                                        .font(.title3)

                                    Text("#\(member.tagNumber)")
                                        .font(.caption.monospacedDigit().bold())
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 4)
                                        .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                                        .foregroundStyle(.green)

                                    Text(member.userFullName)
                                        .fontWeight(isMe ? .bold : .regular)
                                        .foregroundStyle(.primary)

                                    if isMe {
                                        Text("(You)")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(isMe)
                        }
                    }
                }

                Button {
                    step = .enterScores
                } label: {
                    Text("Continue with \(selectedIDs.count) Players")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .tint(.green)
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
                Section(header: Text("Strokes per player — lower score is better")) {
                    ForEach(selectedMembers) { member in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.userFullName)
                                    .fontWeight(member.userId == currentUID ? .bold : .regular)
                                Text("Current tag #\(member.tagNumber)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            TextField("Score", text: Binding(
                                get: { scores[member.userId] ?? "" },
                                set: { scores[member.userId] = $0 }
                            ))
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .textFieldStyle(.roundedBorder)
                        }
                    }
                }
            }

            Button {
                computeTagResults()
                step = .reviewResults
            } label: {
                Text("Calculate Results")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
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
                Section(header: Text("Finish order & new tag assignments")) {
                    ForEach(Array(tagResults.enumerated()), id: \.element.id) { idx, result in
                        let improved = result.newTag < result.oldTag
                        let same     = result.newTag == result.oldTag

                        HStack(spacing: 12) {
                            Text("\(idx + 1).")
                                .font(.headline)
                                .foregroundStyle(.secondary)
                                .frame(width: 28, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(result.membership.userFullName)
                                    .fontWeight(result.membership.userId == currentUID ? .bold : .regular)
                                Text("\(result.score) strokes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            HStack(spacing: 4) {
                                Text("#\(result.oldTag)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Image(systemName: same ? "equal" : (improved ? "arrow.down" : "arrow.up"))
                                    .font(.caption.bold())
                                    .foregroundStyle(same ? Color.secondary : (improved ? .green : .red))
                                Text("#\(result.newTag)")
                                    .font(.subheadline.bold().monospacedDigit())
                                    .foregroundStyle(same ? Color.primary : (improved ? .green : .red))
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }

                if let err = saveError {
                    Section {
                        Text(err).foregroundStyle(.red).font(.caption)
                    }
                }
            }

            Button {
                Task { await saveRound() }
            } label: {
                Group {
                    if isSaving {
                        ProgressView()
                    } else {
                        Text("Confirm & Save Results")
                            .fontWeight(.semibold)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isSaving)
            .padding()
        }
    }

    // MARK: – Step 4: Success

    @ViewBuilder
    private var successView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 32)

                Text("🏆")
                    .font(.system(size: 80))

                Text("Tags Updated!")
                    .font(.largeTitle.bold())

                Text("Great round, everyone!")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(tagResults) { result in
                        let improved = result.newTag < result.oldTag
                        let same     = result.newTag == result.oldTag
                        HStack {
                            Text(result.membership.userFullName)
                                .fontWeight(result.membership.userId == currentUID ? .bold : .regular)
                            Spacer()
                            Text("#\(result.oldTag) → #\(result.newTag)")
                                .font(.subheadline.monospacedDigit())
                                .foregroundStyle(same ? Color.primary : (improved ? .green : .red))
                        }
                    }
                }
                .padding()
                .background(Color(.systemGray6), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal)

                Text("Returning to Home in 3 seconds…")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            dismiss()
        }
    }

    // MARK: – Helpers

    private func loadMembers() async {
        isLoadingMembers = true
        allMembers = (try? await service.fetchLeaderboard(clubID: service.daltonClubID)) ?? []
        if let mine = allMembers.first(where: { $0.userId == currentUID }) {
            selectedIDs.insert(mine.userId)
        }
        isLoadingMembers = false
    }

    private func computeTagResults() {
        // Sort selected players by score ascending (lowest score = best finish)
        let sortedByScore = selectedMembers.sorted {
            (Int(scores[$0.userId] ?? "") ?? Int.max) < (Int(scores[$1.userId] ?? "") ?? Int.max)
        }
        // Collect their tag numbers and sort ascending so best finisher claims the lowest tag
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
        isSaving   = true
        saveError  = nil
        let intScores = scores.compactMapValues { Int($0) }
        do {
            try await service.saveGroupRound(
                clubId:      service.daltonClubID,
                results:     tagResults,
                scores:      intScores,
                confirmedBy: currentUID
            )
            step = .success
        } catch {
            saveError = error.localizedDescription
        }
        isSaving = false
    }
}
