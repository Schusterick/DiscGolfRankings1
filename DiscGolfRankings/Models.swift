import Foundation
import FirebaseFirestore

// MARK: - User

struct AppUser: Identifiable, Codable {
    @DocumentID var id: String?
    var email: String
    var displayName: String
    var createdAt: Date

    // Customization (all optional — older user docs predate these)
    var photoURL:        String?
    var bio:             String?
    var instagram:       String?
    var facebook:        String?
    var twitter:         String?
    var tiktok:          String?
    var favoriteCourse:  String?    // e.g. "Maple Hill"
    var yearsPlaying:    Int?       // 0..50

    enum CodingKeys: String, CodingKey {
        case id, email, displayName, createdAt
        case photoURL, bio, instagram, facebook, twitter, tiktok
        case favoriteCourse, yearsPlaying
    }
}

// MARK: - Club

struct Club: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var name: String
    var location: String
    var adminUID: String
    var status: ClubStatus
    var tagFee: Double
    var setupFee: Double
    var memberCount: Int
    var createdAt: Date
    // New fields
    var missionStatement: String?
    var adminUserIds: [String]?
    var joinFee: Double?
    var website: String?
    // Public-profile contact details
    var contactEmail: String?
    var contactPhone: String?
    // Public-profile visual customization
    var logoURL:      String?
    var foundedYear:  Int?
    // Stripe / payments
    var stripeConnectedAccountId: String?
    var paymentsEnabled: Bool?
    var totalRevenue: Double?
    // Hybrid subscription model (free trial → $50/year)
    var subscriptionStatus:     String?    // "trial" | "active" | "expired" | "cancelled"
    var subscriptionStartedAt:  Date?
    var subscriptionExpiresAt:  Date?

    enum ClubStatus: String, Codable, CaseIterable, Hashable {
        case pending  = "pending"
        case approved = "approved"
        case rejected = "rejected"
    }

    // Includes legacy keys so old Firestore docs (city/state/isApproved) decode correctly
    enum CodingKeys: String, CodingKey {
        case name, location, adminUID, status
        case tagFee, setupFee, memberCount, createdAt
        case missionStatement, adminUserIds, joinFee, website
        case contactEmail, contactPhone
        case logoURL, foundedYear
        case stripeConnectedAccountId, paymentsEnabled, totalRevenue
        case subscriptionStatus, subscriptionStartedAt, subscriptionExpiresAt
        case city, state, isApproved   // legacy field names
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        name = (try? c.decode(String.self, forKey: .name)) ?? "Unknown Club"

        // Support both "location" string and separate "city"+"state" fields
        if let loc = try? c.decode(String.self, forKey: .location), !loc.isEmpty {
            location = loc
        } else {
            let city  = (try? c.decode(String.self, forKey: .city))  ?? ""
            let state = (try? c.decode(String.self, forKey: .state)) ?? ""
            location  = [city, state].filter { !$0.isEmpty }.joined(separator: ", ")
        }

        adminUID = (try? c.decode(String.self, forKey: .adminUID)) ?? ""

        // Support both "status" string and legacy "isApproved" bool
        if let s = try? c.decode(ClubStatus.self, forKey: .status) {
            status = s
        } else {
            let approved = (try? c.decode(Bool.self, forKey: .isApproved)) ?? false
            status = approved ? .approved : .pending
        }

        tagFee      = (try? c.decode(Double.self, forKey: .tagFee))      ?? 0
        setupFee    = (try? c.decode(Double.self, forKey: .setupFee))    ?? 0
        memberCount = (try? c.decode(Int.self,    forKey: .memberCount)) ?? 0
        createdAt   = (try? c.decode(Date.self,   forKey: .createdAt))   ?? Date()

        missionStatement        = try? c.decode(String.self,   forKey: .missionStatement)
        adminUserIds            = try? c.decode([String].self, forKey: .adminUserIds)
        joinFee                 = try? c.decode(Double.self,   forKey: .joinFee)
        website                 = try? c.decode(String.self,   forKey: .website)
        contactEmail            = try? c.decode(String.self,   forKey: .contactEmail)
        contactPhone            = try? c.decode(String.self,   forKey: .contactPhone)
        logoURL                 = try? c.decode(String.self,   forKey: .logoURL)
        foundedYear             = try? c.decode(Int.self,      forKey: .foundedYear)
        stripeConnectedAccountId = try? c.decode(String.self,  forKey: .stripeConnectedAccountId)
        subscriptionStatus       = try? c.decode(String.self,  forKey: .subscriptionStatus)
        subscriptionStartedAt    = try? c.decode(Date.self,    forKey: .subscriptionStartedAt)
        subscriptionExpiresAt    = try? c.decode(Date.self,    forKey: .subscriptionExpiresAt)
        paymentsEnabled         = try? c.decode(Bool.self,     forKey: .paymentsEnabled)
        totalRevenue            = try? c.decode(Double.self,   forKey: .totalRevenue)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name,          forKey: .name)
        try c.encode(location,      forKey: .location)
        try c.encode(adminUID,      forKey: .adminUID)
        try c.encode(status,        forKey: .status)
        try c.encode(tagFee,        forKey: .tagFee)
        try c.encode(setupFee,      forKey: .setupFee)
        try c.encode(memberCount,   forKey: .memberCount)
        try c.encode(createdAt,     forKey: .createdAt)
        try c.encodeIfPresent(missionStatement,         forKey: .missionStatement)
        try c.encodeIfPresent(adminUserIds,             forKey: .adminUserIds)
        try c.encodeIfPresent(joinFee,                  forKey: .joinFee)
        try c.encodeIfPresent(website,                  forKey: .website)
        try c.encodeIfPresent(contactEmail,             forKey: .contactEmail)
        try c.encodeIfPresent(contactPhone,             forKey: .contactPhone)
        try c.encodeIfPresent(logoURL,                  forKey: .logoURL)
        try c.encodeIfPresent(foundedYear,              forKey: .foundedYear)
        try c.encodeIfPresent(stripeConnectedAccountId, forKey: .stripeConnectedAccountId)
        try c.encodeIfPresent(paymentsEnabled,          forKey: .paymentsEnabled)
        try c.encodeIfPresent(totalRevenue,             forKey: .totalRevenue)
        try c.encodeIfPresent(subscriptionStatus,       forKey: .subscriptionStatus)
        try c.encodeIfPresent(subscriptionStartedAt,    forKey: .subscriptionStartedAt)
        try c.encodeIfPresent(subscriptionExpiresAt,    forKey: .subscriptionExpiresAt)
    }

    init(name: String, location: String, adminUID: String,
         status: ClubStatus, tagFee: Double, setupFee: Double,
         memberCount: Int, createdAt: Date,
         missionStatement: String? = nil,
         adminUserIds: [String]? = nil,
         joinFee: Double? = nil,
         website: String? = nil,
         stripeConnectedAccountId: String? = nil,
         paymentsEnabled: Bool? = nil,
         totalRevenue: Double? = nil,
         subscriptionStatus: String? = nil,
         subscriptionStartedAt: Date? = nil,
         subscriptionExpiresAt: Date? = nil) {
        self.name = name; self.location = location; self.adminUID = adminUID
        self.status = status; self.tagFee = tagFee; self.setupFee = setupFee
        self.memberCount = memberCount; self.createdAt = createdAt
        self.missionStatement = missionStatement
        self.adminUserIds = adminUserIds
        self.joinFee = joinFee
        self.website = website
        self.stripeConnectedAccountId = stripeConnectedAccountId
        self.paymentsEnabled = paymentsEnabled
        self.totalRevenue = totalRevenue
        self.subscriptionStatus = subscriptionStatus
        self.subscriptionStartedAt = subscriptionStartedAt
        self.subscriptionExpiresAt = subscriptionExpiresAt
    }

    // MARK: - Subscription helper

    /// Computes the live subscription state for this club based on the dates stored.
    /// Falls back to `.trial` (with a 6-month grace period from `createdAt`) for
    /// legacy docs that don't have subscription fields yet — so existing clubs are
    /// grandfathered into the trial automatically.
    enum SubscriptionState {
        case trial(daysRemaining: Int)
        case active(daysUntilRenewal: Int)
        case expiringSoon(daysUntilExpire: Int)
        case expired
        case cancelled

        var isUsable: Bool {
            switch self {
            case .trial, .active, .expiringSoon: return true
            case .expired, .cancelled:           return false
            }
        }
        var label: String {
            switch self {
            case .trial(let d):         return d == 1 ? "1 day left in free trial" : "\(d) days left in free trial"
            case .active(let d):        return "Renews in \(d) day\(d == 1 ? "" : "s")"
            case .expiringSoon(let d):  return "Expires in \(d) day\(d == 1 ? "" : "s")"
            case .expired:              return "Subscription expired"
            case .cancelled:            return "Subscription cancelled"
            }
        }
    }

    /// Live subscription state computed from stored dates + Config constants.
    var subscriptionState: SubscriptionState {
        let now = Date()
        // Explicitly-cancelled clubs
        if subscriptionStatus == "cancelled" { return .cancelled }

        // Determine the effective expiration date
        let effectiveExpiry: Date = subscriptionExpiresAt
            ?? Calendar.current.date(byAdding: .day, value: Config.clubTrialDurationDays,
                                     to: subscriptionStartedAt ?? createdAt)
            ?? createdAt

        let daysLeft = Calendar.current.dateComponents([.day], from: now,
                                                       to: effectiveExpiry).day ?? 0

        if daysLeft < 0 { return .expired }

        // If never explicitly marked "active", treat as trial
        if subscriptionStatus != "active" {
            return .trial(daysRemaining: daysLeft)
        }
        if daysLeft <= Config.renewalWarningWindowDays {
            return .expiringSoon(daysUntilExpire: daysLeft)
        }
        return .active(daysUntilRenewal: daysLeft)
    }

    /// True while the trial is active — used to skip the platform fee on member transactions.
    var isInFreeTrial: Bool {
        if case .trial = subscriptionState { return true }
        return false
    }

    /// Platform fee actually applied to a member-fee transaction.
    /// Zero during the free trial — clubs keep 100% of their members' payments for 6 months.
    var effectivePlatformFeeRate: Double {
        isInFreeTrial ? 0.0 : Config.stripePlatformFee
    }
}

