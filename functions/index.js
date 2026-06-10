// DiscGolfRankings — Cloud Functions entry point.
//
// All exports listed below are deployed when you run:
//   firebase deploy --only functions
//
// Secrets required before deploy:
//   firebase functions:secrets:set RESEND_API_KEY    (Phase D — welcome email)
//
// APNs key must be uploaded in Firebase Console → Project Settings →
// Cloud Messaging → Apple app config → APNs Authentication Key (.p8).

const admin = require("firebase-admin");

// Credential init:
//   1. If ADMIN_SA_KEY env var is set (via Cloud Functions secret), use it
//      explicitly. Bypasses ADC quirks in 2nd-gen Functions where FCM auth
//      silently fails. (Name avoids the reserved FIREBASE_ / EXT_ / X_GOOGLE_
//      prefixes that Firebase secret manager rejects.)
//   2. Otherwise, plain init — auto-discover ADC from the runtime.
if (process.env.ADMIN_SA_KEY) {
  try {
    const sa = JSON.parse(process.env.ADMIN_SA_KEY);
    admin.initializeApp({
      credential: admin.credential.cert(sa),
      projectId:  sa.project_id,
    });
    console.log("admin init [explicit]", {
      sa_client_email: sa.client_email,
      sa_project_id:   sa.project_id,
      sa_key_length:   process.env.ADMIN_SA_KEY.length,
    });
  } catch (err) {
    console.error("admin init failed [explicit]", err.message);
    admin.initializeApp();
  }
} else {
  admin.initializeApp();
  console.log("admin init [ADC fallback] — no ADMIN_SA_KEY env var present");
}

// Push fan-out — every notification doc written to Firestore turns into APNs.
exports.onNotificationCreated = require("./notifications").onNotificationCreated;

// Welcome email on Firebase Auth user creation.
exports.onAuthUserCreated = require("./triggers").onAuthUserCreated;

// Super-admin fanout when a new club application is submitted.
exports.onClubApplicationCreated = require("./triggers").onClubApplicationCreated;

// Daily 09:00 ET sweep — 14 / 7 / 1 day subscription expiry warnings.
exports.dailySubscriptionCheck = require("./triggers").dailySubscriptionCheck;

// Daily 10:00 ET sweep — admin education drip (days 0/3/7/14/45) + recurring
// "submit feedback" ask (day 30, then ~every 90 days).
exports.dailyAdminEducation = require("./triggers").dailyAdminEducation;

// Stripe — Club Dues checkout (web) + webhook (single source of truth for
// marking a club paid). Member-fee (Connect) functions land here in Phase 2.
exports.createClubDuesCheckout = require("./stripe").createClubDuesCheckout;
exports.stripeWebhook          = require("./stripe").stripeWebhook;
