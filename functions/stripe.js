// stripe.js — Stripe integration for DiscGolfRankings.
//
// Two flows live here:
//   1. CLUB DUES ($50/yr, club → platform) — sold on the WEB via a Stripe
//      Checkout session (NOT in-app, to stay clear of Apple's IAP rules).
//      `createClubDuesCheckout` mints a hosted Checkout URL; `stripeWebhook`
//      marks the club active once Stripe confirms `checkout.session.completed`.
//   2. MEMBER FEES (members → club, 0% platform cut) — added in Phase 2
//      (Stripe Connect). Stubs noted below.
//
// Secrets required before deploy:
//   firebase functions:secrets:set STRIPE_SECRET_KEY       (sk_live_… / sk_test_…)
//   firebase functions:secrets:set STRIPE_WEBHOOK_SECRET   (whsec_… from the webhook endpoint)
//
// The webhook is the ONLY thing trusted to flip a club to paid. The client
// never reports its own payment success.

const { onRequest, onCall, HttpsError } = require("firebase-functions/v2/https");
const { defineSecret } = require("firebase-functions/params");
const { logger } = require("firebase-functions");
const admin = require("firebase-admin");

const STRIPE_SECRET_KEY     = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");

// $ amount of annual club dues, in cents. Mirror of Config.clubSubscriptionAnnualFee.
const CLUB_DUES_CENTS = 5000;
const YEAR_MS = 365 * 24 * 60 * 60 * 1000;

// Where Checkout sends the browser back to (static pages on the marketing site).
const SUCCESS_URL = "https://discgolfrankings.com/subscribe-success.html";
const CANCEL_URL  = "https://discgolfrankings.com/subscribe-cancel.html";

function stripeClient() {
  // Lazy-require so deploy succeeds even before the secret is set.
  return require("stripe")(STRIPE_SECRET_KEY.value());
}

// ──────────────────────────────────────────────────────────────────────────
// createClubDuesCheckout — returns a hosted Stripe Checkout URL for a club's
// annual dues. Callable from the web (or the iOS app, which opens it in the
// external browser). One-time $50 charge, no auto-renew.
//
// Exposed as an onCall so the web/app gets a clean { url } back. We also keep
// a helper `buildClubDuesCheckoutUrl` for server-side use (the dues email).
// ──────────────────────────────────────────────────────────────────────────
async function buildClubDuesCheckoutUrl(clubId, clubName) {
  const stripe = stripeClient();
  const session = await stripe.checkout.sessions.create({
    mode: "payment",
    line_items: [{
      quantity: 1,
      price_data: {
        currency: "usd",
        unit_amount: CLUB_DUES_CENTS,
        product_data: {
          name: "DiscGolfRankings — Annual Club Dues",
          description: clubName ? `Keeps "${clubName}" active for 1 year` : "Keeps your club active for 1 year",
        },
      },
    }],
    metadata: { clubId, type: "club_dues" },
    success_url: SUCCESS_URL,
    cancel_url:  CANCEL_URL,
  });
  return session.url;
}

exports.createClubDuesCheckout = onCall(
  { secrets: [STRIPE_SECRET_KEY] },
  async (request) => {
    const clubId = request.data && request.data.clubId;
    if (!clubId) throw new HttpsError("invalid-argument", "clubId is required");

    const snap = await admin.firestore().collection("clubs").doc(clubId).get();
    if (!snap.exists) throw new HttpsError("not-found", "Club not found");

    try {
      const url = await buildClubDuesCheckoutUrl(clubId, snap.data().name);
      return { url };
    } catch (err) {
      logger.error("createClubDuesCheckout failed", { clubId, error: err.message });
      throw new HttpsError("internal", "Could not start checkout");
    }
  }
);

// ──────────────────────────────────────────────────────────────────────────
// stripeWebhook — the single source of truth for payment confirmation.
// Verifies the Stripe signature, then on a completed club-dues checkout flips
// the club to active with a fresh +1-year expiry.
// ──────────────────────────────────────────────────────────────────────────
exports.stripeWebhook = onRequest(
  { secrets: [STRIPE_SECRET_KEY, STRIPE_WEBHOOK_SECRET] },
  async (req, res) => {
    const stripe = stripeClient();
    let event;
    try {
      event = stripe.webhooks.constructEvent(
        req.rawBody,                       // raw body required for signature check
        req.headers["stripe-signature"],
        STRIPE_WEBHOOK_SECRET.value()
      );
    } catch (err) {
      logger.error("stripe webhook signature verification failed", { error: err.message });
      return res.status(400).send(`Webhook Error: ${err.message}`);
    }

    if (event.type === "checkout.session.completed") {
      const session = event.data.object;
      const meta = session.metadata || {};
      if (meta.type === "club_dues" && meta.clubId) {
        try {
          await activateClubDues(meta.clubId);
          logger.info("club dues activated via webhook", { clubId: meta.clubId });
        } catch (err) {
          logger.error("failed to activate club dues", { clubId: meta.clubId, error: err.message });
          // 500 so Stripe retries.
          return res.status(500).send("activation failed");
        }
      }
    }

    // Always 200 the events we don't act on, so Stripe stops retrying them.
    return res.status(200).send("ok");
  }
);

// Mirrors FirebaseService.activateClubSubscription: status → active, expiry →
// max(now, current expiry) + 1 year (so paying early during the trial doesn't
// burn the remaining free time).
async function activateClubDues(clubId) {
  const ref  = admin.firestore().collection("clubs").doc(clubId);
  const snap = await ref.get();
  const data = snap.exists ? snap.data() : {};
  const current = data.subscriptionExpiresAt && data.subscriptionExpiresAt.toDate
    ? data.subscriptionExpiresAt.toDate().getTime()
    : 0;
  const base = Math.max(Date.now(), current);
  await ref.set({
    subscriptionStatus:    "active",
    subscriptionExpiresAt: admin.firestore.Timestamp.fromMillis(base + YEAR_MS),
  }, { merge: true });
}

module.exports = {
  createClubDuesCheckout: exports.createClubDuesCheckout,
  stripeWebhook:          exports.stripeWebhook,
  buildClubDuesCheckoutUrl,
  STRIPE_SECRET_KEY,
  STRIPE_WEBHOOK_SECRET,
};
