// email.js — Transactional email sender (Resend).
//
// Setup once before first deploy:
//   firebase functions:secrets:set RESEND_API_KEY
//   (paste the API key from your Resend dashboard)
//
// Domain setup (one-time):
//   • Sign up at resend.com
//   • Add discgolfrankings.com as a sending domain
//   • Add the SPF / DKIM DNS records Resend prompts you for
//   • Wait for verification (~10 minutes)

const { defineSecret } = require("firebase-functions/params");
const { logger }       = require("firebase-functions");

const RESEND_API_KEY = defineSecret("RESEND_API_KEY");

const FROM = "DiscGolfRankings <welcome@discgolfrankings.com>";
const REPLY_TO = "discgolfrankings@gmail.com";

/// Sends the welcome email. Called from triggers.js onAuthUserCreated.
/// Throws on failure so the caller can log.
async function sendWelcomeEmail({ to, firstName }) {
  // Lazy-require so the function can deploy even before the secret is set
  // (deploy fails fast at runtime with a clear error rather than at build).
  const { Resend } = require("resend");
  const apiKey = RESEND_API_KEY.value();
  if (!apiKey) throw new Error("RESEND_API_KEY secret not configured");

  const resend = new Resend(apiKey);

  const result = await resend.emails.send({
    from:    FROM,
    replyTo: REPLY_TO,
    to,
    subject: "Welcome to DiscGolfRankings 🥏",
    html:    welcomeHtml(firstName),
    text:    welcomeText(firstName)
  });

  if (result.error) throw new Error(result.error.message || "Resend error");
  return result;
}

// MARK: HTML template
function welcomeHtml(firstName) {
  return /* html */ `
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width" />
  <title>Welcome to DiscGolfRankings</title>
</head>
<body style="margin:0;padding:0;background:#0E1525;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;color:#F2F3F7;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0E1525;padding:32px 16px;">
    <tr>
      <td align="center">
        <table width="560" cellpadding="0" cellspacing="0" border="0" style="background:#1A2238;border-radius:16px;padding:32px;">
          <tr>
            <td>
              <h1 style="margin:0 0 8px;font-size:28px;font-weight:900;color:#F2F3F7;">
                Welcome, ${escapeHtml(firstName)} 🥏
              </h1>
              <p style="margin:0 0 24px;font-size:15px;color:#9CA3B0;">
                You're in. Here's everything you need to start owning your rank.
              </p>

              <h2 style="margin:24px 0 8px;font-size:18px;color:#E94560;">What is DiscGolfRankings?</h2>
              <p style="margin:0 0 16px;font-size:14px;line-height:1.6;">
                It's the first iOS app built specifically for disc-golf
                <strong>bag-tag clubs</strong>. Members get a tag number, swap
                tags after every round, host leagues + tournaments, and watch
                their rank live on the leaderboard — no spreadsheets, no
                Discord chaos.
              </p>

              <h2 style="margin:24px 0 8px;font-size:18px;color:#E94560;">Find your local club</h2>
              <p style="margin:0 0 16px;font-size:14px;line-height:1.6;">
                Open the app → tap <strong>Home</strong> → search clubs by
                name, city, or state. Tap <strong>Join</strong> on a club
                near you. If it's a paid club, pay the join fee — every
                dollar goes to the club, we take 0%.
              </p>

              <h2 style="margin:24px 0 8px;font-size:18px;color:#E94560;">Start your own club</h2>
              <p style="margin:0 0 8px;font-size:14px;line-height:1.6;">
                Don't see your local club? Tap <strong>Profile → Request
                a Club</strong>. We review within 2 business days.
              </p>
              <ul style="margin:0 0 16px 20px;padding:0;font-size:14px;line-height:1.7;">
                <li><strong>Free for the first 60 days</strong> — no credit card</li>
                <li>Just <strong>$50 / year</strong> after that — flat fee, no platform cut</li>
                <li><strong>0% on member transactions</strong> — tag fees + dues flow direct to your club's Stripe</li>
              </ul>

              <h2 style="margin:24px 0 8px;font-size:18px;color:#E94560;">Your global rank</h2>
              <p style="margin:0 0 16px;font-size:14px;line-height:1.6;">
                Every player gets a World Ranking the second they sign up,
                based on signup order. Tap the globe icon in the app to
                see where you stack up.
              </p>

              <h2 style="margin:24px 0 8px;font-size:18px;color:#E94560;">Need help?</h2>
              <p style="margin:0 0 24px;font-size:14px;line-height:1.6;">
                Reply to this email or write to
                <a href="mailto:discgolfrankings@gmail.com" style="color:#F5A623;">discgolfrankings@gmail.com</a>.
              </p>

              <p style="margin:32px 0 0;font-size:12px;color:#6E7587;border-top:1px solid #2A3247;padding-top:16px;">
                Own Your Rank. — The DiscGolfRankings Team
              </p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`;
}

// MARK: Plain text fallback
function welcomeText(firstName) {
  return [
    `Welcome, ${firstName}!`,
    ``,
    `DiscGolfRankings is the first iOS app built for disc-golf bag-tag clubs.`,
    `Get a tag, play rounds, swap tags, watch your rank.`,
    ``,
    `FIND YOUR CLUB`,
    `Open the app → Home tab → search clubs by name, city, or state.`,
    ``,
    `START YOUR OWN CLUB`,
    `Profile → Request a Club.`,
    `• Free for the first 60 days`,
    `• $50/year after that — flat fee`,
    `• 0% on member transactions (tag fees + dues go direct to your club)`,
    ``,
    `YOUR WORLD RANK`,
    `Every player gets a global rank on signup. Tap the globe icon in the app.`,
    ``,
    `NEED HELP?`,
    `Reply to this email or write to discgolfrankings@gmail.com.`,
    ``,
    `— The DiscGolfRankings Team`
  ].join("\n");
}

function escapeHtml(s) {
  return String(s || "").replace(/[&<>"']/g, (c) => ({
    "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;"
  })[c]);
}

module.exports = { sendWelcomeEmail, RESEND_API_KEY };
