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
                page3.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))
        }
        .preferredColorScheme(.dark)
    }

    // MARK: Page 1 — Brand

    private var page1: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "figure.disc.sports")
                .font(.system(size: 96))
                .foregroundStyle(Theme.accent)
                .shadow(color: Theme.accent.opacity(0.4), radius: 20)

            VStack(spacing: 12) {
                Text("DiscGolfRankings")
                    .font(.system(size: 36, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Own Your Rank")
                    .font(.title2.bold())
                    .foregroundStyle(Theme.gold)
                Text("The official tag-match ranking system\nfor disc golf clubs.")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button { withAnimation { page = 1 } } label: {
                Text("Get Started")
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

    // MARK: Page 2 — How It Works

    private var page2: some View {
        VStack(spacing: 32) {
            Spacer()
            Text("How It Works")
                .font(.system(size: 30, weight: .black, design: .rounded))
                .foregroundStyle(Theme.textPrimary)

            VStack(spacing: 20) {
                howItWorksRow(icon: "person.badge.plus", color: Theme.accent,
                              title: "Join a Club", subtitle: "Find your local disc golf club and become a member.")
                howItWorksRow(icon: "tag.fill", color: Theme.gold,
                              title: "Get Your Tag", subtitle: "Every member gets a tag number. Lower is better — #1 is the champion.")
                howItWorksRow(icon: "flag.checkered.2.crossed", color: Theme.success,
                              title: "Play for Tags", subtitle: "Beat other members to take their tag. Winners swap numbers after every round.")
            }
            .padding(.horizontal, 24)

            Spacer()

            Button { withAnimation { page = 2 } } label: {
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

    @ViewBuilder
    private func howItWorksRow(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(color)
                .frame(width: 48, height: 48)
                .background(color.opacity(0.15), in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(subtitle).font(.subheadline).foregroundStyle(Theme.textSecondary)
            }
            Spacer()
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: Page 3 — CTA

    private var page3: some View {
        VStack(spacing: 32) {
            Spacer()
            Image(systemName: "magnifyingglass.circle.fill")
                .font(.system(size: 80))
                .foregroundStyle(Theme.gold)

            VStack(spacing: 12) {
                Text("Find Your Club")
                    .font(.system(size: 30, weight: .black, design: .rounded))
                    .foregroundStyle(Theme.textPrimary)
                Text("Search for an existing club near you, or request to start your own.")
                    .font(.body)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            VStack(spacing: 14) {
                Button {
                    onboardingIntent  = "browse"
                    hasSeenOnboarding = true
                } label: {
                    Text("Browse Clubs")
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
                    Text("Request a Club")
                        .font(.headline)
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Theme.accent, lineWidth: 1.5))
                }
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
    }
}
