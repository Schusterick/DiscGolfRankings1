# Cloud Functions Setup — Build 6

Everything in this folder ships push notifications, the welcome email, and
the daily subscription warning sweep. None of it goes live until you run
the steps below.

## 1. Install + log in

You only do this once per machine.

```sh
# Install Firebase CLI globally (skip if already installed)
npm install -g firebase-tools

# Sign in
firebase login

# Tell the CLI which project this folder is for
cd "/Users/Schusterick/Desktop/Claude Folder/DiscGolfRankings"
firebase use discgolfrankings
```

## 2. APNs key (for push)

One-time, manual, ~5 minutes:

1. Go to https://developer.apple.com/account/resources/authkeys/list
2. Click the **+** to create a new key
3. Name it `DiscGolfRankings APNs`
4. Check the **Apple Push Notifications service (APNs)** capability
5. Click **Continue → Register**
6. **Download** the `.p8` file (you can only download it once — store it safely)
7. Note down the **Key ID** (visible right after creation, e.g. `ABC123XYZ4`)
8. Note down your **Team ID** (`TC7RHXK5LK` for your personal team)

Then upload to Firebase:

1. Go to https://console.firebase.google.com/project/discgolfrankings/settings/cloudmessaging
2. Under "Apple app configuration" → **APNs Authentication Key** → click **Upload**
3. Pick the `.p8` file, paste the Key ID + Team ID, click **Upload**

Push notifications now work as soon as testers install Build 6 and tap "Allow".

## 3. Resend (for welcome email)

One-time, ~15 minutes (most of it waiting for DNS).

1. Sign up at https://resend.com (free tier = 3,000 emails/month, fine for now)
2. **Domains** tab → **Add domain** → `discgolfrankings.com`
3. Resend shows ~4 DNS records (SPF, DKIM, etc.) — add them at your GoDaddy
   DNS dashboard. Click **Verify** when done (Resend re-checks for ~10 min)
4. Once verified, go to **API Keys** → **Create API Key** → name it `production`
5. Copy the key — it starts with `re_`

Store the key as a Cloud Functions secret:

```sh
cd "/Users/Schusterick/Desktop/Claude Folder/DiscGolfRankings"
firebase functions:secrets:set RESEND_API_KEY
# Paste the re_... key when prompted
```

## 4. Install Node dependencies

```sh
cd "/Users/Schusterick/Desktop/Claude Folder/DiscGolfRankings/functions"
npm install
```

## 5. Deploy

From the repo root (not `functions/`):

```sh
cd "/Users/Schusterick/Desktop/Claude Folder/DiscGolfRankings"
firebase deploy --only functions
```

First deploy takes ~3 minutes. You'll see four functions registered:

- `onNotificationCreated` — Firestore trigger, push fan-out
- `onAuthUserCreated` — Auth trigger, welcome email
- `onClubApplicationCreated` — Firestore trigger, super-admin fanout
- `dailySubscriptionCheck` — scheduled 09:00 ET

## 6. Smoke test

After deploy:

```sh
firebase functions:log --only onNotificationCreated --lines 20
```

Then on your iPhone:

1. Update to Build 6 via TestFlight
2. iOS prompts for notification permission → Allow
3. Have a friend (or a second test account) send you a challenge
4. Within ~2 seconds you should get a banner: "🥏 You've Been Challenged"

If nothing arrives, the function log shows why (no FCM token, opt-out, etc.).

## Updating the super-admin list

If you add a second super admin later (e.g. a co-founder), update **both**:

- iOS: `AuthService.superAdminEmails` in `AuthService.swift:49`
- Cloud Function: `SUPER_ADMIN_EMAILS` in `functions/triggers.js:23`

(Or migrate to a Firestore `roles` collection. Not worth it for one admin.)
