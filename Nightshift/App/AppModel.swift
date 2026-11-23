import Foundation
import Network
import Observation

@MainActor
@Observable
final class AppModel {
    let repository: any NightshiftRepository
    let images: ImagePipeline
    let location = LocationService()
    var profile: Profile?
    var unreadNotifications = 0
    var toast: String?
    var isOffline = false
    let uiTesting: Bool
    let skipLaunch: Bool

    private let monitor = NWPathMonitor()

    init(repository: (any NightshiftRepository)? = nil) {
        let resolved = repository ?? Backend.makeRepository()
        self.repository = resolved
        self.images = ImagePipeline(repository: resolved)
        self.uiTesting = CommandLine.arguments.contains("-UITesting")
        self.skipLaunch = CommandLine.arguments.contains("-skipLaunch")
        if AppConfig.mode == .supabase {
            monitor.pathUpdateHandler = { [weak self] path in
                let offline = path.status != .satisfied
                Task { @MainActor in
                    self?.isOffline = offline
                }
            }
            monitor.start(queue: DispatchQueue(label: "nightshift.network"))
        }
    }

    var usesRemoteBackend: Bool { AppConfig.mode == .supabase }

    var storageDescription: String {
        switch AppConfig.mode {
        case .local: "On this iPhone"
        case .supabase: "Supabase"
        case .invalid(let message): message
        }
    }

    func restore() async {
        do {
            profile = try await repository.restoreSession()
            await refreshUnread()
            if profile == nil {
                await seedDemoIfRequested()
            }
        } catch {
            profile = nil
        }
    }

    func adopt(_ profile: Profile) async {
        self.profile = profile
        images.invalidate()
        await refreshUnread()
    }

    func refreshUnread() async {
        guard profile != nil else {
            unreadNotifications = 0
            return
        }
        unreadNotifications = (try? await repository.unreadNotificationCount()) ?? 0
    }

    func signOut() async {
        try? await repository.signOut()
        profile = nil
        unreadNotifications = 0
        images.invalidate()
    }

    func showToast(_ text: String) {
        toast = text
        Task {
            try? await Task.sleep(for: .seconds(1.8))
            if toast == text { toast = nil }
        }
    }

    private func seedDemoIfRequested() async {
        guard CommandLine.arguments.contains("-SeedDemo") else { return }
        let photo = TestImages.jpeg(seed: 1)
        let cover = TestImages.jpeg(seed: 2)
        guard case .signedIn(let profile) = try? await repository.signUp(
            email: "ada@nightshift.test",
            password: "underground",
            username: "ada_r",
            displayName: "Ada R"
        ) else { return }
        await adopt(profile)
        var vehicle = VehicleDraft()
        vehicle.make = "Nissan"
        vehicle.model = "Silvia"
        vehicle.year = 1999
        vehicle.trim = "Spec-R"
        vehicle.color = "Midnight purple"
        vehicle.nickname = "Afterhours"
        vehicle.description = "A street build for late meets and canyon roads."
        vehicle.photos = [PhotoUpload(source: .new(photo))]
        vehicle.modifications = [ModificationDraft(category: "Suspension", name: "Coilovers", description: "Street damping")]
        _ = try? await repository.saveVehicle(vehicle, existingID: nil)
        var event = EventDraft()
        event.title = "Harbor Lights Meet"
        event.description = "A lawful evening cars and coffee along the waterfront. No racing, no burnouts."
        event.address = "200 N Harbor Blvd, Los Angeles"
        event.latitude = 33.755
        event.longitude = -118.191
        event.startsAt = Date().addingTimeInterval(60 * 60 * 26)
        event.endsAt = Date().addingTimeInterval(60 * 60 * 30)
        event.category = .coffee
        event.coverData = cover
        _ = try? await repository.saveEvent(event, existingID: nil)
        var post = PostDraft()
        post.caption = "Fresh alignment before the harbor meet."
        post.photos = [PhotoUpload(source: .new(photo))]
        _ = try? await repository.createPost(post)
    }
}
