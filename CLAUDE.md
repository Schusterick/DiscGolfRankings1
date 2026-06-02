# DiscGolfRankings

iOS app for disc golf club management and tag-based player rankings.

## Architecture

- **Platform:** iOS 17.0+, SwiftUI, MVVM
- **Backend:** Firebase (Firestore, Auth, Cloud Storage)
- **Payments:** Stripe Connect (club subscriptions + member payments)
- **Auth:** Firebase Auth with Apple, Google, and Facebook OAuth

## Key Files

| File | Purpose |
|------|---------|
| `AppEntry.swift` | App entry point, tab navigation, root state |
| `Models.swift` | All data models (AppUser, Club, Membership, Challenge, Event, etc.) |
| `FirebaseService.swift` | Singleton for all Firestore reads/writes — use this for any data operations |
| `AuthService.swift` | Auth state, sign-in flows, super admin detection |
| `RankingEngine.swift` | Pure functions for tag redistribution logic — no Firebase calls here |
| `Theme.swift` | Design system (colors, fonts, view modifiers) |
| `Config.swift` | App-level constants (Stripe keys, subscription pricing) |

## Core Concepts

**Tag-based rankings:** Each club member holds a numbered tag (1 = best). After an event, `RankingEngine.redistribute()` renumbers tags based on finish order. Attendees keep their relative positions; non-attendees receive a default demotion (+2 positions).

**Pending rounds:** Scores are submitted as `PendingRound`, reviewed by an admin, then committed as `RoundRecord` with tag redistribution applied atomically.

**Club subscriptions:** Clubs pay $50/year after a 60-day free trial. Stripe Connect is used so clubs can also collect member payments directly.

## Design System

Dark theme throughout. Use existing modifiers from `Theme.swift` — don't introduce custom colors inline.

- Accent: `Color.appAccent` (#E94560)
- Background: `Color.appBackground` (#1A1A2E)
- Card: `Color.cardBackground` (#16213E)
- Success: `Color.successGreen` (#4CAF50)

## Conventions

- All Firestore operations go through `FirebaseService.shared` — don't create new Firestore references elsewhere
- Use `@MainActor` on ViewModels; `FirebaseService` and `AuthService` are already `@MainActor`
- Batch writes for any operation that touches multiple documents (e.g., tag redistribution)
- Super admin access is checked in `AuthService` — don't duplicate that logic in views

## Running / Building

Open `DiscGolfRankings.xcodeproj` in Xcode 15+. Requires:
- A `GoogleService-Info.plist` with valid Firebase credentials
- A physical device or simulator running iOS 17+

No command-line build scripts exist; use Xcode directly.
