import SwiftUI

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

    @State private var photoURL:  String = ""
    @State private var bio:       String = ""
    @State private var instagram: String = ""
    @State private var facebook:  String = ""
    @State private var twitter:   String = ""
    @State private var tiktok:    String = ""

    @State private var isSaving = false
    @State private var errorMsg: String?
    @State private var showSaved = false

    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()

                Form {
                    // MARK: Photo preview
                    Section {
                        VStack(spacing: 12) {
                            avatar
                            TextField("Profile picture URL", text: $photoURL)
                                .foregroundStyle(Theme.textPrimary)
                                .autocorrectionDisabled()
                                .textInputAutocapitalization(.never)
                                .keyboardType(.URL)
                            Text("Paste a public image URL (Instagram photo, Gravatar, Imgur, etc.)")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.vertical, 6)
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
        photoURL  = u?.photoURL  ?? ""
        bio       = u?.bio       ?? ""
        instagram = u?.instagram ?? ""
        facebook  = u?.facebook  ?? ""
        twitter   = u?.twitter   ?? ""
        tiktok    = u?.tiktok    ?? ""
    }

    private func save() async {
        guard let uid = auth.currentUser?.uid else { return }
        isSaving = true; errorMsg = nil
        do {
            try await service.updateUserProfile(
                uid: uid,
                photoURL:  photoURL.trimmingCharacters(in: .whitespaces),
                bio:       bio.trimmingCharacters(in: .whitespaces),
                instagram: instagram.trimmingCharacters(in: .whitespaces),
                facebook:  facebook.trimmingCharacters(in: .whitespaces),
                twitter:   twitter.trimmingCharacters(in: .whitespaces),
                tiktok:    tiktok.trimmingCharacters(in: .whitespaces)
            )
            await auth.reloadAppUser()
            showSaved = true
        } catch {
            errorMsg = error.localizedDescription
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
