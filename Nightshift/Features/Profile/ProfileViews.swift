import PhotosUI
import SwiftUI

enum ProfileSection: String, CaseIterable, Identifiable {
    case garage = "Garage"
    case posts = "Posts"
    case attended = "Attended"
    case hosted = "Hosted"
    var id: String { rawValue }
}

struct ProfileScreen: View {
    var userID: UUID?
    @Environment(AppModel.self) private var app
    @State private var card: ProfileCard?
    @State private var section: ProfileSection = .garage
    @State private var cars: [VehicleSummary] = []
    @State private var posts: [PostItem] = []
    @State private var attended: [EventSummary] = []
    @State private var hosted: [EventSummary] = []
    @State private var error: String?
    @State private var isLoading = true
    @State private var showSettings = false
    @State private var showEditor = false
    @State private var report = false

    private var resolvedID: UUID? { userID ?? app.profile?.id }
    private var isMine: Bool { resolvedID == app.profile?.id }

    var body: some View {
        NavigationStack {
            ScrollView {
                if let card {
                    ProfileHeader(card: card)
                    if isMine {
                        HStack {
                            Button("Edit profile") { showEditor = true }
                            NavigationLink("Notifications") { NotificationsView() }
                                .accessibilityIdentifier("profile.notifications")
                        }
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(NightshiftColor.purple)
                        .padding(.horizontal, 16)
                    } else if card.isBlockedByMe {
                        Text("You blocked this driver. Their posts and meets stay hidden.")
                            .font(.subheadline)
                            .foregroundStyle(NightshiftColor.secondaryText)
                            .padding(.horizontal, 16)
                        Button("Unblock") { Task { await setBlocked(false) } }
                            .padding(.horizontal, 16)
                    } else {
                        HStack {
                            Button(card.isFollowedByMe ? "Following" : "Follow") {
                                Task { await setFollowing(!card.isFollowedByMe) }
                            }
                            Button("Block", role: .destructive) { Task { await setBlocked(true) } }
                            Button("Report") { report = true }
                        }
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 16)
                    }
                    if !card.isBlockedByMe {
                        sectionPicker
                        sectionContent
                    }
                } else if let error {
                    ErrorState(message: error) { Task { await load() } }
                } else {
                    LoadingState(title: "Loading profile")
                        .frame(height: 240)
                }
            }
            .nightshiftScreen()
            .navigationTitle(isMine ? "Profile" : (card?.profile.displayName ?? "Driver"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isMine {
                    ToolbarItem(placement: .primaryAction) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            Label("Settings", systemImage: "gearshape")
                        }
                        .accessibilityIdentifier(UIID.settings)
                    }
                }
            }
            .refreshable { await load() }
            .sheet(isPresented: $showEditor, onDismiss: { Task { await load() } }) {
                EditProfileView()
            }
            .sheet(isPresented: $report) {
                if let id = resolvedID { ReportSheet(target: .profile, targetID: id) }
            }
        }
        .task { await load() }
    }

    private var sectionPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                ForEach(ProfileSection.allCases) { item in
                    Button(item.rawValue) { section = item }
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(section == item ? NightshiftColor.text : NightshiftColor.secondaryText)
                        .padding(.bottom, 6)
                        .overlay(alignment: .bottom) {
                            if section == item {
                                Rectangle().fill(NightshiftColor.purple).frame(height: 2)
                            }
                        }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch section {
        case .garage:
            if cars.isEmpty {
                Text(isMine ? "No cars in the garage yet." : "This garage is private or empty.")
                    .foregroundStyle(NightshiftColor.secondaryText)
                    .padding()
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                    ForEach(cars) { car in
                        NavigationLink { VehicleDetailView(vehicleID: car.id) } label: {
                            VehicleCard(summary: car)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
        case .posts:
            if posts.isEmpty {
                Text("No posts yet.").foregroundStyle(NightshiftColor.secondaryText).padding()
            } else {
                LazyVStack(spacing: 20) {
                    ForEach(posts) { post in
                        PostCard(post: post) { Task { await toggle(post) } }
                    }
                }
                .padding(16)
            }
        case .attended:
            eventList(attended, empty: "No meets attended yet.")
        case .hosted:
            eventList(hosted, empty: "No meets hosted yet.")
        }
    }

    private func eventList(_ events: [EventSummary], empty: String) -> some View {
        VStack(spacing: 12) {
            if events.isEmpty {
                Text(empty).foregroundStyle(NightshiftColor.secondaryText)
            }
            ForEach(events) { event in
                NavigationLink { EventDetailView(eventID: event.id) } label: {
                    EventCard(summary: event)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
    }

    private func load() async {
        guard let id = resolvedID else { return }
        do {
            async let profile = app.repository.profile(id: id)
            async let garage = app.repository.vehicles(ownerID: id)
            async let feed = app.repository.posts(authorID: id, before: nil, limit: 30)
            let subject = isMine ? nil : id
            async let going = app.repository.events(filter: EventQuery(joinedOnly: true, subjectID: subject, limit: 30))
            async let hosting = app.repository.events(filter: EventQuery(hostedOnly: true, subjectID: subject, limit: 30))
            card = try await profile
            cars = try await garage
            posts = try await feed
            attended = try await going
            hosted = try await hosting
            error = nil
            if isMine { await app.refreshUnread() }
        } catch {
            self.error = nightshiftMessage(error)
        }
        isLoading = false
    }

    private func setFollowing(_ following: Bool) async {
        guard let id = resolvedID else { return }
        do {
            try await app.repository.setFollowing(userID: id, following: following)
            await load()
        } catch {
            self.error = nightshiftMessage(error)
        }
    }

    private func setBlocked(_ blocked: Bool) async {
        guard let id = resolvedID else { return }
        do {
            try await app.repository.setBlocked(userID: id, blocked: blocked)
            await load()
        } catch {
            self.error = nightshiftMessage(error)
        }
    }

    private func toggle(_ post: PostItem) async {
        try? await app.repository.setPostLike(id: post.id, liked: !post.likedByMe)
        await load()
    }
}

struct EditProfileView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var username = ""
    @State private var displayName = ""
    @State private var bio = ""
    @State private var city = ""
    @State private var showGarage = true
    @State private var showCity = true
    @State private var message: String?
    @State private var avatarItem: PhotosPickerItem?
    @State private var coverItem: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    PhotosPicker(selection: $coverItem, matching: .images) { Label("Change cover", systemImage: "photo") }
                        .onChange(of: coverItem) { _, item in Task { await upload(item, cover: true) } }
                    PhotosPicker(selection: $avatarItem, matching: .images) { Label("Change avatar", systemImage: "person.crop.circle") }
                        .onChange(of: avatarItem) { _, item in Task { await upload(item, cover: false) } }
                    if app.uiTesting {
                        Button("Use test photo") {
                            Task {
                                _ = try? await app.repository.uploadAvatar(TestImages.jpeg(seed: 4))
                                if let id = app.profile?.id, let card = try? await app.repository.profile(id: id) {
                                    await app.adopt(card.profile)
                                }
                            }
                        }
                        .accessibilityIdentifier(UIID.testPhoto)
                    }
                    NightshiftField(title: "Username", text: $username, capitalization: .never, contentType: .username)
                    NightshiftField(title: "Display name", text: $displayName, contentType: .name)
                    NightshiftField(title: "Bio", text: $bio, axis: .vertical)
                    NightshiftField(title: "Home city", text: $city)
                    Toggle("Show my garage", isOn: $showGarage)
                    Toggle("Show my city", isOn: $showCity)
                    if let message { Text(message).foregroundStyle(NightshiftColor.pink) }
                    NeonPrimaryButton(title: "Save profile") { Task { await save() } }
                }
                .padding(20)
            }
            .nightshiftScreen()
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .onAppear {
                if let profile = app.profile {
                    username = profile.username
                    displayName = profile.displayName
                    bio = profile.bio
                    city = profile.homeCity ?? ""
                    showGarage = profile.showGarage
                    showCity = profile.showCity
                }
            }
        }
    }

    private func save() async {
        guard var profile = app.profile else { return }
        profile.username = username
        profile.displayName = displayName
        profile.bio = bio
        profile.homeCity = city
        profile.showGarage = showGarage
        profile.showCity = showCity
        do {
            let updated = try await app.repository.updateProfile(profile)
            await app.adopt(updated)
            dismiss()
        } catch {
            message = nightshiftMessage(error)
        }
    }

    private func upload(_ item: PhotosPickerItem?, cover: Bool) async {
        guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
        do {
            let profile = cover ? try await app.repository.uploadCover(data) : try await app.repository.uploadAvatar(data)
            app.images.invalidate()
            await app.adopt(profile)
        } catch {
            message = nightshiftMessage(error)
        }
    }
}

struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmDelete = false
    @State private var blocked: [Profile] = []
    @State private var reports: [Report] = []
    @State private var message: String?

    var body: some View {
        List {
            Section("Storage") {
                Text(app.storageDescription)
            }
            Section("Blocked drivers") {
                if blocked.isEmpty { Text("Nobody is blocked.") }
                ForEach(blocked) { profile in
                    HStack {
                        Text(profile.displayName)
                        Spacer()
                        Button("Unblock") { Task { await unblock(profile) } }
                    }
                }
            }
            Section("Reports you filed") {
                if reports.isEmpty {
                    Text("Reports are saved for review. Moderators hide content from the Supabase dashboard. Blocking and deleting your own posts is immediate.")
                }
                ForEach(reports) { report in
                    VStack(alignment: .leading) {
                        Text(report.targetType.rawValue.capitalized).font(.subheadline.weight(.semibold))
                        Text(report.reason).font(.caption).foregroundStyle(NightshiftColor.secondaryText)
                    }
                }
            }
            Section {
                Button("Sign out", role: .destructive) { Task { await app.signOut() } }
                    .accessibilityIdentifier(UIID.signOut)
                Button("Delete account", role: .destructive) { confirmDelete = true }
            }
            if let message {
                Section { Text(message).foregroundStyle(NightshiftColor.pink) }
            }
        }
        .scrollContentBackground(.hidden)
        .nightshiftScreen()
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
        .confirmationDialog("Delete your account and everything you posted?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete account", role: .destructive) { Task { await deleteAccount() } }
        }
    }

    private func load() async {
        blocked = (try? await app.repository.blockedUsers()) ?? []
        reports = (try? await app.repository.reportsFiled()) ?? []
    }

    private func unblock(_ profile: Profile) async {
        try? await app.repository.setBlocked(userID: profile.id, blocked: false)
        await load()
    }

    private func deleteAccount() async {
        do {
            try await app.repository.deleteAccount()
            await app.signOut()
        } catch {
            message = nightshiftMessage(error)
        }
    }
}

struct NotificationsView: View {
    @Environment(AppModel.self) private var app
    @State private var notes: [AppNotification] = []

    var body: some View {
        Group {
            if notes.isEmpty {
                EmptyState(systemImage: "bell", title: "No notifications", message: "Follows, likes, comments, and meet joins show up here.")
            } else {
                List(notes) { note in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.message).foregroundStyle(note.readAt == nil ? NightshiftColor.text : NightshiftColor.secondaryText)
                        Text(NightshiftFormat.relative(note.createdAt))
                            .font(.caption)
                            .foregroundStyle(NightshiftColor.secondaryText)
                    }
                    .listRowBackground(NightshiftColor.background)
                }
                .scrollContentBackground(.hidden)
            }
        }
        .nightshiftScreen()
        .navigationTitle("Notifications")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            notes = (try? await app.repository.notifications()) ?? []
            try? await app.repository.markNotificationsRead()
            await app.refreshUnread()
        }
    }
}
