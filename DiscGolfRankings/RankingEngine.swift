import Foundation

// MARK: - RankingEngine
// Pure functions — no Firestore, no SwiftUI. Easy to test and reason about.
//
// After an event:
//   • Attendees keep the *pool* of tags they collectively held, redistributed
//     among themselves by event finish order (best finisher → lowest tag in pool).
//   • Non-attendees have their old tag bumped down by `demotion` (default 2).
//   • The combined list is re-sorted (with attendees winning ties over no-shows)
//     and renumbered 1..N so there are no gaps or collisions.

enum RankingEngine {

    /// Computes new tag numbers for every member of a club after an event.
    /// - Parameters:
    ///   - members:     All active club members with their CURRENT tag numbers.
    ///   - eventTotals: Map of `userId → total event score` (sum of all rounds).
    ///                  Only attendees appear here. Lower score = better finish.
    ///   - demotion:    How many positions to drop each non-attendee. Default 2.
    /// - Returns: Map of `userId → new tag number` for every member.
    ///            Returns an empty dict if `eventTotals` is empty.
    static func redistribute(
        members: [Membership],
        eventTotals: [String: Int],
        demotion: Int = 2
    ) -> [String: Int] {
        guard !eventTotals.isEmpty else { return [:] }     // nothing to do

        let attendeeIds = Set(eventTotals.keys)
        let attendees    = members.filter {  attendeeIds.contains($0.userId) }
        let nonAttendees = members.filter { !attendeeIds.contains($0.userId) }

        // 1. Sort attendees by event score ascending (lower = better)
        let sortedAttendees = attendees.sorted {
            (eventTotals[$0.userId] ?? .max) < (eventTotals[$1.userId] ?? .max)
        }
        // 2. Pool of tags currently held by attendees, sorted ascending
        let pool = attendees.map { $0.tagNumber }.sorted()

        // 3. Best finisher → lowest tag in the pool, etc.
        var earned: [String: Int] = [:]
        for (idx, m) in sortedAttendees.enumerated() {
            earned[m.userId] = pool[idx]
        }
        // 4. Non-attendees: old tag + demotion
        for m in nonAttendees {
            earned[m.userId] = m.tagNumber + demotion
        }

        // 5. Global sort: by earned tag ascending; attendees win ties; then by old tag
        let sortedAll = members.sorted { a, b in
            let aTag = earned[a.userId] ?? .max
            let bTag = earned[b.userId] ?? .max
            if aTag != bTag { return aTag < bTag }
            let aAttended = attendeeIds.contains(a.userId)
            let bAttended = attendeeIds.contains(b.userId)
            if aAttended != bAttended { return aAttended }
            return a.tagNumber < b.tagNumber
        }

        // 6. Renumber 1..N
        var final: [String: Int] = [:]
        for (idx, m) in sortedAll.enumerated() {
            final[m.userId] = idx + 1
        }
        return final
    }

    /// A view-model row showing one player's before/after tag, used by the preview UI.
    struct PreviewRow: Identifiable {
        let id:       String     // userId
        let name:     String
        let oldTag:   Int
        let newTag:   Int
        let attended: Bool
        let total:    Int?       // nil for no-shows

        var delta: Int { oldTag - newTag }   // positive = moved up
    }

    /// Builds a sorted preview list for the admin's review screen.
    /// Sorted by new tag ascending.
    static func preview(
        members:     [Membership],
        eventTotals: [String: Int],
        demotion:    Int = 2
    ) -> [PreviewRow] {
        let newTags = redistribute(members: members, eventTotals: eventTotals, demotion: demotion)
        let attendeeIds = Set(eventTotals.keys)
        return members.map { m in
            PreviewRow(
                id:       m.userId,
                name:     m.userFullName,
                oldTag:   m.tagNumber,
                newTag:   newTags[m.userId] ?? m.tagNumber,
                attended: attendeeIds.contains(m.userId),
                total:    eventTotals[m.userId]
            )
        }
        .sorted { $0.newTag < $1.newTag }
    }
}