// MARK: - Membership

struct Membership: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var userId: String
    var clubId: String
    var tagNumber: Int
    var userFullName: String
    var joinedAt: Date
    var isActive: Bool?
    var isAdmin: Bool?    // club-level admin flag
    var email: String?    // stored at join time
}

// MARK: - Challenge

struct Challenge: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var clubID: String
    var clubName: String?           // denormalized for display in notifications/email
    var challengerUID: String
    var challengerName: String
    var challengerTag: Int
    var challengerEmail: String?    // captured at send time for the email-coordinate flow
    var defendantUID: String
    var defendantName: String
    var defendantTag: Int
    var defendantEmail: String?
    var status: ChallengeStatus
    var createdAt: Date
    var resolvedAt: Date?
    var winnerUID: String?
    var courseName: String?
    var notes: String?
    // New fields for the simplified "challenge → email" flow
    var message:          String?   // short note from challenger
    var proposedLocation: String?   // e.g. "Hidden Hills DGC"
    var proposedDate:     Date?     // optional date suggestion

    enum ChallengeStatus: String, Codable, CaseIterable, Hashable {
        case pending   = "pending"
        case accepted  = "accepted"
        case completed = "completed"
        case declined  = "declined"
        case cancelled = "cancelled"
    }

    var isActive: Bool { status == .pending || status == .accepted }
}

