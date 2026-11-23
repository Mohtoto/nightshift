import SwiftUI

enum AppTab: Hashable {
    case map
    case meets
    case garage
    case feed
    case profile
}

struct RootView: View {
    @Environment(AppModel.self) private var app
    @AppStorage("nightshift.onboarded") private var onboarded = false
    @State private var showLaunch: Bool
    @State private var startInSignUp = false

    init() {
        _showLaunch = State(initialValue: !CommandLine.arguments.contains("-skipLaunch"))
    }

    var body: some View {
        ZStack {
            Group {
                if app.profile == nil {
                    if !onboarded {
                        OnboardingView {
                            onboarded = true
                            startInSignUp = true
                        }
                    } else {
                        AuthView(initialMode: startInSignUp ? .signUp : .signIn)
                    }
                } else {
                    MainTabView()
                }
            }
            .nightshiftScreen()
            if showLaunch && !app.skipLaunch {
                LaunchOverlay { showLaunch = false }
            }
            if let toast = app.toast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NightshiftColor.text)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background(.ultraThinMaterial, in: Capsule())
                        .padding(.bottom, 28)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .accessibilityAddTraits(.isStaticText)
            }
        }
        .preferredColorScheme(.dark)
        .tint(NightshiftColor.purple)
        .animation(.spring(duration: 0.3), value: app.toast)
        .task { await app.restore() }
    }
}

struct LaunchOverlay: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var onFinished: () -> Void
    @State private var shown = false

    var body: some View {
        ZStack {
            NightshiftColor.background.ignoresSafeArea()
            Wordmark(size: 36)
                .opacity(shown ? 1 : 0)
                .scaleEffect(shown || reduceMotion ? 1 : 0.96)
        }
        .contentShape(Rectangle())
        .onTapGesture { onFinished() }
        .task {
            if reduceMotion {
                shown = true
                try? await Task.sleep(for: .milliseconds(180))
            } else {
                withAnimation(.easeOut(duration: 0.35)) { shown = true }
                try? await Task.sleep(for: .milliseconds(900))
            }
            onFinished()
        }
        .accessibilityLabel("Nightshift. Tap to continue.")
        .accessibilityAddTraits(.isButton)
    }
}

struct MainTabView: View {
    @Environment(AppModel.self) private var app
    @State private var tab: AppTab = .map

    var body: some View {
        TabView(selection: $tab) {
            MapScreen()
                .tabItem { Label("Map", systemImage: "map.fill") }
                .tag(AppTab.map)
            MeetsScreen()
                .tabItem { Label("Meets", systemImage: "flag.checkered") }
                .tag(AppTab.meets)
            GarageScreen()
                .tabItem { Label("Garage", systemImage: "car.fill") }
                .tag(AppTab.garage)
            FeedScreen()
                .tabItem { Label("Feed", systemImage: "square.stack.fill") }
                .tag(AppTab.feed)
            ProfileScreen(userID: nil)
                .tabItem { Label("Profile", systemImage: "person.crop.circle.fill") }
                .tag(AppTab.profile)
                .badge(app.unreadNotifications)
        }
        .sensoryFeedback(.selection, trigger: tab)
        .toolbarBackground(.ultraThinMaterial, for: .tabBar)
        .toolbarBackground(.visible, for: .tabBar)
    }
}
