import SwiftUI
import UIKit

enum NightshiftColor {
    static let background = Color(hex: 0x08090F)
    static let secondaryBackground = Color(hex: 0x121420)
    static let elevated = Color(hex: 0x1B1D2B)
    static let purple = Color(hex: 0xA020F0)
    static let violet = Color(hex: 0x7B2CFF)
    static let pink = Color(hex: 0xFF2D92)
    static let cyan = Color(hex: 0x00E5FF)
    static let text = Color(hex: 0xF7F7FB)
    static let secondaryText = Color(hex: 0x9396AB)
    static let hairline = Color.white.opacity(0.08)

    static func ui(_ hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(hex: hex, alpha: alpha)
    }
}

extension EventCategory {
    var accent: Color {
        switch self {
        case .show: NightshiftColor.pink
        case .track: NightshiftColor.cyan
        default: NightshiftColor.purple
        }
    }
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        let red = Double((hex >> 16) & 0xFF) / 255
        let green = Double((hex >> 8) & 0xFF) / 255
        let blue = Double(hex & 0xFF) / 255
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        let red = CGFloat((hex >> 16) & 0xFF) / 255
        let green = CGFloat((hex >> 8) & 0xFF) / 255
        let blue = CGFloat(hex & 0xFF) / 255
        self.init(red: red, green: green, blue: blue, alpha: alpha)
    }
}

enum NightshiftFont {
    static func display(_ size: CGFloat) -> Font {
        .system(size: size, weight: .black, design: .default)
    }

    static func title(_ size: CGFloat = 22) -> Font {
        .system(size: size, weight: .bold, design: .default)
    }
}

struct ScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content.background(NightshiftColor.background.ignoresSafeArea())
    }
}

extension View {
    func nightshiftScreen() -> some View {
        modifier(ScreenBackground())
    }

    @ViewBuilder
    func nightshiftZoomSource<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    @ViewBuilder
    func nightshiftZoomDestination<ID: Hashable>(id: ID, in namespace: Namespace.ID) -> some View {
        if #available(iOS 18.0, *) {
            self.navigationTransition(.zoom(sourceID: id, in: namespace))
        } else {
            self
        }
    }
}

enum NightshiftLayout {
    static func avoidance(in proxy: GeometryProxy) -> EdgeInsets {
        guard #available(iOS 27.1, *) else { return EdgeInsets() }
        let regions = proxy.reservedRegions(kind: .occlusion)
            + proxy.reservedRegions(kind: .division).filter(\.isActive)
        return insets(for: regions.map(\.frame), in: proxy.size)
    }

    private static func insets(for frames: [CGRect], in size: CGSize) -> EdgeInsets {
        var top: CGFloat = 0
        var bottom: CGFloat = 0
        var leading: CGFloat = 0
        var trailing: CGFloat = 0
        for frame in frames where frame.width > 1 && frame.height > 1 {
            if frame.minY < 140 {
                top = max(top, frame.maxY)
            }
            if frame.maxY > size.height - 180 {
                bottom = max(bottom, size.height - frame.minY)
            }
            if frame.minX < 100 {
                leading = max(leading, frame.maxX)
            }
            if frame.maxX > size.width - 100 {
                trailing = max(trailing, size.width - frame.minX)
            }
        }
        return EdgeInsets(top: top, leading: leading, bottom: bottom, trailing: trailing)
    }
}

enum NightshiftAppearance {
    static func apply() {
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemUltraThinMaterialDark)
        appearance.backgroundColor = UIColor(hex: 0x08090F, alpha: 0.72)
        let item = UITabBarItemAppearance()
        let selected = UIColor(hex: 0xA020F0)
        let normal = UIColor(hex: 0x9396AB)
        item.selected.iconColor = selected
        item.selected.titleTextAttributes = [.foregroundColor: selected]
        item.normal.iconColor = normal
        item.normal.titleTextAttributes = [.foregroundColor: normal]
        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item
        UITabBar.appearance().standardAppearance = appearance
        UITabBar.appearance().scrollEdgeAppearance = appearance
        UITabBar.appearance().tintColor = selected
        UITabBar.appearance().unselectedItemTintColor = normal

        let navigation = UINavigationBarAppearance()
        navigation.configureWithOpaqueBackground()
        navigation.backgroundColor = UIColor(hex: 0x08090F)
        navigation.titleTextAttributes = [
            .foregroundColor: UIColor(hex: 0xF7F7FB),
            .font: UIFont.systemFont(ofSize: 17, weight: .bold)
        ]
        navigation.largeTitleTextAttributes = [.foregroundColor: UIColor(hex: 0xF7F7FB)]
        UINavigationBar.appearance().standardAppearance = navigation
        UINavigationBar.appearance().scrollEdgeAppearance = navigation
        UINavigationBar.appearance().compactAppearance = navigation
        UINavigationBar.appearance().tintColor = selected
    }
}

struct Wordmark: View {
    var size: CGFloat = 34
    var alignment: HorizontalAlignment = .center

    var body: some View {
        VStack(alignment: alignment, spacing: 6) {
            Text("NIGHTSHIFT")
                .font(NightshiftFont.display(size))
                .tracking(size * 0.14)
                .foregroundStyle(NightshiftColor.text)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Text("THE UNDERGROUND")
                .font(.caption.weight(.semibold))
                .tracking(2.4)
                .foregroundStyle(NightshiftColor.secondaryText)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Nightshift")
    }
}
