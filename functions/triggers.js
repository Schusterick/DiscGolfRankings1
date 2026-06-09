// triggers.js — Cloud Function triggers that don't fit cleanly into
// iOS-side writes:
//   • onAuthUserCreated         → welcome email (Phase D)
//   • onClubApplicationCreated  → fan-out to super admins
//   • dailySubscriptionCheck    → 14/7/1 day expiry warnings
//
// Each function that needs to push uses the existing /notifications fan-out
// (it writes a notification doc, which fires onNotificationCreated, which
// hits FCM). This keeps the push delivery path single-chokepoint.

const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const { onSchedule }        = require("firebase-functions/v2/scheduler");
const { logger }            = require("firebase-functions");
const admin                 = require("firebase-admin");

const { sendWelcomeEmail, sendClubDuesEmail, RESEND_API_KEY } = require("./email");
const { buildClubDuesCheckoutUrl, STRIPE_SECRET_KEY } = require("./stripe");

// MARK: Super-admin email list
// Mirror of AuthService.superAdminEmails in iOS. Keep in sync until we move
// roles to a Firestore collection.
const SUPER_ADMIN_EMAILS = ["will@prodigydisc.com"];

// ──────────────────────────────────────────────────────────────────────────────
// onAuthUserCreated — sends the welcome email on signup.
// ──────────────────────────────────────────────────────────────────────────────

// Auth v2 trigger lives in firebase-functions/v2/identity. For wider Node
// compatibility we use the v1 functions namespace which still exposes onCreate.
const functionsV1 = require("firebase-functions/v1");

exports.onAuthUserCreated = functionsV1
  .runWith({ secrets: [RESEND_API_KEY] })
  .auth.user()
  .onCreate(async (user) => {
    if (!user.email) {
      logger.info("auth.onCreate fired without email — skipping", { uid: user.uid });
      return;
    }
    // Safe diagnostic — logs structure of the secret, not its value.
    const k = process.env.RESEND_API_KEY || "";
    logger.info("resend secret check", {
      uid: user.uid,
      has_env:           !!process.env.RESEND_API_KEY,
      length:            k.length,
      starts_with_re:    k.startsWith("re_"),
      has_whitespace:    /\s/.test(k),
      first_two_chars:   k.slice(0, 2),
      last_two_chars:    k.slice(-2),
    });
    try {
      await sendWelcomeEmail({
        to: user.email,
        firstName: extractFirstName(user.displayName, user.email)
      });
      logger.info("welcome email sent", { uid: user.uid, to: user.email });
    } catch (err) {
      logger.error("welcome email failed", { uid: user.uid, err: err.message });
    }
  });

function extractFirstName(displayName, email) {
  if (displayName && displayName.trim()) {
    return displayName.trim().split(/\s+/)[0];
  }
  if (email) return email.split("@")[0];
  return "there";
}

// ──────────────────────────────────────────────────────────────────────────────
// onClubApplicationCreated — fans the new application out to every super admin.
// ──────────────────────────────────────────────────────────────────────────────

exports.onClubApplicationCreated = onDocumentCreated(
  {
    document: "clubApplications/{appId}",
    secrets:  ["ADMIN_SA_KEY"],
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const app = snap.data() || {};

    // Resolve super-admin uids by email.
    const superAdminUids = new Set();
    for (const email of SUPER_ADMIN_EMAILS) {
      try {
        const userRecord = await admin.auth().getUserByEmail(email);
        superAdminUids.add(userRecord.uid);
      } catch (err) {
        logger.info("super admin not yet signed up", { email });
      }
    }

    if (superAdminUids.size === 0) {
      logger.info("no super admins to notify");
      return;
    }

    const msg = `🆕 New club application: "${app.clubName}" (${app.city}, ${app.state}) by ${app.applicantName || "—"}.`;
    const writes = [];
    for (const uid of superAdminUids) {
      writes.push(admin.firestore().collection("notifications").add({
        userId:    uid,
        message:   msg,
        isRead:    false,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        type:      "clubApplicationSubmitted",
        meta:      { applicationId: snap.id }
      }));
    }
    await Promise.all(writes);
    logger.info("super-admin fan-out complete", {
      applicationId: snap.id,
      count: superAdminUids.size
    });
  }
);

// ──────────────────────────────────────────────────────────────────────────────
// dailySubscriptionCheck — scheduled 09:00 ET, warns admins at 14 / 7 / 1 days.
// ──────────────────────────────────────────────────────────────────────────────

exports.dailySubscriptionCheck = onSchedule(
  {
    schedule: "0 9 * * *",
    timeZone: "America/New_York",
    secrets:  [RESEND_API_KEY, STRIPE_SECRET_KEY]
  },
  async () => {
    const WARN_DAYS = [14, 7, 1];
    const now       = new Date();
    const dayMs     = 24 * 60 * 60 * 1000;

    const snap = await admin.firestore()
      .collection("clubs")
      .where("subscriptionStatus", "in", ["active", "trial"])
      .get();

    let sent = 0;
    for (const doc of snap.docs) {
      const c = doc.data();
      const expiresAt = c.subscriptionExpiresAt && c.subscriptionExpiresAt.toDate
        ? c.subscriptionExpiresAt.toDate()
        : null;
      if (!expiresAt) continue;

      const daysLeft = Math.round((expiresAt.getTime() - now.getTime()) / dayMs);
      if (!WARN_DAYS.includes(daysLeft)) continue;

      const adminUIDs = new Set();
      if (c.adminUID) adminUIDs.add(c.adminUID);
      (c.adminUserIds || []).forEach(uid => adminUIDs.add(uid));

      const status = c.subscriptionStatus === "trial" ? "Free trial" : "Club dues";
      const noun   = daysLeft === 1 ? "day" : "days";

      // One Checkout URL per club, reused for all of its admins.
      let checkoutUrl = null;
      try {
        checkoutUrl = await buildClubDuesCheckoutUrl(doc.id, c.name);
      } catch (err) {
        logger.warn("could not build dues checkout url", { clubId: doc.id, error: err.message });
      }

      for (const uid of adminUIDs) {
        // In-app notification (fires the push fan-out).
        await admin.firestore().collection("notifications").add({
          userId:    uid,
          message:   `⏰ ${status} for "${c.name}" ends in ${daysLeft} ${noun}.`,
          isRead:    false,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
          type:      "subscriptionExpiring",
          meta:      { clubId: doc.id, daysLeft: String(daysLeft) }
        });
        sent++;

        // Email the admin a pay link (best-effort; never blocks the sweep).
        if (checkoutUrl) {
          try {
            const user = await admin.auth().getUser(uid);
            if (user.email) {
              await sendClubDuesEmail({
                to:          user.email,
                clubName:    c.name,
                daysLeft,
                statusLabel: status,
                checkoutUrl,
              });
            }
          } catch (err) {
            logger.warn("dues email failed", { uid, clubId: doc.id, error: err.message });
          }
        }
      }
    }
    logger.info("dailySubscriptionCheck complete", { sent });
  }
);
