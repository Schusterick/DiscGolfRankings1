import Foundation
import UIKit
import FirebaseAuth
import FirebaseCore
import FirebaseFirestore
import AuthenticationServices
import CryptoKit
#if canImport(GoogleSignIn)
import GoogleSignIn       // SPM: https://github.com/google/GoogleSignIn-iOS
#endif
#if canImport(FBSDKLoginKit)
import FBSDKLoginKit      // SPM: https://github.com/facebook/facebook-ios-sdk
#endif

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
            UINotificationFeedbackGenerator().notificationOccurred(.error)
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
            UINotificationFeedbackGenerator().notificationOccurred(.error)
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
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
        isLoading = false
    }

    // MARK: - Sign in with Apple

    /// Raw nonce held between request creation and credential validation.
    /// Apple requires us to send a SHA-256 hash of this string in the auth request,
    /// then pass the original raw value to Firebase to prove possession.
    fileprivate var pendingAppleNonce: String?

    /// Builds a new ASAuthorizationAppleIDRequest with a fresh hashed nonce.
    /// Called by the SignInWithAppleButton in SignInView.
    func makeAppleSignInRequest(_ request: ASAuthorizationAppleIDRequest) {
        let nonce = Self.randomNonce()
        pendingAppleNonce = nonce
        request.requestedScopes = [.fullName, .email]
        request.nonce           = Self.sha256(nonce)
    }

    /// Completes Sign in with Apple by handing the Apple credential to Firebase.
    /// Creates the matching users/{uid} doc on first sign-in.
    func handleAppleSignInResult(_ result: Result<ASAuthorization, Error>) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        switch result {
        case .failure(let error):
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential,
                  let nonce = pendingAppleNonce,
                  let identityToken = credential.identityToken,
                  let tokenString = String(data: identityToken, encoding: .utf8)
            else {
                errorMessage = "Couldn't read Apple credential."
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                return
            }
            do {
                let firebaseCredential = OAuthProvider.appleCredential(
                    withIDToken: tokenString,
                    rawNonce:    nonce,
                    fullName:    credential.fullName
                )
                let result = try await Auth.auth().signIn(with: firebaseCredential)
                // First-time sign-in: create the users/{uid} doc
                let user = result.user
                let displayName = [credential.fullName?.givenName,
                                   credential.fullName?.familyName]
                    .compactMap { $0 }
                    .joined(separator: " ")
                if !displayName.isEmpty, user.displayName == nil {
                    let req = user.createProfileChangeRequest()
                    req.displayName = displayName
                    try? await req.commitChanges()
                }
                let userDoc = db.collection("users").document(user.uid)
                let existing = try? await userDoc.getDocument()
                if existing?.exists != true {
                    let appUserDoc = AppUser(
                        id:          user.uid,
                        email:       user.email ?? credential.email ?? "",
                        displayName: displayName.isEmpty ? (user.displayName ?? "Player") : displayName,
                        createdAt:   Date()
                    )
                    try? userDoc.setData(from: appUserDoc)
                }
            } catch {
                errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            pendingAppleNonce = nil
        }
    }

    // MARK: Nonce helpers

    /// Generates a cryptographically-random 32-character nonce (URL-safe charset).
    private static func randomNonce(length: Int = 32) -> String {
        precondition(length > 0)
        let charset: [Character] =
            Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._")
        var result = ""
        var remaining = length
        while remaining > 0 {
            var randoms = [UInt8](repeating: 0, count: 16)
            let status = SecRandomCopyBytes(kSecRandomDefault, randoms.count, &randoms)
            precondition(status == errSecSuccess)
            for byte in randoms where remaining > 0 {
                if byte < charset.count {
                    result.append(charset[Int(byte)])
                    remaining -= 1
                }
            }
        }
        return result
    }

    /// SHA-256 hash of the nonce — what Apple wants in the request.
    private static func sha256(_ input: String) -> String {
        let data = Data(input.utf8)
        let hash = SHA256.hash(data: data)
        return hash.map { String(format: "%02x", $0) }.joined()
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

    // MARK: - Sign in with Google
    #if canImport(GoogleSignIn)

    /// Presents Google's OAuth flow, exchanges the resulting ID token for a Firebase
    /// credential, and signs in. Creates the matching users/{uid} doc on first sign-in.
    func signInWithGoogle() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let clientID = FirebaseApp.app()?.options.clientID else {
            errorMessage = "Google sign-in is not configured."
            UINotificationFeedbackGenerator().notificationOccurred(.error)
            return
        }
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        guard let rootVC = Self.rootViewController() else {
            errorMessage = "Couldn't find a view to present from."
            return
        }

        do {
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: rootVC)
            guard let idToken = result.user.idToken?.tokenString else {
                errorMessage = "Google sign-in failed (no ID token)."
                return
            }
            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            let authResult = try await Auth.auth().signIn(with: credential)
            await createUserDocIfNeeded(authResult.user,
                                        displayName: result.user.profile?.name)
        } catch {
            // GoogleSignIn returns a cancellation error if the user dismissed the sheet
            let ns = error as NSError
            if ns.code == GIDSignInError.canceled.rawValue { return }
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
    #endif

    // MARK: - Sign in with Facebook
    #if canImport(FBSDKLoginKit)

    /// Presents Facebook Login, exchanges the resulting access token for a Firebase
    /// credential, and signs in. Creates the matching users/{uid} doc on first sign-in.
    func signInWithFacebook() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        guard let rootVC = Self.rootViewController() else {
            errorMessage = "Couldn't find a view to present from."
            return
        }

        let manager = LoginManager()
        do {
            let fbResult: LoginManagerLoginResult = try await withCheckedThrowingContinuation { cont in
                manager.logIn(permissions: ["public_profile", "email"], from: rootVC) { result, err in
                    if let err {
                        cont.resume(throwing: err)
                    } else if let result {
                        cont.resume(returning: result)
                    } else {
                        cont.resume(throwing: NSError(domain: "Facebook", code: 0,
                                                      userInfo: [NSLocalizedDescriptionKey: "No result"]))
                    }
                }
            }
            if fbResult.isCancelled { return }
            guard let token = AccessToken.current?.tokenString else {
                errorMessage = "Facebook sign-in failed (no access token)."
                return
            }
            let credential = FacebookAuthProvider.credential(withAccessToken: token)
            let authResult = try await Auth.auth().signIn(with: credential)
            await createUserDocIfNeeded(authResult.user, displayName: nil)
        } catch {
            errorMessage = error.localizedDescription
            UINotificationFeedbackGenerator().notificationOccurred(.error)
        }
    }
    #endif

    // MARK: - Helpers shared by all OAuth flows

    /// Creates the Firestore users/{uid} doc on first sign-in. No-op for returning users.
    private func createUserDocIfNeeded(_ user: User, displayName: String?) async {
        let ref = db.collection("users").document(user.uid)
        let existing = try? await ref.getDocument()
        guard existing?.exists != true else { return }
        let name = displayName ?? user.displayName ?? "Player"
        let appUser = AppUser(
            id:          user.uid,
            email:       user.email ?? "",
            displayName: name,
            createdAt:   Date()
        )
        try? ref.setData(from: appUser)
    }

    /// Returns the top-most UIViewController for presenting OAuth flows.
    /// Works for SwiftUI apps where there's no explicit UIWindow root.
    private static func rootViewController() -> UIViewController? {
        guard let scene = UIApplication.shared.connectedScenes
                .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene,
              let window = scene.windows.first(where: { $0.isKeyWindow }),
              var top = window.rootViewController
        else { return nil }
        while let presented = top.presentedViewController { top = presented }
        return top
    }
}
