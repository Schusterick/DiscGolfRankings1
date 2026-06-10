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

              <h2 style="margin:24px 0 8px;font-size:18px;color:#E94560;">It's the digital bag tag</h2>
              <p style="margin:0 0 16px;font-size:14px;line-height:1.6;">
                A physical bag tag is just a number — you can't see the
                standings, who holds #1, or how your tag is moving. We turn it
                into a <strong>live ranking system</strong>. Get your tag, swap
                it after every round, and watch your club leaderboard and
                <strong>World Ranking</strong> update in real time. No
                spreadsheets, no Discord chaos.
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
    `DiscGolfRankings is the digital bag tag. A physical tag is just a number —`,
    `here it's a live ranking system. Get a tag, swap it after every round, and`,
    `watch your club leaderboard and World Ranking update in real time.`,
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

/// Sends the club-dues reminder email with a Stripe Checkout link.
/// Called from triggers.js dailySubscriptionCheck at 14/7/1 days out.
async function sendClubDuesEmail({ to, clubName, daysLeft, statusLabel, checkoutUrl }) {
  const { Resend } = require("resend");
  const apiKey = RESEND_API_KEY.value();
  if (!apiKey) throw new Error("RESEND_API_KEY secret not configured");
  const resend = new Resend(apiKey);

  const noun = daysLeft === 1 ? "day" : "days";
  const result = await resend.emails.send({
    from:    FROM,
    replyTo: REPLY_TO,
    to,
    subject: `${statusLabel} for ${clubName} ends in ${daysLeft} ${noun} 🥏`,
    html:    clubDuesHtml({ clubName, daysLeft: `${daysLeft} ${noun}`, statusLabel, checkoutUrl }),
    text:    clubDuesText({ clubName, daysLeft: `${daysLeft} ${noun}`, statusLabel, checkoutUrl })
  });
  if (result.error) throw new Error(result.error.message || "Resend error");
  return result;
}