// MARK: - TagResult (Group Round)

struct TagResult: Identifiable {
    var id: String { membership.userId }
    let membership: Membership
    let oldTag: Int
    let newTag: Int
    let score: Int
}

// MARK: - ClubApplication

struct ClubApplication: Identifiable, Codable {
    @DocumentID var id: String?
    var clubName: String
    var city: String
    var state: String
    var description: String
    var website: String
    var contactEmail: String
    var applicantUserId: String
    var applicantName: String
    var status: String
    var submittedAt: Date
}

// MARK: - ClubWithMembership

struct ClubWithMembership: Identifiable {
    var id: String { membership.id ?? club.id ?? UUID().uuidString }
    let club: Club
    let membership: Membership
}

// MARK: - ClubJoinRequest (legacy model, kept for compatibility)

struct ClubJoinRequest: Identifiable, Codable {
    @DocumentID var id: String?
    var userID: String
    var displayName: String
    var clubID: String
    var status: RequestStatus
    var requestedAt: Date

    enum RequestStatus: String, Codable {
        case pending  = "pending"
        case approved = "approved"
        case rejected = "rejected"
    }
}

// MARK: - JoinRequest (paid-club join flow)

struct JoinRequest: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var userFullName: String
    var userEmail: String
    var clubId: String
    var status: JoinRequestStatus
    var requestedAt: Date

    enum JoinRequestStatus: String, Codable {
        case pending  = "pending"
        case approved = "approved"
        case denied   = "denied"
    }
}

