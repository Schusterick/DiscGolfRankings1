import SwiftUI

// MARK: - AdminTabView

struct AdminTabView: View {
    private let service = FirebaseService.shared

    @State private var applications: [ClubApplication] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                Group {
                    if isLoading && applications.isEmpty {
                        ProgressView().tint(Theme.accent)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else if applications.isEmpty {
                        ContentUnavailableView(
                            "No Pending Applications",
                            systemImage: "checkmark.seal",
                            description: Text("All club requests have been reviewed.")
                        )
                        .foregroundStyle(Theme.textSecondary)
                    } else {
                        List {
                            Section("\(applications.count) Pending") {
                                ForEach(applications) { app in
                                    ClubApplicationRowView(application: app) {
                                        await loadApplications()
                                    }
                                    .listRowBackground(Theme.card)
                                    .listRowSeparatorTint(Theme.divider)
                                }
                            }
                        }
                        .darkListStyle()
                    }
                }
            }
            .navigationTitle("Club Applications")
            .navigationBarTitleDisplayMode(.large)
            .darkNavBar()
            .task { await loadApplications() }
            .refreshable { await loadApplications() }
        }
        .preferredColorScheme(.dark)
    }

    private func loadApplications() async {
        isLoading = true
        applications = (try? await service.fetchPendingApplications()) ?? []
        isLoading = false
    }
}

// MARK: - ClubApplicationRowView

struct ClubApplicationRowView: View {
    let application: ClubApplication
    let onAction: () async -> Void

    private let service = FirebaseService.shared

    @State private var isApproving       = false
    @State private var isRejecting        = false
    @State private var showRejectConfirm  = false
    @State private var expanded           = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {

            // Header row
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(application.clubName)
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("\(application.city), \(application.state)")
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 3) {
                    Text(application.submittedAt.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                    Text(application.applicantName)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            // Description — tap to expand
            Text(application.description)
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(expanded ? nil : 2)
                .onTapGesture { withAnimation { expanded.toggle() } }

            // Optional details
            if !application.website.isEmpty {
                Label(application.website, systemImage: "globe")
                    .font(.caption)
                    .foregroundStyle(Theme.accent)
                    .lineLimit(1)
            }

            Label(application.contactEmail, systemImage: "envelope")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)

            Divider().background(Theme.divider)

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    Task { await approve() }
                } label: {
                    Group {
                        if isApproving {
                            ProgressView().tint(.white)
                        } else {
                            Label("Approve", systemImage: "checkmark.circle.fill")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.success)
                .disabled(isApproving || isRejecting)

                Button(role: .destructive) {
                    showRejectConfirm = true
                } label: {
                    Group {
                        if isRejecting {
                            ProgressView().tint(.white)
                        } else {
                            Label("Reject", systemImage: "xmark.circle.fill")
                                .fontWeight(.semibold)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red.opacity(0.8))
                .disabled(isApproving || isRejecting)
            }
        }
        .padding(.vertical, 6)
        .confirmationDialog(
            "Reject \"\(application.clubName)\"?",
            isPresented: $showRejectConfirm,
            titleVisibility: .visible
        ) {
            Button("Reject Application", role: .destructive) {
                Task { await reject() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This will mark the application as rejected. The applicant will not be notified automatically.")
        }
    }

    // MARK: Actions

    private func approve() async {
        isApproving = true
        do {
            try await service.approveClubApplication(application)
        } catch { }
        await onAction()
        isApproving = false
    }

    private func reject() async {
        isRejecting = true
        do {
            try await service.rejectClubApplication(application.id ?? "")
        } catch { }
        await onAction()
        isRejecting = false
    }
}
