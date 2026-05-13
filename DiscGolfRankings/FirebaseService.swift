import Foundation
import FirebaseFirestore
import FirebaseAuth

@MainActor
class FirebaseService: ObservableObject {
    static let shared = FirebaseService()
    private let db = Firestore.firestore()

    let daltonClubID = "wK75njjNDMQDmEdkWTHU"

    // MARK: - Club

    func fetchClub(id: String) async throws -> Club? {
        let doc = try await db.collection("clubs").document(id).getDocument()
        return try doc.data(as: Club.self)
    }

    // MARK: - Memberships

    func fetchLeaderboard(clubID: String) async throws -> [Membership] {
        let snapshot = try await db.collection("memberships")
            .whereField("clubId", isEqualTo: clubID)
            .whereField("isActive", isEqualTo: true)
            .order(by: "tagNumber")
            .getDocuments()
        return try snapshot.documents.compactMap { try $0.data(as: Membership.self) }
    }

    func fetchMembership(userId: String, clubId: String) async throws -> Membership? {
        let snapshot = try await db.collection("memberships")
            .whereField("userId", isEqualTo: userId)
            .whereField("clubId", isEqualTo: clubId)
            .whereField("isActive", isEqualTo: true)
            .limit(to: 1)
            .getDocuments()
        return try snapshot.documents.first.flatMap { try $0.data(as: Membership.self) }
    }

    func joinDaltonClub(userId: String, userFullName: String) async throws {
        // Prevent duplicate memberships
        let existing = try await db.collection("memberships")
            .whereField("userId", isEqualTo: userId)
            .whereField("clubId", isEqualTo: daltonClubID)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        guard existing.documents.isEmpty else { return }

        // Count current active members to determine tag number
        let activeSnap = try await db.collection("memberships")
            .whereField("clubId", isEqualTo: daltonClubID)
            .whereField("isActive", isEqualTo: true)
            .getDocuments()
        let nextTag = activeSnap.documents.count + 1

        let membership = Membership(
            userId: userId,
            clubId: daltonClubID,
            tagNumber: nextTag,
            userFullName: userFullName,
            joinedAt: Date(),
            isActive: true
        )
        try db.collection("memberships").addDocument(from: membership)

        // Increment memberCount on the club document
        try await db.collection("clubs").document(daltonClubID).updateData([
            "memberCount": FieldValue.increment(Int64(1))
        ])
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
}
