import Foundation
import FirebaseFirestore

// MARK: - User

struct AppUser: Identifiable, Codable {
    @DocumentID var id: String?
    var email: String
    var displayName: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, email, displayName, createdAt
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

    enum ClubStatus: String, Codable, CaseIterable, Hashable {
        case pending = "pending"
        case approved = "approved"
        case rejected = "rejected"
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
    var isActive: Bool
}

// MARK: - Challenge

struct Challenge: Identifiable, Codable, Hashable {
    @DocumentID var id: String?
    var clubID: String
    var challengerUID: String
    var challengerName: String
    var challengerTag: Int
    var defendantUID: String
    var defendantName: String
    var defendantTag: Int
    var status: ChallengeStatus
    var createdAt: Date
    var resolvedAt: Date?
    var winnerUID: String?
    var courseName: String?
    var notes: String?

    enum ChallengeStatus: String, Codable, CaseIterable, Hashable {
        case pending = "pending"
        case accepted = "accepted"
        case completed = "completed"
        case declined = "declined"
        case cancelled = "cancelled"
    }

    var isActive: Bool {
        status == .pending || status == .accepted
    }
}

// MARK: - ClubJoinRequest

struct ClubJoinRequest: Identifiable, Codable {
    @DocumentID var id: String?
    var userID: String
    var displayName: String
    var clubID: String
    var status: RequestStatus
    var requestedAt: Date

    enum RequestStatus: String, Codable {
        case pending = "pending"
        case approved = "approved"
        case rejected = "rejected"
    }
}
