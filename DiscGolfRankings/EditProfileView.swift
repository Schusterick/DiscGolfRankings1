import SwiftUI
import UIKit
import FirebaseAuth

// MARK: - EditProfileView
// Opened from Profile → "Edit Profile". Lets the user set a photo URL,
// a short bio, and social media handles.
//
// PHOTO UPLOAD NOTE:
// We accept a public URL for now (paste from Instagram, Gravatar, Imgur, etc.).
// TODO: Upgrade to native photo upload by adding FirebaseStorage via SPM and
//       wiring up PhotosPicker → upload → save the resulting download URL.

struct EditProfileView: View {
    @EnvironmentObject var auth: AuthService
    @Environment(\.dismiss) private var dismiss
    private let service = FirebaseService.shared

    @State private var firstName: String = ""
    @State private var lastName:  String = ""
    @State private var email:     String = ""
    @State private var originalEmail: String = ""    // to detect change
    @State private var photoURL:  String = ""
    @State private var bio:       String = ""
    @State private var instagram: String = ""
    @State private var facebook:  String = ""
    @State private var twitter:   String = ""
    @State private var tiktok:    String = ""
    @State private var favoriteCourse: String = ""
    @State private var yearsPlayingStr: String = ""

    @State private var isSaving = false
    @State private var errorMsg: String?
    @State private var showSaved = false
    @State private var showEmailNote = false        // shown after a successful email-change request

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                Form {
                    // MARK: Photo upload
                    Section {
                        VStack(spacing: 12) {
                            if let uid = auth.currentUser?.uid {
                                PhotoUploadAvatar(
                                    storagePath: "users/\(uid)/profile.jpg",
                                    photoURL: $photoURL,
                                    initials: initials,
                                    diameter: 110
                                )
                            } else {
                                avatar
                            }
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .listRowBackground(Theme.card)

                    // MARK: Name
                    Section("Your Name") {
                        TextField("First name", text: $firstName)
                            .foregroundStyle(Theme.textPrimary)
                            .textContentType(.givenName)
                            .autocorrectionDisabled()
                        TextField("Last name", text: $lastName)
                            .foregroundStyle(Theme.textPrimary)
                            .textContentType(.familyName)
                            .autocorrectionDisabled()
                    }
                    .listRowBackground(Theme.card)

                    // MARK: Email
                    Section(header: Text("Email").foregroundStyle(Theme.textSecondary),
                            footer: Text(email == originalEmail
                                         ? "Used for sign-in. Won't be shown publicly to other players."
                                         : "We'll send a verification link to the new address. Your email won't change until you click that link.")
                                        .font(.caption2)
                                        .foregroundStyle(Theme.textSecondary)) {
                        TextField("you@example.com", text: $email)
                            .foregroundStyle(Theme.textPrimary)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    .listRowBackground(Theme.card)

                    // MARK: Bio
                    Section("Bio") {
                        TextField("Tell other players about yourself…",
                                  text: $bio, axis: .vertical)
                            .lineLimit(2...5)
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .listRowBackground(Theme.card)

                    // MARK: Disc-golf fun facts
                    Section("Disc Golf") {
                        HStack {
                            Image(systemName: "flag.fill").foregroundStyle(Theme.gold).frame(width: 24)
                            TextField("Favorite course", text: $favoriteCourse)
                                .foregroundStyle(Theme.textPrimary)
                        }
                        HStack {
                            Image(systemName: "calendar").foregroundStyle(Theme.gold).frame(width: 24)
                            TextField("Years playing", text: $yearsPlayingStr)
                                .foregroundStyle(Theme.textPrimary)
                                .keyboardType(.numberPad)
                        }
                    }
                    .listRowBackground(Theme.card)

                    // MARK: Socials
                    Section("Social Links") {
                        socialField(icon: "camera.circle.fill",
                                    label: "Instagram", placeholder: "username",
                                    text: $instagram)
                        socialField(icon: "f.circle.fill",
                                    label: "Facebook", placeholder: "profile URL or handle",
                                    text: $facebook)
                        socialField(icon: "bird.fill",
                                    label: "Twitter / X", placeholder: "username",
                                    text: $twitter)
                        socialField(icon: "music.note",
                                    label: "TikTok", placeholder: "username",
                                    text: $tiktok)
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
                                else { Text("Save Changes").fontWeight(.semibold).foregroundStyle(.white) }
                            }
                            .frame(maxWidth: .infinity).padding(.vertical, 4)
                        }
                        .disabled(isSaving)
                    }
                    .listRowBackground(Theme.accent.opacity(0.85))
                }
                .darkListStyle()
            }
            .navigationTitle("Edit Profile")
            .navigationBarTitleDisplayMode(.inline)
            .darkNavBar()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.foregroundStyle(Theme.accent)
                }
            }
            .onAppear { loadCurrent() }
            .alert("Saved!", isPresented: $showSaved) {
                Button("OK") { dismiss() }
            }
            .alert("Check your inbox", isPresented: $showEmailNote) {
                Button("OK") { dismiss() }
            } message: {
                Text("We sent a verification link to your new email. Your email won't change until you click that link.")
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Avatar preview

    @ViewBuilder
    private var avatar: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(colors: [Theme.accent, Theme.gold],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 96, height: 96)
            if let url = URL(string: photoURL), !photoURL.isEmpty {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        ProgressView().tint(.white)
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        Image(systemName: "photo.badge.exclamationmark")
                            .font(.system(size: 32)).foregroundStyle(.white)
                    @unknown default:
                        EmptyView()
                    }
                }
                .frame(width: 92, height: 92)
                .clipShape(Circle())
            } else {
                Text(initials)
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
            }
        }
        .shadow(color: Theme.accent.opacity(0.4), radius: 12)
    }

    private var initials: String {
        let parts = (auth.appUser?.displayName ?? auth.currentUser?.displayName ?? "P")
            .split(separator: " ")
        let first = parts.first?.prefix(1) ?? "?"
        let last  = parts.count > 1 ? parts.last!.prefix(1) : Substring("")
        return "\(first)\(last)".uppercased()
    }

    // MARK: Social field

    @ViewBuilder
    private func socialField(icon: String, label: String,
                             placeholder: String, text: Binding<String>) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(Theme.gold).frame(width: 24)
            VStack(alignment: .leading, spacing: 0) {
                Text(label).font(.caption).foregroundStyle(Theme.textSecondary)
                TextField(placeholder, text: text)
                    .foregroundStyle(Theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }
        }
    }

    // MARK: Actions

    private func loadCurrent() {
        let u = auth.appUser
        photoURL        = u?.photoURL        ?? ""
        bio             = u?.bio             ?? ""
        instagram       = u?.instagram       ?? ""
        facebook        = u?.facebook        ?? ""
        twitter         = u?.twitter         ?? ""
        tiktok          = u?.tiktok          ?? ""
        favoriteCourse  = u?.favoriteCourse  ?? ""
        yearsPlayingStr = u?.yearsPlaying.map { String($0) } ?? ""

        // Split current displayName into first/last for editing
        let full = (u?.displayName ?? auth.currentUser?.displayName ?? "")
            .trimmingCharacters(in: .whitespaces)
        let parts = full.split(separator: " ", maxSplits: 1)
        firstName = parts.first.map(String.init) ?? ""
        lastName  = parts.count > 1 ? String(parts.last!) : ""

        email         = u?.email ?? auth.currentUser?.email ?? ""
        originalEmail = email
    }

    private var combinedName: String {
        let f = firstName.trimmingCharacters(in: .whitespaces)
        let l = lastName.trimmingCharacters(in: .whitespaces)
        return [f, l].filter { !$0.isEmpty }.joined(separator: " ")
    }

    private func save() async {
        guard let uid = auth.currentUser?.uid else { return }
        isSaving = true; errorMsg = nil
        let newName = combinedName
        let newEmail = email.trimmingCharacters(in: .whitespaces)
        let emailChanged = newEmail.lowercased() != originalEmail.lowercased() && !newEmail.isEmpty

        do {
            // 1. Push display name + bio/photo/socials to Firestore
            try await service.updateUserProfile(
                uid: uid,
                displayName:    newName.isEmpty ? nil : newName,
                photoURL:       photoURL.trimmingCharacters(in: .whitespaces),
                bio:            bio.trimmingCharacters(in: .whitespaces),
                instagram:      instagram.trimmingCharacters(in: .whitespaces),
                facebook:       facebook.trimmingCharacters(in: .whitespaces),
                twitter:        twitter.trimmingCharacters(in: .whitespaces),
                tiktok:         tiktok.trimmingCharacters(in: .whitespaces),
                favoriteCourse: favoriteCourse.trimmingCharacters(in: .whitespaces),
                yearsPlaying:   Int(yearsPlayingStr.trimmingCharacters(in: .whitespaces))
            )

            // 2. Keep Firebase Auth in sync with the new display name
            if !newName.isEmpty {
                try? await service.updateAuthDisplayName(newName)
            }

            // 3. Email change — sends verification link to the new address
            if emailChanged {
                try await service.sendEmailChangeVerification(newEmail: newEmail)
                await auth.reloadAppUser()
                showEmailNote = true
                isSaving = false
                return
            }

            await auth.reloadAppUser()
            showSaved = true
        } catch let err as NSError where err.code == AuthErrorCode.requiresRecentLogin.rawValue {
            errorMsg = "For security, please sign out and back in before changing your email."
        } catch {
            errorMsg = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        isSaving = false
    }
}

