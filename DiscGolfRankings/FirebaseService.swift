import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class FirebaseService: ObservableObject {
    static let shared = FirebaseService()
    private let db = Firestore.firestore()

    let daltonClubID = "wK75njjNDMQDmEdkWTHU"
    let adminUID     = "mCu5lZBrUfey3x8BOQnylPGj8Ik2"

    // MARK: - Club

    func fetchClub(id: String) async throws -> Club? {
        let doc = try await db.collection("clubs").document(id).getDocument()
        guard var club = try? doc.data(as: Club.self) else { return nil }
        if club.id == nil { club.id = doc.documentID }
        return club
    }

    // MARK: - Memberships

    func fetchLeaderboard(clubID: String) async throws -> [Membership] {
        let snapshot = try await db.collection("memberships")
            .whereField("clubId", isEqualTo: clubID)
            .whereField("isActive", isEqualTo: true)
            .order(by: "tagNumber")
            .getDocuments()
        // try? per document so one bad doc never empties the whole list
        return snapshot.documents.compactMap { try? $0.data(as: Membership.self) }
    }

    func fetchMembership(userId: String, clubId: String) async throws -> Membership? {
        // No isActive filter in Firestore — avoids extra composite index requirement
        let snapshot = try await db.collection("memberships")
            .whereField("userId", isEqualTo: userId)
            .whereField("clubId", isEqualTo: clubId)
            .limit(to: 1)
            .getDocuments()
        return snapshot.documents.first.flatMap { try? $0.data(as: Membership.self) }
    }

    func joinDaltonClub(userId: String, userFullName: String, userEmail: String = "") async throws {
        try await joinClub(userId: userId, userFullName: userFullName,
                           clubId: daltonClubID, userEmail: userEmail)
    }

    func fetchApprovedClubs() async throws -> [Club] {
        let snapshot = try await db.collection("clubs")
            .whereField("status", isEqualTo: Club.ClubStatus.approved.rawValue)
            .order(by: "name")
            .getDocuments()
        return snapshot.documents.compactMap { doc -> Club? in
            guard var club = try? doc.data(as: Club.self) else { return nil }
            // With a custom init(from:), Firestore's @DocumentID is not auto-populated.
            // Explicitly set the document ID so List/ForEach identity works correctly.
            if club.id == nil { club.id = doc.documentID }
            return club
        }
    }

    // MARK: - Challenges

    func fetchChallenges(clubID: String, userId: String) async throws -> [Challenge] {
        let asChallenger = try await db.collection("challenges")
            .whereField("clubID", isEqualTo: clubID)
            .whereField("challengerUID", isEqualTo: userId)
            .getDocuments()
        let asDefendant = try await db.collection("challenges")
            .whereField("clubID", isEqualTo: clubID)
            .whereField("defendantUID", isEqualTo: userId)
            .getDocuments()

        var all = try asChallenger.documents.compactMap { try $0.data(as: Challenge.self) }
        all += try asDefendant.documents.compactMap { try $0.data(as: Challenge.self) }
        return all.sorted { $0.createdAt > $1.createdAt }
    }

    func fetchActiveChallenges(clubID: String) async throws -> [Challenge] {
        async let pendingSnap = db.collection("challenges")
            .whereField("clubID", isEqualTo: clubID)
            .whereField("status", isEqualTo: Challenge.ChallengeStatus.pending.rawValue)
            .getDocuments()
        async let acceptedSnap = db.collection("challenges")
            .whereField("clubID", isEqualTo: clubID)
            .whereField("status", isEqualTo: Challenge.ChallengeStatus.accepted.rawValue)
            .getDocuments()

        var results = try await pendingSnap.documents.compactMap { try $0.data(as: Challenge.self) }
        results += try await acceptedSnap.documents.compactMap { try $0.data(as: Challenge.self) }
        return results.sorted { $0.createdAt > $1.createdAt }
    }

    func createChallenge(
        clubID: String,
        challengerMembership: Membership,
        defendantMembership: Membership,
        courseName: String?,
        notes: String?
    ) async throws {
        let challenge = Challenge(
            clubID: clubID,
            challengerUID: challengerMembership.userId,
            challengerName: challengerMembership.userFullName,
            challengerTag: challengerMembership.tagNumber,
            defendantUID: defendantMembership.userId,
            defendantName: defendantMembership.userFullName,
            defendantTag: defendantMembership.tagNumber,
            status: .pending,
            createdAt: Date(),
            courseName: courseName,
            notes: notes
        )
        try db.collection("challenges").addDocument(from: challenge)
    }

    func respondToChallenge(_ challengeID: String, accept: Bool) async throws {
        let status: Challenge.ChallengeStatus = accept ? .accepted : .declined
        try await db.collection("challenges").document(challengeID).updateData([
            "status": status.rawValue
        ])
    }

    func resolveChallenge(_ challenge: Challenge, challengerWon: Bool) async throws {
        guard let challengeID = challenge.id else { return }
        let winnerUID = challengerWon ? challenge.challengerUID : challenge.defendantUID

        let batch = db.batch()

        let challengeRef = db.collection("challenges").document(challengeID)
        batch.updateData([
            "status": Challenge.ChallengeStatus.completed.rawValue,
            "winnerUID": winnerUID,
            "resolvedAt": Timestamp(date: Date())
        ], forDocument: challengeRef)

        if challengerWon {
            let challengerSnap = try await db.collection("memberships")
                .whereField("userId", isEqualTo: challenge.challengerUID)
                .whereField("clubId", isEqualTo: challenge.clubID)
                .limit(to: 1)
                .getDocuments()
            let defendantSnap = try await db.collection("memberships")
                .whereField("userId", isEqualTo: challenge.defendantUID)
                .whereField("clubId", isEqualTo: challenge.clubID)
                .limit(to: 1)
                .getDocuments()

            if let cDoc = challengerSnap.documents.first, let dDoc = defendantSnap.documents.first {
                batch.updateData(["tagNumber": challenge.defendantTag], forDocument: cDoc.reference)
                batch.updateData(["tagNumber": challenge.challengerTag], forDocument: dDoc.reference)
            }
        }

        try await batch.commit()
    }

    func cancelChallenge(_ challengeID: String) async throws {
        try await db.collection("challenges").document(challengeID).updateData([
            "status": Challenge.ChallengeStatus.cancelled.rawValue
        ])
    }

    // MARK: - User Memberships (multi-club)

    func fetchUserMemberships(userId: String) async throws -> [Membership] {
        let snapshot = try await db.collection("memberships")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        return snapshot.documents
            .compactMap { try? $0.data(as: Membership.self) }
            .filter { $0.isActive != false }
    }

    // MARK: - Club Applications

    func submitClubApplication(
        clubName: String,
        city: String,
        state: String,
        description: String,
        website: String,
        contactEmail: String,
        applicantUserId: String,
        applicantName: String
    ) async throws {
        let data: [String: Any] = [
            "clubName": clubName,
            "city": city,
            "state": state,
            "description": description,
            "website": website,
            "contactEmail": contactEmail,
            "applicantUserId": applicantUserId,
            "applicantName": applicantName,
            "status": "pending",
            "submittedAt": Timestamp(date: Date())
        ]
        try await db.collection("clubApplications").addDocument(data: data)
    }

    // MARK: - Admin: Club Application Management

    func fetchPendingApplications() async throws -> [ClubApplication] {
        let snapshot = try await db.collection("clubApplications")
            .whereField("status", isEqualTo: "pending")
            .order(by: "submittedAt", descending: true)
            .getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: ClubApplication.self) }
    }

    func approveClubApplication(_ application: ClubApplication) async throws {
        guard let appId = application.id else { return }
        let club = Club(
            name: application.clubName,
            location: "\(application.city), \(application.state)",
            adminUID: application.applicantUserId,
            status: .approved,
            tagFee: 0,
            setupFee: 0,
            memberCount: 0,
            createdAt: Date()
        )
        try db.collection("clubs").addDocument(from: club)
        try await db.collection("clubApplications").document(appId)
            .updateData(["status": "approved"])
    }

    func rejectClubApplication(_ applicationId: String) async throws {
        try await db.collection("clubApplications").document(applicationId)
            .updateData(["status": "rejected"])
    }

    // MARK: - Pending Rounds (Score Verification)

    /// Saves scores as a pending round. Submitter is auto-confirmed.
    /// Other players must confirm before tags actually swap.
    func submitPendingRound(
        clubId: String,
        results: [TagResult],
        scores: [String: Int],
        submittedBy: String,
        submittedByName: String
    ) async throws {
        var tagsBefore:  [String: Int]    = [:]
        var tagsAfter:   [String: Int]    = [:]
        var playerIds:   [String]         = []
        var playerNames: [String: String] = [:]

        for result in results {
            let uid = result.membership.userId
            tagsBefore[uid]  = result.oldTag
            tagsAfter[uid]   = result.newTag
            playerIds.append(uid)
            playerNames[uid] = result.membership.userFullName
        }

        // Submitter auto-confirms their own submission
        let confirmations: [String: Bool] = [submittedBy: true]

        let data: [String: Any] = [
            "clubId":          clubId,
            "submittedBy":     submittedBy,
            "submittedByName": submittedByName,
            "submittedAt":     Timestamp(date: Date()),
            "playerIds":       playerIds,
            "playerNames":     playerNames,
            "scores":          scores,
            "tagsBefore":      tagsBefore,
            "tagsAfter":       tagsAfter,
            "confirmations":   confirmations,
            "status":          PendingRound.PendingRoundStatus.pending.rawValue
        ]

        try await db.collection("pendingRounds").addDocument(data: data)
    }

    /// Fetch all pending rounds the user is part of that still need confirmation.
    func fetchPendingRoundsForUser(userId: String) async throws -> [PendingRound] {
        let snapshot = try await db.collection("pendingRounds")
            .whereField("playerIds", arrayContains: userId)
            .whereField("status", isEqualTo: PendingRound.PendingRoundStatus.pending.rawValue)
            .getDocuments()
        return snapshot.documents
            .compactMap { try? $0.data(as: PendingRound.self) }
            .sorted { $0.submittedAt > $1.submittedAt }
    }

    /// Confirm or dispute a pending round.
    /// If disputed → marks status as disputed immediately (no tag swap).
    /// If confirmed → checks whether all players have confirmed; if so, finalizes and swaps tags.
    func respondToPendingRound(roundId: String, userId: String, confirmed: Bool) async throws {
        let ref = db.collection("pendingRounds").document(roundId)

        guard confirmed else {
            // Dispute — cancel immediately, no tag swap
            try await ref.updateData([
                "confirmations.\(userId)": false,
                "status": PendingRound.PendingRoundStatus.disputed.rawValue
            ])
            return
        }

        // Record this player's confirmation
        try await ref.updateData(["confirmations.\(userId)": true])

        // Re-fetch to see if everyone has now confirmed
        let doc = try await ref.getDocument()
        guard let round = try? doc.data(as: PendingRound.self),
              round.status == .pending          // guard against double-finalize
        else { return }

        if round.isConfirmedByAll {
            try await finalizeRound(round, roundId: roundId)
        }
    }

    /// Atomically swaps tags, archives the round, and marks the pending round confirmed.
    private func finalizeRound(_ round: PendingRound, roundId: String) async throws {
        let batch = db.batch()

        // Update every player's tag number
        for playerId in round.playerIds {
            guard let newTag = round.tagsAfter[playerId] else { continue }
            let snap = try await db.collection("memberships")
                .whereField("userId", isEqualTo: playerId)
                .whereField("clubId", isEqualTo: round.clubId)
                .limit(to: 1)
                .getDocuments()
            if let memberDoc = snap.documents.first {
                batch.updateData(["tagNumber": newTag], forDocument: memberDoc.reference)
            }
        }

        // Archive to the rounds collection for history
        let roundData: [String: Any] = [
            "clubId":      round.clubId,
            "playerIds":   round.playerIds,
            "scores":      round.scores,
            "tagsBefore":  round.tagsBefore,
            "tagsAfter":   round.tagsAfter,
            "playedAt":    Timestamp(date: Date()),
            "confirmedBy": round.submittedBy
        ]
        batch.setData(roundData, forDocument: db.collection("rounds").document())

        // Mark the pending round as fully confirmed
        batch.updateData(
            ["status": PendingRound.PendingRoundStatus.confirmed.rawValue],
            forDocument: db.collection("pendingRounds").document(roundId)
        )

        try await batch.commit()
    }

    // MARK: - Group Rounds

    func saveGroupRound(
        clubId: String,
        results: [TagResult],
        scores: [String: Int],
        confirmedBy: String
    ) async throws {
        let batch = db.batch()

        var tagsBefore: [String: Int] = [:]
        var tagsAfter:  [String: Int] = [:]
        var playerIds:  [String]      = []

        for result in results {
            guard let docID = result.membership.id else { continue }
            let ref = db.collection("memberships").document(docID)
            if result.oldTag != result.newTag {
                batch.updateData(["tagNumber": result.newTag], forDocument: ref)
            }
            tagsBefore[result.membership.userId] = result.oldTag
            tagsAfter[result.membership.userId]  = result.newTag
            playerIds.append(result.membership.userId)
        }

        let roundData: [String: Any] = [
            "clubId":      clubId,
            "playerIds":   playerIds,
            "scores":      scores,
            "tagsBefore":  tagsBefore,
            "tagsAfter":   tagsAfter,
            "playedAt":    Timestamp(date: Date()),
            "confirmedBy": confirmedBy
        ]
        let roundRef = db.collection("rounds").document()
        batch.setData(roundData, forDocument: roundRef)

        try await batch.commit()
    }

    // MARK: - Club Admin

    func fetchClubMembers(clubId: String) async throws -> [Membership] {
        let snap = try await db.collection("memberships")
            .whereField("clubId", isEqualTo: clubId)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: Membership.self) }
            .sorted { $0.tagNumber < $1.tagNumber }
    }

    func removeMember(membershipId: String) async throws {
        try await db.collection("memberships").document(membershipId)
            .updateData(["isActive": false])
    }

    func setMemberAdmin(membershipId: String, clubId: String, userId: String, isAdmin: Bool) async throws {
        let batch = db.batch()
        let memberRef = db.collection("memberships").document(membershipId)
        batch.updateData(["isAdmin": isAdmin], forDocument: memberRef)

        // Keep club.adminUserIds in sync
        let clubRef = db.collection("clubs").document(clubId)
        if isAdmin {
            batch.updateData(["adminUserIds": FieldValue.arrayUnion([userId])], forDocument: clubRef)
        } else {
            batch.updateData(["adminUserIds": FieldValue.arrayRemove([userId])], forDocument: clubRef)
        }
        try await batch.commit()
    }

    func updateClub(clubId: String, name: String, location: String,
                    joinFee: Double, missionStatement: String, website: String,
                    contactEmail: String? = nil,
                    contactPhone: String? = nil) async throws {
        var data: [String: Any] = [
            "name":             name,
            "location":         location,
            "joinFee":          joinFee,
            "missionStatement": missionStatement,
            "website":          website
        ]
        if let contactEmail { data["contactEmail"] = contactEmail }
        if let contactPhone { data["contactPhone"] = contactPhone }
        try await db.collection("clubs").document(clubId).updateData(data)
    }

    // MARK: - Join Requests (paid clubs)

    func submitJoinRequest(userId: String, userFullName: String,
                           userEmail: String, clubId: String) async throws {
        // Prevent duplicate requests
        let existing = try await db.collection("joinRequests")
            .whereField("userId", isEqualTo: userId)
            .whereField("clubId", isEqualTo: clubId)
            .limit(to: 1).getDocuments()
        guard existing.documents.isEmpty else { return }

        let data: [String: Any] = [
            "userId":       userId,
            "userFullName": userFullName,
            "userEmail":    userEmail,
            "clubId":       clubId,
            "status":       JoinRequest.JoinRequestStatus.pending.rawValue,
            "requestedAt":  Timestamp(date: Date())
        ]
        try await db.collection("joinRequests").addDocument(data: data)
    }

    func checkJoinRequest(userId: String, clubId: String) async throws -> JoinRequest? {
        let snap = try await db.collection("joinRequests")
            .whereField("userId", isEqualTo: userId)
            .whereField("clubId", isEqualTo: clubId)
            .limit(to: 1).getDocuments()
        return snap.documents.first.flatMap { try? $0.data(as: JoinRequest.self) }
    }

    func fetchJoinRequests(clubId: String) async throws -> [JoinRequest] {
        let snap = try await db.collection("joinRequests")
            .whereField("clubId", isEqualTo: clubId)
            .whereField("status", isEqualTo: JoinRequest.JoinRequestStatus.pending.rawValue)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: JoinRequest.self) }
            .sorted { $0.requestedAt > $1.requestedAt }
    }

    func approveJoinRequest(_ request: JoinRequest) async throws {
        guard let reqId = request.id else { return }
        let name = request.userFullName

        // Create the membership (reuses joinClub logic)
        try await joinClub(userId: request.userId, userFullName: name,
                           clubId: request.clubId, userEmail: request.userEmail)
        // Mark request approved
        try await db.collection("joinRequests").document(reqId)
            .updateData(["status": JoinRequest.JoinRequestStatus.approved.rawValue])

        // Send welcome notification
        let memberSnap = try await db.collection("memberships")
            .whereField("userId", isEqualTo: request.userId)
            .whereField("clubId", isEqualTo: request.clubId)
            .limit(to: 1).getDocuments()
        if let m = memberSnap.documents.first.flatMap({ try? $0.data(as: Membership.self) }) {
            let clubDoc = try? await db.collection("clubs").document(request.clubId).getDocument()
            let clubName = (try? clubDoc?.data(as: Club.self))?.name ?? "the club"
            try? await sendWelcomeNotification(userId: request.userId,
                                               clubName: clubName, tagNumber: m.tagNumber)
        }
    }

    func denyJoinRequest(requestId: String) async throws {
        try await db.collection("joinRequests").document(requestId)
            .updateData(["status": JoinRequest.JoinRequestStatus.denied.rawValue])
    }

    // MARK: - Notifications

    func fetchNotifications(userId: String) async throws -> [AppNotification] {
        let snap = try await db.collection("notifications")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: AppNotification.self) }
            .sorted { $0.createdAt > $1.createdAt }
    }

    func markAllNotificationsRead(userId: String) async throws {
        let snap = try await db.collection("notifications")
            .whereField("userId", isEqualTo: userId)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()
        let batch = db.batch()
        for doc in snap.documents {
            batch.updateData(["isRead": true], forDocument: doc.reference)
        }
        try await batch.commit()
    }

    func sendWelcomeNotification(userId: String, clubName: String, tagNumber: Int) async throws {
        let data: [String: Any] = [
            "userId":    userId,
            "message":   "Welcome to \(clubName)! You've been assigned tag #\(tagNumber).",
            "isRead":    false,
            "createdAt": Timestamp(date: Date())
        ]
        try await db.collection("notifications").addDocument(data: data)
    }

    func unreadNotificationCount(userId: String) async throws -> Int {
        let snap = try await db.collection("notifications")
            .whereField("userId", isEqualTo: userId)
            .whereField("isRead", isEqualTo: false)
            .getDocuments()
        return snap.documents.count
    }

    // MARK: - Rounds / Stats

    func fetchRecentRounds(clubId: String, limit: Int = 5) async throws -> [RoundRecord] {
        let snap = try await db.collection("rounds")
            .whereField("clubId", isEqualTo: clubId)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: RoundRecord.self) }
            .sorted { $0.playedAt > $1.playedAt }
            .prefix(limit)
            .map { $0 }
    }

    func fetchUserStats(userId: String) async throws -> UserStats {
        let snap = try await db.collection("memberships")
            .whereField("userId", isEqualTo: userId)
            .getDocuments()
        let memberships = snap.documents
            .compactMap { try? $0.data(as: Membership.self) }
            .filter { $0.isActive != false }   // include legacy docs where isActive may be nil

        let count = memberships.count
        let avg: Double? = count == 0
            ? nil
            : Double(memberships.reduce(0) { $0 + $1.tagNumber }) / Double(count)

        return UserStats(clubCount: count, averageRank: avg)
    }

    // MARK: - Events

    /// Creates a new event and notifies every active club member.
    @discardableResult
    func createEvent(_ event: Event) async throws -> String {
        let ref = try db.collection("events").addDocument(from: event)
        let dateStr = event.startDate.formatted(date: .abbreviated, time: .shortened)
        try? await sendNotificationToAllClubMembersInternal(
            clubId: event.clubId,
            message: "📅 New event: \(event.title) — \(dateStr)"
        )
        return ref.documentID
    }

    /// Fetches events for a club, optionally filtered by status.
    func fetchEvents(clubId: String, status: Event.EventStatus? = nil) async throws -> [Event] {
        var query: Query = db.collection("events").whereField("clubId", isEqualTo: clubId)
        if let status {
            query = query.whereField("status", isEqualTo: status.rawValue)
        }
        let snap = try await query.getDocuments()
        return snap.documents
            .compactMap { try? $0.data(as: Event.self) }
            .sorted { $0.startDate < $1.startDate }
    }

    /// Fetches every upcoming event for a club, sorted by date ascending.
    func fetchUpcomingEvents(clubId: String) async throws -> [Event] {
        try await fetchEvents(clubId: clubId, status: .upcoming)
    }

    /// Toggles a user's RSVP on an event.
    func setEventRSVP(eventId: String, userId: String, going: Bool) async throws {
        let ref = db.collection("events").document(eventId)
        try await ref.updateData([
            "rsvps": going
                ? FieldValue.arrayUnion([userId])
                : FieldValue.arrayRemove([userId])
        ])
    }

    /// Cancels an event (marks status=cancelled, sends a notification to all members).
    func cancelEvent(_ event: Event) async throws {
        guard let eid = event.id else { return }
        try await db.collection("events").document(eid).updateData([
            "status": Event.EventStatus.cancelled.rawValue
        ])
        try? await sendNotificationToAllClubMembersInternal(
            clubId: event.clubId,
            message: "❌ Event cancelled: \(event.title)"
        )
    }

    /// Submits final scores for an event, redistributes club rankings, and marks the event completed.
    /// Writes everything atomically in a Firestore batch.
    /// - Returns: the new `[userId: tagNumber]` map so the UI can confirm what changed.
    @discardableResult
    func submitEventResults(
        event: Event,
        members: [Membership],
        roundScores: [[String: Int]],   // [round_idx][userId] = strokes
        demotion: Int = 2
    ) async throws -> [String: Int] {
        guard let eventId = event.id else {
            throw NSError(domain: "Event", code: 0,
                          userInfo: [NSLocalizedDescriptionKey: "Event missing id"])
        }

        // Sum per-round scores into a single playerTotals dict
        var totals: [String: Int] = [:]
        for round in roundScores {
            for (uid, score) in round {
                totals[uid, default: 0] += score
            }
        }

        // Run the ranking engine
        let newTags = RankingEngine.redistribute(
            members: members,
            eventTotals: totals,
            demotion: demotion
        )
        guard !newTags.isEmpty else {
            throw NSError(domain: "Event", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No scores were entered."])
        }

        // Snapshot old tags for the event record
        var oldTags: [String: Int] = [:]
        for m in members { oldTags[m.userId] = m.tagNumber }

        // Batch: update each membership's tagNumber + mark event completed
        let batch = db.batch()
        for m in members {
            guard let mid = m.id, let newTag = newTags[m.userId], newTag != m.tagNumber
            else { continue }
            let ref = db.collection("memberships").document(mid)
            batch.updateData(["tagNumber": newTag], forDocument: ref)
        }

        let eventRef = db.collection("events").document(eventId)
        batch.updateData([
            "status":        Event.EventStatus.completed.rawValue,
            "roundScores":   roundScores,
            "playerTotals":  totals,
            "oldTags":       oldTags,
            "newTags":       newTags,
            "demotion":      demotion,
            "completedAt":   Timestamp(date: Date())
        ], forDocument: eventRef)

        try await batch.commit()

        // Write a `rounds` record so the leaderboard Activity tab sees the tag changes
        try? await writeEventToRounds(event: event, members: members, totals: totals,
                                      oldTags: oldTags, newTags: newTags)

        return newTags
    }

    /// Writes a single `rounds/{id}` doc so the Activity tab picks up the event's tag changes.
    private func writeEventToRounds(event: Event, members: [Membership],
                                    totals: [String: Int],
                                    oldTags: [String: Int],
                                    newTags: [String: Int]) async throws {
        var playerNames: [String: String] = [:]
        for m in members { playerNames[m.userId] = m.userFullName }
        let data: [String: Any] = [
            "clubId":      event.clubId,
            "playerIds":   members.map { $0.userId },
            "playerNames": playerNames,
            "scores":      totals,
            "tagsBefore":  oldTags,
            "tagsAfter":   newTags,
            "playedAt":    Timestamp(date: event.startDate),
            "confirmedBy": "event:\(event.id ?? "")"
        ]
        try await db.collection("rounds").addDocument(data: data)
    }

    // MARK: - Helper: broadcast (used by createEvent / cancelEvent)
    private func sendNotificationToAllClubMembersInternal(clubId: String, message: String) async throws {
        let snap = try await db.collection("memberships")
            .whereField("clubId", isEqualTo: clubId)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        let members = snap.documents.compactMap { try? $0.data(as: Membership.self) }
        guard !members.isEmpty else { return }
        let batch = db.batch()
        for m in members {
            let ref = db.collection("notifications").document()
            batch.setData([
                "userId":    m.userId,
                "message":   message,
                "isRead":    false,
                "createdAt": Timestamp(date: Date())
            ], forDocument: ref)
        }
        try await batch.commit()
    }

    /// Sends an in-app notification to every active member of a club.
    /// Used by club admins to broadcast announcements. Returns the count delivered.
    func sendNotificationToAllClubMembers(clubId: String, message: String) async throws -> Int {
        let snap = try await db.collection("memberships")
            .whereField("clubId", isEqualTo: clubId)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        let members = snap.documents.compactMap { try? $0.data(as: Membership.self) }
        guard !members.isEmpty else { return 0 }

        let batch = db.batch()
        for m in members {
            let ref = db.collection("notifications").document()
            batch.setData([
                "userId":    m.userId,
                "message":   message,
                "isRead":    false,
                "createdAt": Timestamp(date: Date())
            ], forDocument: ref)
        }
        try await batch.commit()
        return members.count
    }

    // Updated joinClub — adds email, isAdmin check, welcome notification
    func joinClub(userId: String, userFullName: String,
                  clubId: String, userEmail: String = "") async throws {
        let existing = try await db.collection("memberships")
            .whereField("userId", isEqualTo: userId)
            .whereField("clubId", isEqualTo: clubId)
            .limit(to: 1).getDocuments()
        guard existing.documents.isEmpty else { return }

        let snap = try await db.collection("memberships")
            .whereField("clubId", isEqualTo: clubId)
            .getDocuments()
        let activeCount = snap.documents
            .compactMap { try? $0.data(as: Membership.self) }
            .filter { $0.isActive != false }
            .count
        let nextTag = activeCount + 1

        // Check if user is the club's designated admin
        let clubDoc = try? await db.collection("clubs").document(clubId).getDocument()
        let club = try? clubDoc?.data(as: Club.self)
        let isAdmin = club?.adminUID == userId || club?.adminUserIds?.contains(userId) == true

        var memberData: [String: Any] = [
            "userId":       userId,
            "clubId":       clubId,
            "tagNumber":    nextTag,
            "userFullName": userFullName,
            "joinedAt":     Timestamp(date: Date()),
            "isActive":     true
        ]
        if !userEmail.isEmpty { memberData["email"] = userEmail }
        if isAdmin             { memberData["isAdmin"] = true    }

        try await db.collection("memberships").addDocument(data: memberData)
        try await db.collection("clubs").document(clubId).updateData([
            "memberCount": FieldValue.increment(Int64(1))
        ])

        // Send welcome notification
        try? await sendWelcomeNotification(userId: userId,
                                           clubName: club?.name ?? "the club",
                                           tagNumber: nextTag)
    }

    // MARK: - Stripe / Payments

    /// Records a successful payment in the `payments` collection and increments club revenue.
    func recordPayment(userId: String, clubId: String, amount: Double,
                       platformFee: Double, stripePaymentIntentId: String) async throws {
        let data: [String: Any] = [
            "userId":                userId,
            "clubId":                clubId,
            "amount":                amount,
            "platformFee":           platformFee,
            "stripePaymentIntentId": stripePaymentIntentId,
            "status":                "succeeded",
            "createdAt":             Timestamp(date: Date())
        ]
        try await db.collection("payments").addDocument(data: data)
        // Increment the club's running revenue total (net of platform fee)
        let clubNet = amount - platformFee
        try? await db.collection("clubs").document(clubId)
            .updateData(["totalRevenue": FieldValue.increment(clubNet)])
    }

    /// Saves the Stripe Connect account ID on the club document and marks paymentsEnabled.
    func updateStripeConnectedAccount(clubId: String, accountId: String) async throws {
        try await db.collection("clubs").document(clubId).updateData([
            "stripeConnectedAccountId": accountId,
            "paymentsEnabled": true
        ])
    }

    /// Flips the paymentsEnabled flag on a club document.
    func setPaymentsEnabled(clubId: String, enabled: Bool) async throws {
        try await db.collection("clubs").document(clubId)
            .updateData(["paymentsEnabled": enabled])
    }

    // MARK: - Super Admin operations

    /// Fetches every club document regardless of status (approved, pending, rejected).
    func fetchAllClubsForSuperAdmin() async throws -> [Club] {
        let snap = try await db.collection("clubs").order(by: "name").getDocuments()
        return snap.documents.compactMap { doc -> Club? in
            guard var club = try? doc.data(as: Club.self) else { return nil }
            if club.id == nil { club.id = doc.documentID }
            return club
        }
    }

    /// Fetches every user in the app. Use sparingly.
    func fetchAllUsers() async throws -> [AppUser] {
        let snap = try await db.collection("users").getDocuments()
        return snap.documents.compactMap { try? $0.data(as: AppUser.self) }
    }

    /// Fetches every pending round across every club. Used by the super-admin force-confirm view.
    func fetchAllPendingRoundsForSuperAdmin() async throws -> [PendingRound] {
        let snap = try await db.collection("pendingRounds")
            .whereField("status", isEqualTo: PendingRound.PendingRoundStatus.pending.rawValue)
            .order(by: "submittedAt", descending: true)
            .getDocuments()
        return snap.documents.compactMap { try? $0.data(as: PendingRound.self) }
    }

    /// Updates only a club's join fee — convenience wrapper used by the super-admin pricing editor.
    func setClubJoinFee(clubId: String, fee: Double) async throws {
        try await db.collection("clubs").document(clubId)
            .updateData(["joinFee": fee])
    }

    /// Force-confirms every player on a pending round (super admin override).
    /// Marks all confirmations true, sets status to confirmed, applies the new tag numbers,
    /// and writes a permanent record into `rounds`.
    func superAdminForceConfirmRound(_ round: PendingRound) async throws {
        guard let roundId = round.id else { return }
        let batch = db.batch()

        // 1. Flip every player to confirmed
        var confirmations: [String: Bool] = round.confirmationsMap
        for pid in round.playerIds { confirmations[pid] = true }

        let pendingRef = db.collection("pendingRounds").document(roundId)
        batch.updateData([
            "confirmations": confirmations,
            "status": PendingRound.PendingRoundStatus.confirmed.rawValue
        ], forDocument: pendingRef)

        // 2. Apply the new tag numbers to every player's membership
        for pid in round.playerIds {
            let newTag = round.tagsAfter[pid] ?? 0
            let memberSnap = try await db.collection("memberships")
                .whereField("userId", isEqualTo: pid)
                .whereField("clubId", isEqualTo: round.clubId)
                .limit(to: 1).getDocuments()
            if let doc = memberSnap.documents.first {
                batch.updateData(["tagNumber": newTag], forDocument: doc.reference)
            }
        }

        // 3. Persist the round into the permanent `rounds` collection
        let roundsRef = db.collection("rounds").document()
        let roundData: [String: Any] = [
            "clubId":       round.clubId,
            "playerIds":    round.playerIds,
            "playerNames":  round.playerNames,
            "scores":       round.scores,
            "tagsBefore":   round.tagsBefore,
            "tagsAfter":    round.tagsAfter,
            "playedAt":     Timestamp(date: round.submittedAt),
            "confirmedBy":  "super_admin_override"
        ]
        batch.setData(roundData, forDocument: roundsRef)

        try await batch.commit()
    }

    // MARK: - Challenges (simplified flow)

    /// Creates a new Challenge document and a notification for the defendant.
    func sendChallenge(_ challenge: Challenge) async throws -> String {
        let ref = try db.collection("challenges").addDocument(from: challenge)
        // Drop a notification on the defendant
        let msg = "🎯 \(challenge.challengerName) challenged you" +
                 (challenge.message?.isEmpty == false ? ": \"\(challenge.message!)\"" : "!")
        _ = try? await db.collection("notifications").addDocument(data: [
            "userId":    challenge.defendantUID,
            "message":   msg,
            "isRead":    false,
            "createdAt": Timestamp(date: Date())
        ])
        return ref.documentID
    }

    /// Marks a challenge as accepted or declined.
    func updateChallengeStatus(challengeId: String, status: Challenge.ChallengeStatus) async throws {
        try await db.collection("challenges").document(challengeId)
            .updateData([
                "status": status.rawValue,
                "resolvedAt": Timestamp(date: Date())
            ])
    }

    /// Fetches every challenge that involves a user — incoming AND outgoing.
    func fetchUserChallenges(userId: String) async throws -> [Challenge] {
        async let incoming = db.collection("challenges")
            .whereField("defendantUID", isEqualTo: userId).getDocuments()
        async let outgoing = db.collection("challenges")
            .whereField("challengerUID", isEqualTo: userId).getDocuments()
        var all = try await incoming.documents.compactMap { try? $0.data(as: Challenge.self) }
        all   += try await outgoing.documents.compactMap { try? $0.data(as: Challenge.self) }
        return all.sorted { $0.createdAt > $1.createdAt }
    }

    /// Returns the count of pending incoming challenges (for the badge on Profile).
    func pendingChallengeCount(userId: String) async throws -> Int {
        let snap = try await db.collection("challenges")
            .whereField("defendantUID", isEqualTo: userId)
            .whereField("status", isEqualTo: Challenge.ChallengeStatus.pending.rawValue)
            .getDocuments()
        return snap.documents.count
    }

    // MARK: - User profile

    /// Updates customizable profile fields on the user document.
    /// Any nil arg is left unchanged (so callers can update one field at a time).
    func updateUserProfile(uid: String,
                           photoURL: String? = nil,
                           bio: String? = nil,
                           instagram: String? = nil,
                           facebook: String? = nil,
                           twitter: String? = nil,
                           tiktok: String? = nil) async throws {
        var data: [String: Any] = [:]
        if let photoURL  { data["photoURL"]  = photoURL  }
        if let bio       { data["bio"]       = bio       }
        if let instagram { data["instagram"] = instagram }
        if let facebook  { data["facebook"]  = facebook  }
        if let twitter   { data["twitter"]   = twitter   }
        if let tiktok    { data["tiktok"]    = tiktok    }
        guard !data.isEmpty else { return }
        try await db.collection("users").document(uid).updateData(data)
    }

    /// Fetches a user document directly (used for looking up a defendant's email when sending challenges).
    func fetchUser(uid: String) async throws -> AppUser? {
        let doc = try await db.collection("users").document(uid).getDocument()
        return try? doc.data(as: AppUser.self)
    }

    /// Permanently deletes a club and every associated membership / join request / pending round.
    /// Use with extreme caution — this is irreversible.
    func superAdminDeleteClub(clubId: String) async throws {
        let batch = db.batch()

        // Delete the club itself
        batch.deleteDocument(db.collection("clubs").document(clubId))

        // Delete all memberships
        let memberSnap = try await db.collection("memberships")
            .whereField("clubId", isEqualTo: clubId).getDocuments()
        for doc in memberSnap.documents { batch.deleteDocument(doc.reference) }

        // Delete all pending join requests
        let reqSnap = try await db.collection("joinRequests")
            .whereField("clubId", isEqualTo: clubId).getDocuments()
        for doc in reqSnap.documents { batch.deleteDocument(doc.reference) }

        // Delete all pending rounds
        let prSnap = try await db.collection("pendingRounds")
            .whereField("clubId", isEqualTo: clubId).getDocuments()
        for doc in prSnap.documents { batch.deleteDocument(doc.reference) }

        try await batch.commit()
    }
}
