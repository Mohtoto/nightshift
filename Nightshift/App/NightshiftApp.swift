import SwiftUI

@main
struct NightshiftApp: App {
    @State private var appModel: AppModel

    init() {
        NightshiftAppearance.apply()
        if CommandLine.arguments.contains("-UITesting") {
            UserDefaults.standard.removeObject(forKey: "nightshift.onboarded")
        }
        _appModel = State(initialValue: AppModel())
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .environment(appModel.images)
                .environment(appModel.location)
        }
    }
}