function clubDuesHtml({ clubName, daysLeft, statusLabel, checkoutUrl }) {
  return /* html */ `
<!doctype html>
<html lang="en"><head><meta charset="utf-8" /><meta name="viewport" content="width=device-width" /></head>
<body style="margin:0;padding:0;background:#0E1525;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;color:#F2F3F7;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0E1525;padding:32px 16px;">
    <tr><td align="center">
      <table width="560" cellpadding="0" cellspacing="0" border="0" style="background:#1A2238;border-radius:16px;padding:32px;">
        <tr><td>
          <h1 style="margin:0 0 8px;font-size:24px;font-weight:900;">Keep ${escapeHtml(clubName)} active 🥏</h1>
          <p style="margin:0 0 20px;font-size:15px;color:#9CA3B0;">
            Your ${escapeHtml(statusLabel.toLowerCase())} ends in <strong style="color:#F5A623;">${escapeHtml(daysLeft)}</strong>.
            Pay your annual club dues to keep your rankings, members, and bag tags live — no interruption.
          </p>
          <table cellpadding="0" cellspacing="0" border="0" style="margin:8px 0 20px;"><tr><td style="border-radius:12px;background:#E94560;">
            <a href="${checkoutUrl}" style="display:inline-block;padding:14px 28px;font-size:16px;font-weight:700;color:#fff;text-decoration:none;">
              Pay Club Dues — $50/year
            </a>
          </td></tr></table>
          <p style="margin:0 0 16px;font-size:13px;color:#9CA3B0;">
            One flat $50 a year for the whole club. We take <strong>0%</strong> of what your members pay you — every dollar of member fees is yours.
          </p>
          <p style="margin:24px 0 0;font-size:12px;color:#6E7587;border-top:1px solid #2A3247;padding-top:16px;">
            Questions? Reply to this email or write to
            <a href="mailto:discgolfrankings@gmail.com" style="color:#F5A623;">discgolfrankings@gmail.com</a>.<br/>
            — The DiscGolfRankings Team
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

function clubDuesText({ clubName, daysLeft, statusLabel, checkoutUrl }) {
  return [
    `Keep ${clubName} active`,
    ``,
    `Your ${statusLabel.toLowerCase()} ends in ${daysLeft}. Pay your annual club dues`,
    `to keep your rankings, members, and bag tags live.`,
    ``,
    `Pay Club Dues — $50/year:`,
    checkoutUrl,
    ``,
    `One flat $50 a year for the whole club. We take 0% of member fees.`,
    ``,
    `Questions? Reply here or write to discgolfrankings@gmail.com.`,
    `— The DiscGolfRankings Team`
  ].join("\n");
}

// ──────────────────────────────────────────────────────────────────────────
// Admin education drip — sent to club admins after approval (day 0 via the
// onClubApproved trigger; days 3/7/14/45 via dailyAdminEducation sweep).
// Short by design: 2–3 tips + zero fluff.
// ──────────────────────────────────────────────────────────────────────────

const EDUCATION_STEPS = {
  0: {
    subject: (club) => `${club} is live on DiscGolfRankings 🥏`,
    title:   "Your club is live!",
    intro:   "You're approved — and you're holding tag #1. Three quick things to set up while the excitement's hot:",
    tips: [
      ["Dress up your club profile", "Add your logo, mission, and schedule (your club page → Edit). This is what new members see first."],
      ["Assign starting tags", "Admin Dashboard → Manage Tags. Hand out numbers to your current crew — takes two minutes."],
      ["Share your join link", "Admin Dashboard → Share Join Link. Post it in your Facebook group or text thread; new members join in seconds."],
    ],
    outro: "Your first 60 days are completely free. Reply to this email anytime — a real person reads it.",
  },
  3: {
    subject: (club) => `Get your crew into ${club}`,
    title:   "Get your crew in",
    intro:   "A club's only as fun as the leaderboard is full. Fastest ways to fill yours:",
    tips: [
      ["Post the join link where your club already talks", "Facebook group, GroupMe, text thread — one tap and they're in."],
      ["Approve join requests as they come", "You'll get a push when someone asks to join. Approve from your Admin Dashboard."],
      ["Bring it to league night", "Have everyone download the app on the spot — each new member gets the next tag automatically."],
    ],
    outro: "Every member you add shows up on the live leaderboard instantly.",
  },
  7: {
    subject: () => "Run your first tag round 🏆",
    title:   "Run your first tag round",
    intro:   "This is the moment the app earns its keep. Here's the flow:",
    tips: [
      ["Start a Group Round", "From your club page, enter everyone's scores in one place after the round."],
      ["Players confirm with one tap", "Each player gets a push to sign off on the scores. No disputes, no he-said-she-said."],
      ["Tags move automatically", "The instant everyone confirms, tags redistribute and the leaderboard updates. No spreadsheets. Ever."],
    ],
    outro: "Watch your members start checking the leaderboard on their own — that's when it clicks.",
  },
  14: {
    subject: (club) => `Keep ${club} competing all season`,
    title:   "Keep them hooked",
    intro:   "The clubs that thrive use these three between league nights:",
    tips: [
      ["Challenges", "Members can challenge anyone in the club — the loser's tag is on the line. Great for keeping mid-pack players engaged."],
      ["Events with signup links", "Post an event, share the signup link, and let the app send the reminders."],
      ["Message All Members", "One tap reaches your whole club as a push notification — weather calls, announcements, trash talk."],
    ],
    outro: "Engaged members renew their club dues. It compounds.",
  },
  45: {
    subject: (club) => `How's ${club} running?`,
    title:   "How's the club running?",
    intro:   "You're about six weeks in. Quick pulse-check on what's available to you:",
    tips: [
      ["Using it all?", "Tags, group rounds, challenges, events, broadcasts, your public club page — if any of those are unfamiliar, reply and we'll point you right at it."],
      ["Heads up: your free trial ends in about 2 weeks", "We'll email you a secure payment link for your annual club dues — $50/year flat for the whole club. Your members never pay us anything."],
      ["Tell us what's missing", "Seriously — reply to this email. Feature ideas from club admins drive what we build next."],
    ],
    outro: "Thanks for running your club with us. 🥏",
  },
};