// MARK: - AppNotification

struct AppNotification: Identifiable, Codable {
    @DocumentID var id: String?
    var userId: String
    var message: String
    var isRead: Bool
    var createdAt: Date
}

// MARK: - RoundRecord

struct RoundRecord: Identifiable, Codable {
    @DocumentID var id: String?
    var clubId: String
    var playerIds: [String]
    var playerNames: [String: String]?
    var scores: [String: Int]
    var tagsBefore: [String: Int]
    var tagsAfter: [String: Int]
    var playedAt: Date
    var confirmedBy: String
    var courseNotes: String?
}

// MARK: - PendingRound

struct PendingRound: Identifiable, Codable {
    @DocumentID var id: String?
    var clubId: String
    var submittedBy: String
    var submittedByName: String
    var submittedAt: Date
    var playerIds: [String]
    var playerNames: [String: String]
    var scores: [String: Int]
    var tagsBefore: [String: Int]
    var tagsAfter: [String: Int]
    var confirmations: [String: Bool]?
    var status: PendingRoundStatus

    enum PendingRoundStatus: String, Codable {
        case pending   = "pending"
        case confirmed = "confirmed"
        case disputed  = "disputed"
    }

    var confirmationsMap: [String: Bool] { confirmations ?? [:] }

    var isConfirmedByAll: Bool {
        playerIds.allSatisfy { confirmationsMap[$0] == true }
    }

    func awaitingCount() -> Int {
        playerIds.filter { confirmationsMap[$0] == nil }.count
    }

    func needsResponse(from userId: String) -> Bool {
        confirmationsMap[userId] == nil
    }
}

// MARK: - UserStats

struct UserStats {
    var clubCount:   Int        // number of active club memberships
    var averageRank: Double?    // average tag number across clubs (lower is better)
}

// MARK: - Payment
// Stored in the `payments` Firestore collection.
// Created after a successful Stripe charge for a paid club membership.

struct Payment: Identifiable, Codable {
    @DocumentID var id: String?
    var userId:                 String
    var clubId:                 String
    var amount:                 Double   // full amount paid by member
    var platformFee:            Double   // 10% retained by DiscGolfRankings
    var stripePaymentIntentId:  String   // Stripe PI id for reconciliation
    var status:                 String   // "succeeded" | "refunded" | "failed"
    var createdAt:              Date
}

// MARK: - Event
// A league / tournament hosted by a club. Members RSVP; admin submits scores at the end
// and the rankings are redistributed (see RankingEngine).

struct Event: Identifiable, Codable {
    @DocumentID var id: String?
    var clubId:         String
    var title:          String
    var description:    String?
    var location:       String?     // course / venue
    var startDate:      Date
    var numberOfRounds: Int         // 1..5
    var status:         EventStatus
    var rsvps:          [String]?   // array of userIds who clicked "I'm Going"
    var demotion:       Int?        // non-attendee tag drop (default 2)
    // Filled in once scores are submitted:
    var roundScores:    [[String: Int]]?  // per-round, [round_idx][userId] = strokes
    var playerTotals:   [String: Int]?    // total event score per userId
    var oldTags:        [String: Int]?    // snapshot of every member's tag *before* redistribution
    var newTags:        [String: Int]?    // snapshot of every member's tag *after* redistribution
    var createdBy:      String
    var createdAt:      Date
    var completedAt:    Date?

    enum EventStatus: String, Codable, CaseIterable {
        case upcoming   = "upcoming"
        case completed  = "completed"
        case cancelled  = "cancelled"
    }

    var goingCount: Int { rsvps?.count ?? 0 }
    var isUpcoming: Bool { status == .upcoming }
}
