import SwiftUI

struct OnboardingView: View {
    var onFinish: () -> Void
    @State private var page = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let pages: [(symbol: String, kicker: String, title: String, message: String)] = [
        ("bolt.car.fill", "NIGHTSHIFT", "Welcome to the underground", "Find your people. Discover the meets. Show off your build."),
        ("map.fill", "YOUR CITY", "Your city. Your scene.", "Discover automotive events happening around you."),
        ("car.fill", "GARAGE", "Build your garage.", "Give your car the spotlight it deserves."),
        ("person.2.fill", "COMMUNITY", "Join the community.", "Create an account and enter the automotive community.")
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(pages.indices, id: \.self) { index in
                    pageView(pages[index])
                        .tag(index)
                        .padding(.horizontal, 28)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            Button(page == pages.count - 1 ? "Create your account" : "Next") {
                if page == pages.count - 1 {
                    onFinish()
                } else if reduceMotion {
                    page += 1
                } else {
                    withAnimation(.spring(duration: 0.35)) { page += 1 }
                }
            }
            .buttonStyle(.plain)
            .font(.headline.weight(.semibold))
            .frame(maxWidth: .infinity)
            .frame(minHeight: 52)
            .foregroundStyle(.white)
            .background(NightshiftColor.purple, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
            .accessibilityIdentifier(page == pages.count - 1 ? UIID.onboardingFinish : UIID.onboardingNext)
        }
        .nightshiftScreen()
    }

    private func pageView(_ page: (symbol: String, kicker: String, title: String, message: String)) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            Spacer()
            Image(systemName: page.symbol)
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(NightshiftColor.purple)
                .frame(width: 88, height: 88)
                .background(NightshiftColor.elevated, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            Text(page.kicker)
                .font(.caption.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(NightshiftColor.cyan)
            Text(page.title)
                .font(NightshiftFont.display(36))
                .foregroundStyle(NightshiftColor.text)
                .minimumScaleFactor(0.6)
                .fixedSize(horizontal: false, vertical: true)
            Text(page.message)
                .font(.title3)
                .foregroundStyle(NightshiftColor.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
