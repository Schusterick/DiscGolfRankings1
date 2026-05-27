import SwiftUI

// MARK: - EventListRow
// Compact row used in the admin Events tab and the public club profile.

struct EventListRow: View {
    let event: Event
    var showStatus: Bool = true

    private var statusColor: Color {
        switch event.status {
        case .upcoming:  return Theme.accent
        case .completed: return Theme.success
        case .cancelled: return .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(event.title)
                        .font(.subheadline.bold())
                        .foregroundStyle(Theme.textPrimary)
                    Text(event.startDate.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    if let loc = event.location, !loc.isEmpty {
                        Label(loc, systemImage: "mappin.and.ellipse")
                            .font(.caption2).foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                if showStatus {
                    Text(event.status.rawValue.capitalized)
                        .font(.caption2.bold())
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(statusColor.opacity(0.15), in: Capsule())
                        .foregroundStyle(statusColor)
                }
            }
            HStack(spacing: 12) {
                Label("\(event.numberOfRounds) round\(event.numberOfRounds == 1 ? "" : "s")",
                      systemImage: "flag.checkered")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
                Label("\(event.goingCount) going",
                      systemImage: "person.fill.checkmark")
                    .font(.caption2).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - CreateEventView
// Admin-only form for creating a new event.

struct CreateEventView: View {
    let club: Club

    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var title          = ""
    @State private var description    = ""
    @State private var location       = ""
    @State private var startDate      = Date().addingTimeInterval(60 * 60 * 24 * 7)  // +1 week
    @State private var numberOfRounds = 1
    @State private var isSaving       = false
    @State private var errorMsg:       String?

    private var canSave: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Form {
                    Section("Event Details") {
                        TextField("Title (e.g. Saturday Doubles League)", text: $title)
                            .foregroundStyle(Theme.textPrimary)
                        TextField("Description (optional)", text: $description, axis: .vertical)
                            .lineLimit(2...5)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .listRowBackground(Theme.card)

                    Section("Where & When") {
                        TextField("Course / Location", text: $location)
                            .foregroundStyle(Theme.textPrimary)
                        DatePicker("Start", selection: $startDate, in: Date()...)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .listRowBackground(Theme.card)

                    Section("Rounds") {
                        Stepper(value: $numberOfRounds, in: 1...5) {
                            Text("\(numberOfRounds) round\(numberOfRounds == 1 ? "" : "s")")
                                .foregroundStyle(Theme.textPrimary)
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
                                else { Text("Create Event").fontWeight(.semibold).foregroundStyle(.white) }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .disabled(!canSave)
                    }
                    .listRowBackground(canSave ? Theme.accent.opacity(0.85) : Theme.accent.opacity(0.3))
                }
                .darkListStyle()
            }
            .navigationTitle("New Event")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func save() async {
        guard let clubId = club.id, let uid = auth.currentUser?.uid else { return }
        isSaving = true; errorMsg = nil
        let event = Event(
            clubId:         clubId,
            title:          title.trimmingCharacters(in: .whitespaces),
            description:    description.trimmingCharacters(in: .whitespaces),
            location:       location.trimmingCharacters(in: .whitespaces),
            startDate:      startDate,
            numberOfRounds: numberOfRounds,
            status:         .upcoming,
            rsvps:          [],
            demotion:       2,
            roundScores:    nil,
            playerTotals:   nil,
            oldTags:        nil,
            newTags:        nil,
            createdBy:      uid,
            createdAt:      Date(),
            completedAt:    nil
        )
        do {
            _ = try await service.createEvent(event)
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
        isSaving = false
    }
}

// MARK: - EventDetailView
// Public detail view — used by members from the club's public profile and by anyone
// from a deep link. Shows RSVPs and lets club members toggle their own.

struct EventDetailView: View {
    let event: Event
    let club:  Club
    var isClubMember: Bool        // controls visibility of the RSVP button

    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var current: Event
    @State private var isToggling = false
    @State private var errorMsg:   String?

    init(event: Event, club: Club, isClubMember: Bool) {
        self.event = event
        self.club = club
        self.isClubMember = isClubMember
        _current = State(initialValue: event)
    }

    private var myUID: String { auth.currentUser?.uid ?? "" }
    private var iAmGoing: Bool { current.rsvps?.contains(myUID) == true }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {

                        // Hero
                        VStack(alignment: .leading, spacing: 8) {
                            Text(current.title)
                                .font(.system(size: 28, weight: .black, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Label(current.startDate.formatted(date: .complete, time: .shortened),
                                  systemImage: "calendar")
                                .font(.subheadline)
                                .foregroundStyle(Theme.gold)
                            if let loc = current.location, !loc.isEmpty {
                                Label(loc, systemImage: "mappin.and.ellipse")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            Label("\(current.numberOfRounds) round\(current.numberOfRounds == 1 ? "" : "s")",
                                  systemImage: "flag.checkered")
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }

                        if let desc = current.description, !desc.isEmpty {
                            Text(desc)
                                .font(.body)
                                .foregroundStyle(Theme.textPrimary)
                                .padding(14)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                        }

                        // RSVP block
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Label("\(current.goingCount) going",
                                      systemImage: "person.fill.checkmark")
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                            }
                            if current.status == .cancelled {
                                Text("This event has been cancelled.")
                                    .font(.caption).foregroundStyle(.red)
                            } else if current.status == .completed {
                                Text("This event has ended.")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            } else if isClubMember {
                                Button { Task { await toggleRSVP() } } label: {
                                    Group {
                                        if isToggling { ProgressView().tint(.white) }
                                        else {
                                            Label(iAmGoing ? "Cancel RSVP" : "I'm Going",
                                                  systemImage: iAmGoing ? "xmark.circle" : "checkmark.circle.fill")
                                                .font(.headline).foregroundStyle(.white)
                                        }
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(iAmGoing ? Color.red.opacity(0.8) : Theme.accent,
                                                in: RoundedRectangle(cornerRadius: 12))
                                }
                                .disabled(isToggling)
                            } else {
                                Text("Only \(club.name) members can RSVP.")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            }
                            if let errorMsg { Text(errorMsg).font(.caption).foregroundStyle(.red) }
                        }
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .padding()
                }
            }
            .navigationTitle(club.name)
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func toggleRSVP() async {
        guard let eid = current.id else { return }
        isToggling = true; errorMsg = nil
        do {
            try await service.setEventRSVP(eventId: eid, userId: myUID, going: !iAmGoing)
            var rsvps = current.rsvps ?? []
            if iAmGoing {
                rsvps.removeAll { $0 == myUID }
            } else {
                rsvps.append(myUID)
            }
            current.rsvps = rsvps
        } catch {
            errorMsg = error.localizedDescription
        }
        isToggling = false
    }
}

// MARK: - SubmitEventScoresView
// Admin-only score entry grid. Lets the admin type in each player's per-round score,
// then opens the ranking preview before applying.

struct SubmitEventScoresView: View {
    let event: Event
    let club:  Club

    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var members:     [Membership] = []
    // [memberIndex][roundIndex] = score string (empty = no-show on that round)
    @State private var scores:      [[String]]   = []
    @State private var demotion:    Int          = 2
    @State private var isLoading    = true
    @State private var showPreview  = false
    @State private var errorMsg:    String?

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                if isLoading {
                    ProgressView().tint(Theme.accent)
                } else if members.isEmpty {
                    ContentUnavailableView(
                        "No Members",
                        systemImage: "person.slash",
                        description: Text("There are no active members to score.")
                    )
                    .foregroundStyle(Theme.textSecondary)
                } else {
                    scoreGrid
                }
            }
            .navigationTitle("Submit Scores")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
            .task { await load() }
            .sheet(isPresented: $showPreview) {
                EventResultsPreviewView(
                    event:      event,
                    members:    members,
                    eventTotals: computeTotals(),
                    demotion:   demotion,
                    onApply:    { await apply() }
                )
                .environmentObject(auth)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Grid

    @ViewBuilder
    private var scoreGrid: some View {
        VStack(spacing: 0) {
            // Header row
            HStack(spacing: 0) {
                Text("Player")
                    .font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(0..<event.numberOfRounds, id: \.self) { i in
                    Text("R\(i+1)")
                        .font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                        .frame(width: 56)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Theme.cardAlt)

            ScrollView {
                VStack(spacing: 0) {
                    ForEach(Array(members.enumerated()), id: \.element.id) { memberIdx, m in
                        memberRow(memberIdx: memberIdx, m: m)
                            .background(memberIdx % 2 == 0 ? Theme.card : Theme.cardAlt)
                    }
                }
            }

            // Footer: demotion picker + Preview button
            VStack(spacing: 10) {
                HStack {
                    Text("No-show demotion")
                        .font(.caption).foregroundStyle(Theme.textSecondary)
                    Spacer()
                    Picker("", selection: $demotion) {
                        Text("None (0)").tag(0)
                        Text("Gentle (1)").tag(1)
                        Text("Standard (2)").tag(2)
                        Text("Harsh (3)").tag(3)
                    }
                    .pickerStyle(.menu).tint(Theme.accent)
                }

                if let errorMsg { Text(errorMsg).font(.caption).foregroundStyle(.red) }

                Button { showPreview = true } label: {
                    Label("Preview New Rankings", systemImage: "eye")
                        .font(.headline).foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canPreview ? Theme.accent : Theme.accent.opacity(0.4),
                                    in: RoundedRectangle(cornerRadius: 12))
                }
                .disabled(!canPreview)
                .padding(.top, 4)
            }
            .padding()
        }
    }

    @ViewBuilder
    private func memberRow(memberIdx: Int, m: Membership) -> some View {
        HStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("#\(m.tagNumber)")
                    .font(.caption.bold().monospacedDigit())
                    .foregroundStyle(Theme.gold)
                Text(m.userFullName)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            ForEach(0..<event.numberOfRounds, id: \.self) { roundIdx in
                TextField("—",
                          text: Binding(
                            get:  { scoreCell(member: memberIdx, round: roundIdx) },
                            set:  { setScore(member: memberIdx, round: roundIdx, value: $0) }
                          ))
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 56)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 4)
                    .background(Theme.background, in: RoundedRectangle(cornerRadius: 6))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func scoreCell(member: Int, round: Int) -> String {
        guard member < scores.count, round < scores[member].count else { return "" }
        return scores[member][round]
    }
    private func setScore(member: Int, round: Int, value: String) {
        let filtered = String(value.filter(\.isNumber).prefix(3))
        guard member < scores.count, round < scores[member].count else { return }
        scores[member][round] = filtered
    }

    private var canPreview: Bool {
        !computeTotals().isEmpty
    }

    /// Sums every entered score per member, skipping members who left every round blank.
    private func computeTotals() -> [String: Int] {
        var totals: [String: Int] = [:]
        for (idx, m) in members.enumerated() {
            let rounds = scores[idx]
            // Sum only if at least one round has a score
            let entered = rounds.compactMap { Int($0) }
            guard !entered.isEmpty else { continue }
            totals[m.userId] = entered.reduce(0, +)
        }
        return totals
    }

    private func roundScoresForBatch() -> [[String: Int]] {
        var out: [[String: Int]] = []
        for r in 0..<event.numberOfRounds {
            var dict: [String: Int] = [:]
            for (idx, m) in members.enumerated() {
                if r < scores[idx].count, let s = Int(scores[idx][r]) {
                    dict[m.userId] = s
                }
            }
            out.append(dict)
        }
        return out
    }

    // MARK: Actions

    private func load() async {
        guard let clubId = club.id else { return }
        isLoading = true
        let fetched = (try? await service.fetchClubMembers(clubId: clubId)) ?? []
        members = fetched.sorted { $0.tagNumber < $1.tagNumber }
        scores  = Array(repeating: Array(repeating: "", count: event.numberOfRounds),
                        count: members.count)
        isLoading = false
    }

    private func apply() async {
        errorMsg = nil
        do {
            _ = try await service.submitEventResults(
                event: event,
                members: members,
                roundScores: roundScoresForBatch(),
                demotion: demotion
            )
            dismiss()
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}

// MARK: - EventResultsPreviewView
// Shown after the admin taps "Preview" — side-by-side old → new tags.

struct EventResultsPreviewView: View {
    let event:       Event
    let members:     [Membership]
    let eventTotals: [String: Int]
    let demotion:    Int
    let onApply:     () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isApplying = false

    private var rows: [RankingEngine.PreviewRow] {
        RankingEngine.preview(members: members, eventTotals: eventTotals, demotion: demotion)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    // Header strip
                    HStack {
                        Text("Old").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                            .frame(width: 50, alignment: .center)
                        Text("→").foregroundStyle(Theme.textSecondary)
                            .frame(width: 20)
                        Text("New").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                            .frame(width: 50, alignment: .center)
                        Text("Player").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 12)
                        Text("Score").font(.caption.bold()).foregroundStyle(Theme.textSecondary)
                            .frame(width: 50, alignment: .trailing)
                    }
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(Theme.cardAlt)

                    List(rows) { row in
                        HStack(spacing: 0) {
                            Text("#\(row.oldTag)")
                                .font(.caption.bold().monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 50, alignment: .center)
                            Image(systemName: row.delta > 0 ? "arrow.down"
                                            : (row.delta < 0 ? "arrow.up" : "equal"))
                                .font(.caption2.bold())
                                .foregroundStyle(row.delta > 0 ? Theme.success
                                                : (row.delta < 0 ? Theme.accent : Theme.textSecondary))
                                .frame(width: 20)
                            Text("#\(row.newTag)")
                                .font(.subheadline.bold().monospacedDigit())
                                .foregroundStyle(Theme.gold)
                                .frame(width: 50, alignment: .center)
                            HStack(spacing: 4) {
                                Text(row.name)
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textPrimary)
                                    .lineLimit(1)
                                if !row.attended {
                                    Text("(no-show)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(.orange)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.leading, 12)
                            Text(row.total.map { "\($0)" } ?? "—")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(Theme.textSecondary)
                                .frame(width: 50, alignment: .trailing)
                        }
                        .listRowBackground(Theme.card)
                        .listRowSeparatorTint(Theme.divider)
                    }
                    .darkListStyle()

                    // Apply button
                    Button {
                        Task {
                            isApplying = true
                            await onApply()
                            isApplying = false
                            dismiss()
                        }
                    } label: {
                        Group {
                            if isApplying { ProgressView().tint(.white) }
                            else { Label("Apply New Rankings", systemImage: "checkmark.seal.fill")
                                    .font(.headline).foregroundStyle(.white) }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isApplying)
                    .padding()
                }
            }
            .navigationTitle("Preview Rankings")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Back") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - EventManageView (admin)
// Tapping an upcoming event in the admin Events tab opens this. Shows RSVPs,
// "Submit Scores" entry, and a Cancel option.

struct EventManageView: View {
    let event: Event
    let club:  Club

    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var showSubmit       = false
    @State private var showCancelConfirm = false
    @State private var current:          Event
    @State private var rsvpMembers:     [Membership] = []
    @State private var isCancelling     = false
    @State private var isReminding      = false
    @State private var reminderSent     = false

    init(event: Event, club: Club) {
        self.event = event
        self.club = club
        _current = State(initialValue: event)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(current.title)
                                .font(.system(size: 24, weight: .black, design: .rounded))
                                .foregroundStyle(Theme.textPrimary)
                            Label(current.startDate.formatted(date: .complete, time: .shortened),
                                  systemImage: "calendar")
                                .font(.subheadline).foregroundStyle(Theme.gold)
                            if let loc = current.location, !loc.isEmpty {
                                Label(loc, systemImage: "mappin.and.ellipse")
                                    .font(.subheadline).foregroundStyle(Theme.textSecondary)
                            }
                            Label("\(current.numberOfRounds) round\(current.numberOfRounds == 1 ? "" : "s")",
                                  systemImage: "flag.checkered")
                                .font(.subheadline).foregroundStyle(Theme.textSecondary)
                        }

                        if let desc = current.description, !desc.isEmpty {
                            Text(desc).font(.body).foregroundStyle(Theme.textPrimary)
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Theme.card, in: RoundedRectangle(cornerRadius: 10))
                        }

                        // RSVPs
                        VStack(alignment: .leading, spacing: 8) {
                            Label("\(current.goingCount) going",
                                  systemImage: "person.fill.checkmark")
                                .font(.headline).foregroundStyle(Theme.textPrimary)
                            if rsvpMembers.isEmpty {
                                Text("No RSVPs yet.")
                                    .font(.caption).foregroundStyle(Theme.textSecondary)
                            } else {
                                ForEach(rsvpMembers) { m in
                                    HStack {
                                        Text("#\(m.tagNumber)").font(.caption.bold())
                                            .foregroundStyle(Theme.gold).frame(width: 36)
                                        Text(m.userFullName).font(.subheadline)
                                            .foregroundStyle(Theme.textPrimary)
                                        Spacer()
                                    }
                                }
                            }
                        }
                        .padding(14)
                        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))

                        // Actions
                        if current.status == .upcoming {
                            Button { showSubmit = true } label: {
                                Label("Submit Scores", systemImage: "square.and.pencil")
                                    .font(.headline).foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 14)
                                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12))
                            }

                            Button { Task { await sendReminder() } } label: {
                                Group {
                                    if isReminding { ProgressView().tint(.white) }
                                    else if reminderSent {
                                        Label("Reminder Sent", systemImage: "checkmark.circle.fill")
                                            .font(.subheadline.bold()).foregroundStyle(.white)
                                    } else {
                                        Label("Send Reminder to Members", systemImage: "bell.fill")
                                            .font(.subheadline.bold()).foregroundStyle(.white)
                                    }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Theme.gold.opacity(0.85),
                                            in: RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(isReminding || reminderSent)

                            Button(role: .destructive) { showCancelConfirm = true } label: {
                                Group {
                                    if isCancelling { ProgressView().tint(.white) }
                                    else { Label("Cancel Event", systemImage: "xmark.circle.fill")
                                            .font(.subheadline.bold()).foregroundStyle(.white) }
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.8),
                                            in: RoundedRectangle(cornerRadius: 12))
                            }
                            .disabled(isCancelling)
                        } else if current.status == .completed {
                            Label("Event completed — rankings applied",
                                  systemImage: "checkmark.seal.fill")
                                .font(.subheadline.bold())
                                .foregroundStyle(Theme.success)
                                .padding(14)
                                .frame(maxWidth: .infinity)
                                .background(Theme.success.opacity(0.10),
                                            in: RoundedRectangle(cornerRadius: 12))
                        } else {
                            Label("Cancelled", systemImage: "xmark.circle.fill")
                                .font(.subheadline.bold()).foregroundStyle(.red)
                                .padding(14).frame(maxWidth: .infinity)
                                .background(Color.red.opacity(0.10),
                                            in: RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("Event")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
            .task { await loadRSVPs() }
            .sheet(isPresented: $showSubmit, onDismiss: { dismiss() }) {
                SubmitEventScoresView(event: current, club: club)
                    .environmentObject(auth)
            }
            .confirmationDialog("Cancel \"\(current.title)\"?",
                                isPresented: $showCancelConfirm,
                                titleVisibility: .visible) {
                Button("Cancel Event", role: .destructive) { Task { await cancel() } }
                Button("Keep Event", role: .cancel) { }
            }
        }
        .preferredColorScheme(.dark)
    }

    private func loadRSVPs() async {
        guard let clubId = club.id else { return }
        let all = (try? await service.fetchClubMembers(clubId: clubId)) ?? []
        let going = Set(current.rsvps ?? [])
        rsvpMembers = all.filter { going.contains($0.userId) }
                         .sorted { $0.tagNumber < $1.tagNumber }
    }

    private func cancel() async {
        isCancelling = true
        try? await service.cancelEvent(current)
        isCancelling = false
        dismiss()
    }

    private func sendReminder() async {
        guard let clubId = club.id else { return }
        isReminding = true
        let dateStr = current.startDate.formatted(date: .abbreviated, time: .shortened)
        let msg = "🔔 Reminder: \(current.title) — \(dateStr)" +
                  ((current.location?.isEmpty ?? true) ? "" : " @ \(current.location!)")
        _ = try? await service.sendNotificationToAllClubMembers(clubId: clubId, message: msg)
        reminderSent = true
        isReminding = false
    }
}
