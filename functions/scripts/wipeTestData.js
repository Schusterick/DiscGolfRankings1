#!/usr/bin/env node
/* eslint-disable no-console */
//
// wipeTestData.js — nuke every test user / club / membership / etc. from
// Firestore and Firebase Auth EXCEPT the protected admin email(s) below.
//
// Usage:
//   1. Firebase Console → Project Settings → Service Accounts → "Generate
//      new private key" → save the JSON somewhere (e.g. ~/Downloads).
//   2. Run:
//      node functions/scripts/wipeTestData.js ~/Downloads/discgolfrankings-firebase-adminsdk-xxxx.json
//   3. Read the dry-run report carefully.
//   4. Type YES to actually nuke. Anything else aborts.
//   5. DELETE the service-account JSON when you're done. Never commit it.
//

const fs       = require("fs");
const path     = require("path");
const readline = require("readline");
const admin    = require("firebase-admin");

// ─── CONFIG ───────────────────────────────────────────────────────────────
const KEEP_EMAILS = new Set([
  "will@prodigydisc.com",
]);

// Every Firestore root collection to scan.
//   keyField === "__docId__"  → preserve doc if its ID is in KEEP_UIDS (only /users)
//   keyField === null         → wipe ALL docs unconditionally
//
// Scope: truly fresh. Only the preserved user's profile doc survives.
// All clubs, memberships, events, etc. — even those owned by the protected
// user — are nuked so the post-wipe state is exactly: one auth login, one
// users/{uid} doc, no clubs, no anything.
const COLLECTIONS = [
  { name: "users",            keyField: "__docId__" },   // ← only /users preserves anything
  { name: "memberships",      keyField: null },
  { name: "challenges",       keyField: null },
  { name: "notifications",    keyField: null },
  { name: "joinRequests",     keyField: null },
  { name: "clubApplications", keyField: null },
  { name: "payments",         keyField: null },
  { name: "pendingRounds",    keyField: null },
  { name: "rounds",           keyField: null },
  { name: "events",           keyField: null },
  { name: "clubs",            keyField: null },
];

// Counter doc to reset (worldRank assignment)
const META_COUNTER_DOC = "meta/worldRankCounter";
// ──────────────────────────────────────────────────────────────────────────

const keyPath = process.argv[2];
if (!keyPath) {
  console.error("Usage: node wipeTestData.js <path/to/service-account.json>");
  process.exit(1);
}
const absKey = path.resolve(keyPath);
if (!fs.existsSync(absKey)) {
  console.error(`Service account key not found at ${absKey}`);
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(require(absKey)),
});
const db = admin.firestore();
const auth = admin.auth();

