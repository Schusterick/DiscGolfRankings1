import SwiftUI

struct OnboardingView: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false
    @AppStorage("onboardingIntent")  private var onboardingIntent  = ""   // "browse" | "request"
    @State private var page = 0

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            TabView(selection: $page) {
                page1.tag(0)
                page2.tag(1)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Page 1 — For Players

    private var page1: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 12)

            Image(systemName: "figure.disc.sports")
                .font(.system(size: 78))
                .foregroundStyle(Theme.accent)
                .shadow(color: Theme.accent.opacity(0.4), radius: 20)

            VStack(spacing: 8) {
                Text("DiscGolfRankings")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("100% Free to Join")
                    .font(.title3.bold())
                    .foregroundStyle(Theme.gold)
            }

            // Benefit rows — why players use the app
            VStack(spacing: 12) {
                benefitRow(icon: "tag.fill",
                           color: Theme.gold,
                           title: "Your Tag, Always With You",
                           subtitle: "Your bag tag lives on your phone — never lost, never reprinted.")
                benefitRow(icon: "list.number",
                           color: Theme.accent,
                           title: "Live Rankings",
                           subtitle: "See your club's full leaderboard and your World Ranking in real time.")
                benefitRow(icon: "bolt.fill",
                           color: Theme.gold,
                           title: "Challenges & Confirmed Scores",
                           subtitle: "Challenge anyone in your club. Every score is signed off by the players — no disputes.")
                benefitRow(icon: "bell.badge.fill",
                           color: Theme.accent,
                           title: "Instant Notifications",
                           subtitle: "Know the second you're challenged or your tag moves.")
                benefitRow(icon: "hand.raised.fill",
                           color: Theme.success,
                           title: "We Don't Take a Cut",
                           subtitle: "0% platform fee. Every dollar you pay your club stays with your club.")
            }
            .padding(.horizontal, 20)

            Spacer()

            Button { withAnimation { page = 1 } } label: {
                Text("Next")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }

    // MARK: Page 2 — For Clubs

    private var page2: some View {
        VStack(spacing: 24) {
            Spacer().frame(height: 12)

            Image(systemName: "trophy.fill")
                .font(.system(size: 70))
                .foregroundStyle(Theme.gold)
                .shadow(color: Theme.gold.opacity(0.4), radius: 20)

            VStack(spacing: 8) {
                Text("Run Your Club")
                    .font(.system(size: 28, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Free for 60 days, then $50/year")
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.gold)
            }

            VStack(spacing: 12) {
                benefitRow(icon: "tag.fill",
                           color: Theme.gold,
                           title: "Modern Tag System",
                           subtitle: "Tags move automatically after every confirmed round. No spreadsheets, no disputes.")
                benefitRow(icon: "megaphone.fill",
                           color: Theme.accent,
                           title: "Reach Every Member Instantly",
                           subtitle: "One tap sends a push notification to your whole club — announcements, events, weather calls.")
                benefitRow(icon: "link",
                           color: Theme.success,
                           title: "Grow With a Shareable Link",
                           subtitle: "Post your club's link anywhere. New members join in seconds and get a tag.")
                benefitRow(icon: "calendar.badge.checkmark",
                           color: Theme.gold,
                           title: "Events, Leagues & Challenges",
                           subtitle: "Post events with signup links and reminders. Keep the club competing all season.")
            }
            .padding(.horizontal, 20)

            Spacer()

            VStack(spacing: 10) {
                Button {
                    onboardingIntent  = "browse"
                    hasSeenOnboarding = true
                } label: {
                    Text("Find a Club")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14))
                }

                Button {
                    onboardingIntent  = "request"
                    hasSeenOnboarding = true
                } label: {
                    Text("Start a Club")
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent, lineWidth: 1.5))
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 40)
        }
    }

    // MARK: Shared row component

    @ViewBuilder
    private func benefitRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 44, height: 44)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.bold())
                    .foregroundStyle(Theme.textPrimary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
        }
        .padding(12)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12))
    }
}
