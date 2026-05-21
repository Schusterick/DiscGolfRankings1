import Foundation
import FirebaseAuth
import FirebaseFirestore

@MainActor
class AuthService: ObservableObject {
    @Published var currentUser: User?
    @Published var appUser: AppUser?
    @Published var isLoading = false
    @Published var errorMessage: String?

    private var authStateHandle: AuthStateDidChangeListenerHandle?
    private let db = Firestore.firestore()

    init() {
        authStateHandle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            Task { @MainActor in
                self?.currentUser = user
                if let user {
                    await self?.fetchAppUser(uid: user.uid)
                } else {
                    self?.appUser = nil
                }
            }
        }
    }

    deinit {
        if let handle = authStateHandle {
            Auth.auth().removeStateDidChangeListener(handle)
        }
    }

    var isSignedIn: Bool { currentUser != nil }
    var isAppAdmin: Bool { isSuperAdmin || currentUser?.uid == FirebaseService.shared.adminUID }

    /// Hard-coded "super admin" — full control over every club, member, round, and user.
    /// Update this list to add/remove super admins.
    static let superAdminEmails: Set<String> = ["will@prodigydisc.com"]

    var isSuperAdmin: Bool {
        guard let email = currentUser?.email?.lowercased() else { return false }
        return Self.superAdminEmails.contains(email)
    }

    func signIn(email: String, password: String) async {
        isLoading = true
        errorMessage = nil
        do {
            try await Auth.auth().signIn(withEmail: email, password: password)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signUp(email: String, password: String, displayName: String) async {
        isLoading = true
        errorMessage = nil
        do {
            let result = try await Auth.auth().createUser(withEmail: email, password: password)
            let changeRequest = result.user.createProfileChangeRequest()
            changeRequest.displayName = displayName
            try await changeRequest.commitChanges()

            let newUser = AppUser(
                id: result.user.uid,
                email: email,
                displayName: displayName,
                createdAt: Date()
            )
            try db.collection("users").document(result.user.uid).setData(from: newUser)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func signOut() {
        try? Auth.auth().signOut()
    }

    func resetPassword(email: String) async {
        isLoading = true
        errorMessage = nil
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func fetchAppUser(uid: String) async {
        do {
            let doc = try await db.collection("users").document(uid).getDocument()
            appUser = try doc.data(as: AppUser.self)
        } catch {
            // user doc may not exist yet for brand-new signups — ignore
        }
    }

    /// Public reload — call after editing the profile so the cached `appUser` updates.
    func reloadAppUser() async {
        guard let uid = currentUser?.uid else { return }
        await fetchAppUser(uid: uid)
    }

    func updateDisplayName(_ name: String) async throws {
        guard let user = currentUser, !name.isEmpty else { return }
        let req = user.createProfileChangeRequest()
        req.displayName = name
        try await req.commitChanges()
    }
}