(async () => {
  console.log("\n==============================================");
  console.log("DiscGolfRankings — Test Data Wipe");
  console.log("==============================================\n");
  console.log("Protected emails:");
  for (const e of KEEP_EMAILS) console.log(`  • ${e}`);
  console.log("");

  // 1. Resolve protected UIDs from Firebase Auth.
  const keepUids = new Set();
  for (const email of KEEP_EMAILS) {
    try {
      const user = await auth.getUserByEmail(email);
      keepUids.add(user.uid);
      console.log(`✔ Resolved ${email} → uid ${user.uid}`);
    } catch (err) {
      console.warn(`⚠ Could not resolve ${email}: ${err.message}`);
    }
  }
  if (keepUids.size === 0) {
    console.warn("\n⚠ No protected UIDs resolved. Aborting to avoid nuking everything.");
    process.exit(2);
  }

  // 2. Plan deletions per collection.
  const plan = {};
  for (const c of COLLECTIONS) {
    const snap = await db.collection(c.name).get();
    const toDelete = [];
    const toKeep = [];

    for (const doc of snap.docs) {
      const data = doc.data();
      let belongsToKeeper = false;

      if (c.keyField === "__docId__") {
        belongsToKeeper = keepUids.has(doc.id);
      } else if (c.keyField) {
        belongsToKeeper = keepUids.has(data[c.keyField]);
      } else if (c.keyFields) {
        belongsToKeeper = c.keyFields.some((f) => keepUids.has(data[f]));
      }

      if (belongsToKeeper) toKeep.push(doc.id);
      else                 toDelete.push({ id: doc.id, summary: shortSummary(c.name, data) });
    }

    plan[c.name] = { toDelete, toKeep };
  }

  // 3. Plan Auth deletions.
  const authToDelete = [];
  let pageToken;
  do {
    const page = await auth.listUsers(1000, pageToken);
    for (const u of page.users) {
      if (!keepUids.has(u.uid)) {
        authToDelete.push({ uid: u.uid, email: u.email || "(no email)" });
      }
    }
    pageToken = page.pageToken;
  } while (pageToken);

  // 4. Dry-run report.
  console.log("\n─── DRY RUN ───────────────────────────────\n");
  let totalDocs = 0;
  for (const c of COLLECTIONS) {
    const { toDelete, toKeep } = plan[c.name];
    totalDocs += toDelete.length;
    console.log(`/${c.name}: delete ${toDelete.length}, keep ${toKeep.length}`);
    for (const item of toDelete.slice(0, 5)) {
      console.log(`    DEL ${item.id}  ${item.summary}`);
    }
    if (toDelete.length > 5) {
      console.log(`    … and ${toDelete.length - 5} more`);
    }
  }
  console.log(`\nFirebase Auth users to delete: ${authToDelete.length}`);
  for (const u of authToDelete.slice(0, 5)) console.log(`    DEL ${u.uid}  ${u.email}`);
  if (authToDelete.length > 5) console.log(`    … and ${authToDelete.length - 5} more`);
  console.log(`\nTotal docs to delete: ${totalDocs}`);
  console.log(`Total Auth users to delete: ${authToDelete.length}`);
  console.log(`\nProtected users will be left intact + worldRankCounter reset to ${keepUids.size}.`);

  // 5. Confirm.
  const answer = await prompt("\nType  YES  to proceed (anything else aborts): ");
  if (answer.trim() !== "YES") {
    console.log("Aborted. Nothing was deleted.");
    process.exit(0);
  }

  // 6. Execute — Firestore.
  console.log("\n─── DELETING ──────────────────────────────");
  for (const c of COLLECTIONS) {
    const { toDelete } = plan[c.name];
    if (toDelete.length === 0) continue;
    // Batched deletes, 500 max per batch.
    for (let i = 0; i < toDelete.length; i += 500) {
      const slice = toDelete.slice(i, i + 500);
      const batch = db.batch();
      for (const item of slice) {
        batch.delete(db.collection(c.name).doc(item.id));
      }
      await batch.commit();
    }
    console.log(`✔ /${c.name}: deleted ${toDelete.length}`);
  }

  // 7. Execute — Auth.
  if (authToDelete.length > 0) {
    const uids = authToDelete.map((u) => u.uid);
    for (let i = 0; i < uids.length; i += 1000) {
      const slice = uids.slice(i, i + 1000);
      const result = await auth.deleteUsers(slice);
      console.log(`✔ Auth: deleted ${result.successCount}, failed ${result.failureCount}`);
    }
  }

  // 8. Reset worldRank counter + protected user's worldRank.
  await db.doc(META_COUNTER_DOC).set({ count: keepUids.size }, { merge: true });
  console.log(`✔ meta/worldRankCounter → ${keepUids.size}`);

  let rank = 1;
  for (const uid of keepUids) {
    await db.collection("users").doc(uid).set({ worldRank: rank }, { merge: true });
    console.log(`✔ users/${uid}.worldRank → ${rank}`);
    rank++;
  }

  console.log("\n✅ Done. Clean slate ready for Build 6 testers.");
  process.exit(0);
})().catch((err) => {
  console.error("\n💥 Wipe failed:", err);
  process.exit(1);
});

// ── helpers ───────────────────────────────────────────────────────────────

function shortSummary(coll, data) {
  switch (coll) {
    case "users":            return `${data.email || "?"} (${data.displayName || "?"})`;
    case "clubs":            return `"${data.name}" — ${data.location}`;
    case "memberships":      return `${data.userFullName || "?"} @ ${data.clubId}`;
    case "challenges":       return `${data.challengerName} → ${data.defendantName}`;
    case "events":           return `"${data.title}" in club ${data.clubId}`;
    case "notifications":    return `${data.type || "general"} → ${data.userId}`;
    case "clubApplications": return `"${data.clubName}" by ${data.applicantName}`;
    case "joinRequests":     return `${data.userFullName} → ${data.clubId}`;
    case "payments":         return `$${data.amount} (${data.status})`;
    default:                 return "";
  }
}

function prompt(q) {
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  return new Promise((res) => rl.question(q, (a) => { rl.close(); res(a); }));
}