/// Sends one step of the admin education drip.
async function sendAdminEducationEmail({ to, clubName, step }) {
  const t = EDUCATION_STEPS[step];
  if (!t) throw new Error(`unknown education step: ${step}`);
  const { Resend } = require("resend");
  const apiKey = RESEND_API_KEY.value();
  if (!apiKey) throw new Error("RESEND_API_KEY secret not configured");
  const resend = new Resend(apiKey);

  const result = await resend.emails.send({
    from:    FROM,
    replyTo: REPLY_TO,
    to,
    subject: t.subject(clubName),
    html:    adminShellHtml(t),
    text:    adminShellText(t),
  });
  if (result.error) throw new Error(result.error.message || "Resend error");
  return result;
}

/// Sends the recurring "help us improve" feedback ask.
async function sendFeedbackEmail({ to, clubName }) {
  const { Resend } = require("resend");
  const apiKey = RESEND_API_KEY.value();
  if (!apiKey) throw new Error("RESEND_API_KEY secret not configured");
  const resend = new Resend(apiKey);

  const t = {
    title: "One question for you",
    intro: `What's one thing DiscGolfRankings could do better for ${clubName}?`,
    tips: [
      ["Just hit reply", "Your answer lands directly in the founder's inbox — not a ticket system, not a survey form."],
      ["Nothing is too small", "A confusing button, a missing feature, something another app does better — all of it helps."],
    ],
    outro: "This app is built by one disc golfer and shaped by club admins like you. Thanks for being early. 🥏",
  };

  const result = await resend.emails.send({
    from:    FROM,
    replyTo: REPLY_TO,
    to,
    subject: "What should we build next? (just hit reply)",
    html:    adminShellHtml(t),
    text:    adminShellText(t),
  });
  if (result.error) throw new Error(result.error.message || "Resend error");
  return result;
}

// Shared dark-theme shell matching the welcome/dues emails.
function adminShellHtml(t) {
  const tipsHtml = t.tips.map(([h, b]) => `
              <h2 style="margin:20px 0 6px;font-size:16px;color:#E94560;">${escapeHtml(h)}</h2>
              <p style="margin:0;font-size:14px;line-height:1.6;color:#F2F3F7;">${escapeHtml(b)}</p>`).join("\n");
  return /* html */ `
<!doctype html>
<html lang="en"><head><meta charset="utf-8" /><meta name="viewport" content="width=device-width" /></head>
<body style="margin:0;padding:0;background:#0E1525;font-family:-apple-system,BlinkMacSystemFont,Segoe UI,Roboto,sans-serif;color:#F2F3F7;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0" style="background:#0E1525;padding:32px 16px;">
    <tr><td align="center">
      <table width="560" cellpadding="0" cellspacing="0" border="0" style="background:#1A2238;border-radius:16px;padding:32px;">
        <tr><td>
          <h1 style="margin:0 0 8px;font-size:24px;font-weight:900;">${escapeHtml(t.title)}</h1>
          <p style="margin:0 0 8px;font-size:15px;color:#9CA3B0;">${escapeHtml(t.intro)}</p>
          ${tipsHtml}
          <p style="margin:24px 0 0;font-size:13px;color:#9CA3B0;">${escapeHtml(t.outro)}</p>
          <p style="margin:24px 0 0;font-size:12px;color:#6E7587;border-top:1px solid #2A3247;padding-top:16px;">
            Own Your Rank. — The DiscGolfRankings Team<br/>
            Questions? Just reply, or write to
            <a href="mailto:discgolfrankings@gmail.com" style="color:#F5A623;">discgolfrankings@gmail.com</a>.
          </p>
        </td></tr>
      </table>
    </td></tr>
  </table>
</body></html>`;
}

function adminShellText(t) {
  return [
    t.title.toUpperCase(), "", t.intro, "",
    ...t.tips.flatMap(([h, b]) => [`• ${h}`, `  ${b}`, ""]),
    t.outro, "", "— The DiscGolfRankings Team",
  ].join("\n");
}

module.exports = {
  sendWelcomeEmail,
  sendClubDuesEmail,
  sendAdminEducationEmail,
  sendFeedbackEmail,
  RESEND_API_KEY
};