// MARK: - SocialLinksRow
// Reusable row displayed on the Profile screen. Shows up to four tappable social icons.

struct SocialLinksRow: View {
    let user: AppUser

    var body: some View {
        HStack(spacing: 14) {
            if let h = user.instagram, !h.isEmpty {
                socialButton(icon: "camera.circle.fill", color: .pink, url: instagramURL(h))
            }
            if let h = user.facebook, !h.isEmpty {
                socialButton(icon: "f.circle.fill", color: .blue, url: facebookURL(h))
            }
            if let h = user.twitter, !h.isEmpty {
                socialButton(icon: "bird.fill", color: Color(hex: "1D9BF0"), url: twitterURL(h))
            }
            if let h = user.tiktok, !h.isEmpty {
                socialButton(icon: "music.note", color: .white, url: tiktokURL(h))
            }
        }
    }

    @ViewBuilder
    private func socialButton(icon: String, color: Color, url: URL?) -> some View {
        Button {
            if let url { UIApplication.shared.open(url) }
        } label: {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 36, height: 36)
                .background(Theme.card, in: Circle())
                .overlay(Circle().stroke(Theme.divider, lineWidth: 1))
        }
    }

    // URL builders — strip a leading @ if pasted, accept full URLs as-is.
    private func instagramURL(_ s: String) -> URL? {
        if s.lowercased().hasPrefix("http") { return URL(string: s) }
        let handle = s.replacingOccurrences(of: "@", with: "")
        return URL(string: "https://instagram.com/\(handle)")
    }
    private func facebookURL(_ s: String) -> URL? {
        if s.lowercased().hasPrefix("http") { return URL(string: s) }
        return URL(string: "https://facebook.com/\(s)")
    }
    private func twitterURL(_ s: String) -> URL? {
        if s.lowercased().hasPrefix("http") { return URL(string: s) }
        let handle = s.replacingOccurrences(of: "@", with: "")
        return URL(string: "https://twitter.com/\(handle)")
    }
    private func tiktokURL(_ s: String) -> URL? {
        if s.lowercased().hasPrefix("http") { return URL(string: s) }
        let handle = s.replacingOccurrences(of: "@", with: "")
        return URL(string: "https://tiktok.com/@\(handle)")
    }
}
