import Foundation
import UIKit
import UserNotifications
import FirebaseAuth
import FirebaseFirestore
#if canImport(FirebaseMessaging)
import FirebaseMessaging
#endif

// MARK: - PushNotificationService
//
// Centralized handler for push notifications:
//   • Asks iOS for permission on first launch
//   • Registers the device with APNs
//   • Receives the FCM registration token from Firebase Messaging
//   • Persists that token on the signed-in user's Firestore doc so the
//     server-side onNotificationCreated Cloud Function can target this device
//   • Routes a tapped notification to the right deep link using the `meta`
//     dictionary attached by the trigger
//
// Wiring:
//   1. AppEntry.init() calls PushNotificationService.shared.configure()
//      AFTER FirebaseApp.configure()
//   2. UIApplicationDelegateAdaptor in DiscGolfRankingsApp passes APNs
//      callbacks through to FirebaseMessaging
//
// SPM dependency:
//   FirebaseMessaging — already linked via the firebase-ios-sdk umbrella SPM
//   that the project uses for Auth/Firestore. The #if canImport guard means
//   the file compiles even before the product is linked to the target — the
//   actual push wiring just no-ops until then.

@MainActor
final class PushNotificationService: NSObject {
    static let shared = PushNotificationService()

    private let db = Firestore.firestore()
    private var didConfigure = false

    /// Called from `AppEntry.init()` after `FirebaseApp.configure()`.
    /// Safe to call multiple times — internal guard prevents re-registration.
    func configure() {
        guard !didConfigure else { return }
        didConfigure = true

        UNUserNotificationCenter.current().delegate = self

        #if canImport(FirebaseMessaging)
        Messaging.messaging().delegate = self
        #endif

        // Ask for permission. Returning users who've already decided will not
        // see a prompt — iOS just resolves with their saved choice.
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .badge, .sound]
        ) { granted, error in
            #if DEBUG
            print("📮 [APNsDiag] requestAuthorization granted=\(granted) error=\(error?.localizedDescription ?? "nil")")
            #endif
            guard granted else { return }
            DispatchQueue.main.async {
                #if DEBUG
                print("📮 [APNsDiag] Calling registerForRemoteNotifications()")
                #endif
                UIApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// Called from the app delegate when APNs hands us the device token.
    func setAPNSDeviceToken(_ data: Data) {
        #if DEBUG
        let hex = data.map { String(format: "%02x", $0) }.joined()
        print("📮 [APNsDiag] APNs device token received (\(data.count) bytes): \(hex.prefix(16))…")
        #endif
        #if canImport(FirebaseMessaging)
        Messaging.messaging().apnsToken = data
        #if DEBUG
        print("📮 [APNsDiag] Set Messaging.apnsToken — Firebase will now link FCM↔APNs")
        #endif
        #endif
    }

    /// Re-write the current FCM token to the now-signed-in user's doc.
    /// Called from AuthService whenever auth state flips to signed-in, so a
    /// brand-new signup's first token (which arrived BEFORE auth completed)
    /// still lands on the right Firestore doc.
    func rebroadcastTokenToCurrentUser() {
        #if canImport(FirebaseMessaging)
        Messaging.messaging().token { [weak self] token, _ in
            guard let token else { return }
            Task { @MainActor in
                self?.persistFCMToken(token)
            }
        }
        #endif
    }

    /// Persists the FCM token to the current user's Firestore doc.
    /// Called whenever Firebase Messaging hands us a fresh token (first time,
    /// or after iOS rotates it). No-op if no user is signed in yet — token
    /// will be re-requested on next sign-in.
    fileprivate func persistFCMToken(_ token: String) {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        db.collection("users").document(uid).setData(
            ["fcmToken": token],
            merge: true
        )
    }

    /// Reads the `meta` dict from a tapped notification and posts a Notification
    /// the SwiftUI layer can observe to navigate to the right screen.
    ///
    /// Subscribers should listen for `Notification.Name.pushDeepLink` and read
    /// the userInfo dict (keys: "type", plus whatever the trigger attached —
    /// e.g. "clubId", "challengeId", "roundId").
    fileprivate func routeDeepLink(userInfo: [AnyHashable: Any]) {
        var payload: [AnyHashable: Any] = [:]
        if let type = userInfo["type"] as? String { payload["type"] = type }
        for (k, v) in userInfo where k as? String != "aps" {
            payload[k] = v
        }
        NotificationCenter.default.post(
            name: .pushDeepLink,
            object: nil,
            userInfo: payload
        )
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationService: UNUserNotificationCenterDelegate {

    /// Foreground delivery — show the banner instead of swallowing it.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge, .list])
    }

    /// Tap on a notification (foreground or background) — route to the screen.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        Task { @MainActor in
            self.routeDeepLink(userInfo: userInfo)
        }
        completionHandler()
    }
}

// MARK: - MessagingDelegate

#if canImport(FirebaseMessaging)
extension PushNotificationService: MessagingDelegate {
    nonisolated func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        #if DEBUG
        print("📮 [APNsDiag] FCM token received: \(fcmToken?.prefix(20) ?? "nil")…")
        #endif
        guard let fcmToken else { return }
        Task { @MainActor in
            self.persistFCMToken(fcmToken)
        }
    }
}
#endif

// MARK: - NotificationCenter name

extension Notification.Name {
    /// Posted whenever the user taps a push or in-app notification. Subscribers
    /// inspect userInfo["type"] (a `NotificationType` raw value) and any other
    /// IDs attached by the originating trigger to navigate to the right screen.
    static let pushDeepLink = Notification.Name("DGR.pushDeepLink")
}

// MARK: - AppDelegate shim
//
// SwiftUI doesn't expose APNs callbacks directly. We register a small UIKit
// delegate via @UIApplicationDelegateAdaptor in DiscGolfRankingsApp and forward
// the device token + remote-notification taps into the service.

final class DGRAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Task { @MainActor in
            PushNotificationService.shared.setAPNSDeviceToken(deviceToken)
        }
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        #if DEBUG
        let ns = error as NSError
        print("❌ [APNsDiag] APNs registration FAILED: \(error.localizedDescription) " +
              "(domain=\(ns.domain) code=\(ns.code))")
        #endif
    }
}
