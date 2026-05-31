import SwiftUI

// MARK: - CompleteProfileView
// Hard gate shown after signup, before onboarding. Required fields:
//   - First name
//   - Last name
//   - Years playing
//
// No Cancel button, no swipe-to-dismiss. The only way out is "Save" with all
// three fields filled. After save, the user's appUser is reloaded and the
// AppEntry router moves them on to OnboardingView.
//
// The CTA is "Save" — optional things like PDGA, favorite course, bio, and
// social handles live in EditProfileView and can be added later from Profile.

struct CompleteProfileView: View {
    @EnvironmentObject var auth: AuthService
    private let service = FirebaseService.shared

    @State private var firstName = ""
    @State private var lastName  = ""
    @State private var yearsPlayingStr = ""

    @State private var isSaving = false
    @State private var errorMsg: String?

    private var canSubmit: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty &&
        !lastName.trimmingCharacters(in: .whitespaces).isEmpty &&
        Int(yearsPlayingStr.trimmingCharacters(in: .whitespaces)) != nil &&
        !isSaving
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    // Hero
                    VStack(spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 60))
                            .foregroundStyle(Theme.gold)
                            .shadow(color: Theme.gold.opacity(0.4), radius: 12)
                            .padding(.top, 32)

                        Text("Tell Us About You")
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)

                        Text("Clubs and leaderboards need to know who you are.\nYou can add more later.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }

                    // Form
                    VStack(spacing: 14) {
                        labeledField(
                            label: "First Name",
                            icon: "person.fill",
                            placeholder: "First name",
                            text: $firstName,
                            contentType: .givenName,
                            keyboard: .default
                        )
                        labeledField(
                            label: "Last Name",
                            icon: "person.fill",
                            placeholder: "Last name",
                            text: $lastName,
                            contentType: .familyName,
                            keyboard: .default
                        )
                        labeledField(
                            label: "Years Playing Disc Golf",
                            icon: "calendar",
                            placeholder: "e.g. 3",
                            text: $yearsPlayingStr,
                            contentType: nil,
                            keyboard: .numberPad
                        )
                    }
                    .padding(.horizontal, 20)

                    if let errorMsg {
                        Text(errorMsg)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .padding(.horizontal, 24)
                    }

                    // Save
                    Button { Task { await save() } } label: {
                        Group {
                            if isSaving {
                                ProgressView().tint(.white)
                            } else {
                                Text("Save & Continue")
                                    .font(.headline)
                                    .foregroundStyle(.white)
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(
                            (canSubmit ? Theme.accent : Theme.accent.opacity(0.4)),
                            in: RoundedRectangle(cornerRadius: 14)
                        )
                    }
                    .disabled(!canSubmit)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 32)
                }
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .preferredColorScheme(.dark)
        .interactiveDismissDisabled(true)   // can't swipe away
        .onAppear(perform: prefillFromAuth)
    }

    // MARK: Pre-fill from existing data (Apple/Google may give us a name)

    private func prefillFromAuth() {
        let current = auth.appUser?.displayName ?? auth.currentUser?.displayName ?? ""
        let trimmed = current.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        let parts = trimmed.split(separator: " ", maxSplits: 1)
        if firstName.isEmpty { firstName = parts.first.map(String.init) ?? "" }
        if lastName.isEmpty,  parts.count > 1 { lastName = String(parts.last!) }
        // yearsPlaying never pre-fills — must be entered explicitly
    }

    // MARK: Labeled field component

    @ViewBuilder
    private func labeledField(
        label: String,
        icon: String,
        placeholder: String,
        text: Binding<String>,
        contentType: UITextContentType?,
        keyboard: UIKeyboardType
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.caption.bold())
                .foregroundStyle(Theme.textSecondary)
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .foregroundStyle(Theme.gold)
                    .frame(width: 24)
                TextField(placeholder, text: text)
                    .foregroundStyle(Theme.textPrimary)
                    .keyboardType(keyboard)
                    .textContentType(contentType)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    // MARK: Save

    private func save() async {
        guard let uid = auth.currentUser?.uid, canSubmit else { return }
        isSaving = true; errorMsg = nil
        defer { isSaving = false }
        let full = "\(firstName.trimmingCharacters(in: .whitespaces)) \(lastName.trimmingCharacters(in: .whitespaces))"
        let yrs  = Int(yearsPlayingStr.trimmingCharacters(in: .whitespaces))
        do {
            try await service.updateUserProfile(
                uid: uid,
                displayName: full,
                yearsPlaying: yrs
            )
            try? await service.updateAuthDisplayName(full)
            await auth.reloadAppUser()
            // No explicit dismiss — AppEntry routing observes appUser changes and moves on.
        } catch {
            errorMsg = error.localizedDescription
        }
    }
}
