// notifications.js — The single chokepoint for APNs push delivery.
//
// EVERY notification doc written to Firestore (no matter which trigger
// created it — iOS-side or backend-side) flows through this function.
// It looks up the recipient's prefs + FCM token, then sends a push via
// FCM, which routes to APNs.

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");
// Use the modular messaging API. In firebase-admin v12 the legacy
// admin.messaging() can take a stale credential path that doesn't attach
// OAuth tokens to outbound HTTP calls in 2nd-gen Cloud Functions. getMessaging()
// from the new modular entry point is the supported path.
const { getMessaging } = require("firebase-admin/messaging");

// MARK: Title / body templates keyed by NotificationType raw value.
//
// Keep in sync with the iOS NotificationType enum in Models.swift.
// `message` from the doc is used as the body fallback when not overridden here.

const TITLES = {
  clubApproved:             "Club Approved 🎉",
  clubApplicationSubmitted: "New Club Application",
  newClubMember:            "New Club Member",
  clubBroadcast:            "Club Announcement",
  subscriptionExpiring:     "Subscription Reminder",
  challengeReceived:        "You've Been Challenged 🥏",
  challengeResponded:       "Challenge Update",
  scoreConfirmationNeeded:  "Confirm Your Scores",
  roundConfirmed:           "Round Finalized ✅",
  eventCreated:             "New Event",
  eventReminder:            "Event Reminder",
  eventCancelled:           "Event Cancelled",
  general:                  "DiscGolfRankings",
};

exports.onNotificationCreated = onDocumentCreated(
  {
    document: "notifications/{notificationId}",
    secrets:  ["ADMIN_SA_KEY"],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) {
      logger.warn("onNotificationCreated fired without a snapshot");
      return;
    }

    // Runtime credential diagnostic — confirms the explicit cert is being used
    // AND that getAccessToken() actually mints a usable OAuth token.
    try {
      const opts = admin.app().options || {};
      let tokenResult = "(skipped)";
      try {
        const t = await opts.credential.getAccessToken();
        tokenResult = {
          has_token:     !!t.access_token,
          token_length:  (t.access_token || "").length,
          token_prefix:  (t.access_token || "").slice(0, 8) + "…",
          expires_in:    t.expires_in,
        };
      } catch (tokenErr) {
        tokenResult = { error: tokenErr.message, code: tokenErr.code };
      }
      logger.info("runtime cred check", {
        admin_sa_env_present: !!process.env.ADMIN_SA_KEY,
        admin_sa_env_length:  (process.env.ADMIN_SA_KEY || "").length,
        admin_apps_count:     admin.apps.length,
        app_project_id:       opts.projectId || null,
        cred_type:            opts.credential
                              ? opts.credential.constructor.name
                              : "(none)",
        token_check:          tokenResult,
      });
    } catch (e) {
      logger.warn("cred diagnostic failed", { err: e.message });
    }

    const data = snap.data() || {};
    const userId  = data.userId;
    const message = data.message || "";
    const type    = data.type || "general";
    const meta    = data.meta || {};

    if (!userId) {
      logger.warn("notification doc missing userId", { notificationId: snap.id });
      return;
    }

    // Load the recipient's user doc to check prefs + FCM token.
    const userSnap = await admin
      .firestore()
      .collection("users")
      .doc(userId)
      .get();

    if (!userSnap.exists) {
      logger.info("recipient user doc missing", { userId });
      return;
    }
    const user = userSnap.data() || {};

    // Master kill switch — nil/true means "push allowed"; only false suppresses.
    if (user.notifyEnabled === false) {
      logger.info("push suppressed by master switch", { userId });
      return;
    }

    // Per-category opt-out — missing key means enabled.
    const prefs = user.notificationPrefs || {};
    if (prefs[type] === false) {
      logger.info("push suppressed by per-category opt-out", { userId, type });
      return;
    }

    const fcmToken = user.fcmToken;
    if (!fcmToken) {
      logger.info("no FCM token on user doc — in-app only", { userId });
      return;
    }

    const title = TITLES[type] || TITLES.general;
    const body  = message;

    // FCM data payload must be all-strings — coerce.
    const dataPayload = { type };
    for (const [k, v] of Object.entries(meta)) {
      if (typeof v === "string") dataPayload[k] = v;
    }

    try {
      // Bypass firebase-admin SDK and call FCM HTTP v1 directly. The SDK
      // refuses to attach its OAuth token to the request (verified via
      // getAccessToken() returning a valid 1024-char ya29.c.c… token, yet
      // FCM responds "missing authentication credential"). Manual fetch
      // with the same token works and gives us a verifiable HTTP path.
      const tok = await admin.app().options.credential.getAccessToken();
      const projectId = admin.app().options.projectId
                     || process.env.GCLOUD_PROJECT
                     || "discgolfrankings";
      const resp = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            "Authorization": `Bearer ${tok.access_token}`,
            "Content-Type":  "application/json",
          },
          body: JSON.stringify({
            message: {
              token: fcmToken,
              notification: { title, body },
              data: dataPayload,
              apns: { payload: { aps: { sound: "default", badge: 1 } } },
            },
          }),
        }
      );
      if (!resp.ok) {
        const errBody = await resp.text();
        throw Object.assign(new Error("FCM HTTP " + resp.status), {
          httpStatus: resp.status,
          httpBody:   errBody,
        });
      }
      logger.info("push sent", { userId, type });
    } catch (err) {
      // Token-not-registered → HTTP 404 with UNREGISTERED in body. Clear it.
      const httpStatus = err.httpStatus;
      const bodyStr    = err.httpBody || "";
      const tokenDead  = httpStatus === 404
                      || /UNREGISTERED|registration-token-not-registered/i.test(bodyStr);
      if (tokenDead) {
        await admin
          .firestore()
          .collection("users")
          .doc(userId)
          .update({ fcmToken: admin.firestore.FieldValue.delete() })
          .catch(() => {});
        logger.warn("cleared stale FCM token", { userId, httpStatus });
      } else {
        logger.error("FCM send failed", {
          userId,
          httpStatus,
          httpBody:  bodyStr.slice(0, 800), // truncate to keep logs readable
          message:   err.message,
          stack:     err.stack && err.stack.split("\n").slice(0, 4).join(" | "),
          projectId: process.env.GCLOUD_PROJECT || process.env.GOOGLE_CLOUD_PROJECT,
        });
      }
    }
  }
);
