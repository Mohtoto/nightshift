import PhotosUI
import SwiftUI

@MainActor
@Observable
final class FeedModel {
    var posts: [PostItem] = []
    var isLoading = false
    var error: String?
    var canLoadMore = true
    private let app: AppModel
    private let authorID: UUID?

    init(app: AppModel, authorID: UUID? = nil) {
        self.app = app
        self.authorID = authorID
    }

    func reload() async {
        isLoading = posts.isEmpty
        defer { isLoading = false }
        do {
            let rows = try await app.repository.posts(authorID: authorID, before: nil, limit: 20)
            posts = rows
            canLoadMore = rows.count == 20
            error = nil
        } catch {
            self.error = nightshiftMessage(error)
        }
    }

    func loadMore() async {
        guard canLoadMore, let last = posts.last else { return }
        do {
            let rows = try await app.repository.posts(authorID: authorID, before: last.post.createdAt, limit: 20)
            let existing = Set(posts.map(\.id))
            posts.append(contentsOf: rows.filter { !existing.contains($0.id) })
            canLoadMore = rows.count == 20
        } catch {
            self.error = nightshiftMessage(error)
        }
    }

    func toggleLike(_ post: PostItem) async {
        if let index = posts.firstIndex(where: { $0.id == post.id }) {
            posts[index].likedByMe.toggle()
            posts[index].likeCount += posts[index].likedByMe ? 1 : -1
        }
        do {
            try await app.repository.setPostLike(id: post.id, liked: !(post.likedByMe))
        } catch {
            self.error = nightshiftMessage(error)
            await reload()
        }
    }
}

struct FeedScreen: View {
    @Environment(AppModel.self) private var app
    @State private var model: FeedModel?
    @State private var showComposer = false

    var body: some View {
        NavigationStack {
            Group {
                if let model {
                    feed(model)
                } else {
                    LoadingState(title: "Loading the feed")
                }
            }
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Post", systemImage: "plus") { showComposer = true }
                        .accessibilityIdentifier(UIID.feedCompose)
                }
            }
            .sheet(isPresented: $showComposer, onDismiss: { Task { await model?.reload() } }) {
                ComposerView()
            }
        }
        .task {
            let active: FeedModel
            if let model {
                active = model
            } else {
                let created = FeedModel(app: app)
                model = created
                active = created
            }
            await active.reload()
            for await signal in app.repository.changes() {
                if signal == .social { await active.reload() }
            }
        }
    }

    @ViewBuilder
    private func feed(_ model: FeedModel) -> some View {
        ScrollView {
            if model.isLoading && model.posts.isEmpty {
                LoadingState(title: "Loading posts").frame(height: 240)
            } else if let error = model.error, model.posts.isEmpty {
                ErrorState(message: error) { Task { await model.reload() } }
            } else if model.posts.isEmpty {
                EmptyState(systemImage: "square.stack", title: "The feed is quiet", message: "Post a photo of the build, a meet recap, or the next part going on.", actionTitle: "Create a post") {
                    showComposer = true
                }
            } else {
                LazyVStack(spacing: 22) {
                    if app.isOffline {
                        Text("You're offline. Posts you already opened stay here.")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(NightshiftColor.secondaryText)
                    }
                    ForEach(model.posts) { post in
                        PostCard(post: post) { Task { await model.toggleLike(post) } }
                            .onAppear {
                                if post.id == model.posts.last?.id { Task { await model.loadMore() } }
                            }
                    }
                }
                .padding(16)
            }
        }
        .nightshiftScreen()
        .refreshable { await model.reload() }
    }
}

struct PostCard: View {
    let post: PostItem
    var onLike: () -> Void
    @Environment(AppModel.self) private var app
    @State private var showComments = false
    @State private var report = false
    @State private var confirmDelete = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                NavigationLink { ProfileScreen(userID: post.author.id) } label: {
                    HStack(spacing: 10) {
                        UserAvatar(path: post.author.avatarURL, name: post.author.displayName, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(post.author.displayName).font(.subheadline.weight(.semibold))
                            Text(post.author.handle).font(.caption).foregroundStyle(NightshiftColor.secondaryText)
                        }
                    }
                }
                .buttonStyle(.plain)
                Spacer()
                Text(NightshiftFormat.relative(post.post.createdAt))
                    .font(.caption)
                    .foregroundStyle(NightshiftColor.secondaryText)
            }
            if let vehicle = post.vehicle {
                NavigationLink { VehicleDetailView(vehicleID: vehicle.id) } label: {
                    Text(vehicle.displayName)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(NightshiftColor.cyan)
                }
                .buttonStyle(.plain)
            }
            if !post.images.isEmpty {
                PhotoGallery(paths: post.images.map(\.storagePath), height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            if !post.post.caption.isEmpty {
                Text(post.post.caption)
                    .font(.body)
                    .foregroundStyle(NightshiftColor.text)
            }
            HStack(spacing: 18) {
                Button(action: onLike) {
                    Label("\(post.likeCount)", systemImage: post.likedByMe ? "heart.fill" : "heart")
                }
                .foregroundStyle(post.likedByMe ? NightshiftColor.pink : NightshiftColor.text)
                .accessibilityIdentifier(UIID.postLike)
                Button { showComments = true } label: {
                    Label("\(post.commentCount)", systemImage: "bubble.right")
                }
                ShareLink(item: post.post.caption.isEmpty ? "A Nightshift post" : post.post.caption) {
                    Image(systemName: "square.and.arrow.up")
                }
                Spacer()
                Button("Report", systemImage: "flag") { report = true }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(NightshiftColor.secondaryText)
                if post.author.id == app.profile?.id {
                    Button("Delete", systemImage: "trash") { confirmDelete = true }
                        .labelStyle(.iconOnly)
                        .foregroundStyle(NightshiftColor.secondaryText)
                }
            }
            .font(.headline)
            .foregroundStyle(NightshiftColor.text)
        }
        .sheet(isPresented: $showComments) { CommentSheet(postID: post.id) }
        .sheet(isPresented: $report) { ReportSheet(target: .post, targetID: post.id) }
        .confirmationDialog("Delete this post?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                Task { try? await app.repository.deletePost(id: post.id) }
            }
        }
    }
}

struct CommentSheet: View {
    let postID: UUID
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var notes: [ConversationNote] = []
    @State private var text = ""
    @State private var error: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List {
                    if notes.isEmpty {
                        Text("No comments yet.")
                            .foregroundStyle(NightshiftColor.secondaryText)
                            .listRowBackground(NightshiftColor.background)
                    }
                    ForEach(notes) { note in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(note.author.displayName).font(.subheadline.weight(.semibold))
                            Text(note.content)
                            if note.isMine {
                                Button("Delete", role: .destructive) { Task { await remove(note) } }
                                    .font(.caption)
                            }
                        }
                        .listRowBackground(NightshiftColor.background)
                    }
                }
                .scrollContentBackground(.hidden)
                if let error {
                    Text(error).font(.caption).foregroundStyle(NightshiftColor.pink).padding(.horizontal)
                }
                HStack {
                    TextField("Comment", text: $text, axis: .vertical)
                        .textFieldStyle(.plain)
                        .accessibilityIdentifier(UIID.commentField)
                    Button("Send") { Task { await send() } }
                        .accessibilityIdentifier(UIID.commentSend)
                }
                .padding(12)
                .background(NightshiftColor.elevated)
            }
            .nightshiftScreen()
            .navigationTitle("Comments")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .task { await load() }
        }
    }

    private func load() async {
        notes = (try? await app.repository.notes(postID: postID)) ?? []
    }

    private func send() async {
        do {
            try await app.repository.addNote(postID: postID, content: text)
            text = ""
            await load()
        } catch {
            self.error = nightshiftMessage(error)
        }
    }

    private func remove(_ note: ConversationNote) async {
        do {
            try await app.repository.deleteNote(id: note.id)
            await load()
        } catch {
            self.error = nightshiftMessage(error)
        }
    }
}

struct ComposerView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var caption = ""
    @State private var vehicleID: UUID?
    @State private var vehicles: [VehicleSummary] = []
    @State private var photos: [PhotoUpload] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var message: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    NightshiftField(title: "Caption", text: $caption, identifier: UIID.postCaption, axis: .vertical)
                    if !vehicles.isEmpty {
                        Picker("Car", selection: $vehicleID) {
                            Text("No car").tag(UUID?.none)
                            ForEach(vehicles) { vehicle in
                                Text(vehicle.vehicle.displayName).tag(UUID?.some(vehicle.id))
                            }
                        }
                    }
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            ForEach(photos) { photo in
                                if case .new(let data) = photo.source, let image = UIImage(data: data) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 90)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                }
                            }
                        }
                    }
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 6, matching: .images) {
                        Label("Add photos", systemImage: "photo")
                    }
                    .onChange(of: pickerItems) { _, items in
                        Task {
                            for item in items {
                                if let data = try? await item.loadTransferable(type: Data.self) {
                                    photos.append(PhotoUpload(source: .new(data)))
                                }
                            }
                            pickerItems = []
                        }
                    }
                    if app.uiTesting {
                        Button("Use test photo") { photos.append(PhotoUpload(source: .new(TestImages.jpeg(seed: 3)))) }
                            .accessibilityIdentifier(UIID.testPhoto)
                    }
                    if let message { Text(message).foregroundStyle(NightshiftColor.pink) }
                    NeonPrimaryButton(title: "Publish", isLoading: isSaving, identifier: UIID.postPublish) {
                        Task { await publish() }
                    }
                }
                .padding(20)
            }
            .nightshiftScreen()
            .navigationTitle("New post")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
            .task {
                if let id = app.profile?.id {
                    vehicles = (try? await app.repository.vehicles(ownerID: id)) ?? []
                }
            }
        }
    }

    private func publish() async {
        if let validation = Validators.post(caption: caption, hasImage: !photos.isEmpty) {
            message = validation
            return
        }
        isSaving = true
        defer { isSaving = false }
        var draft = PostDraft()
        draft.caption = caption
        draft.vehicleID = vehicleID
        draft.photos = photos
        do {
            _ = try await app.repository.createPost(draft)
            app.images.invalidate()
            app.showToast("Posted")
            dismiss()
        } catch {
            message = nightshiftMessage(error)
        }
    }
}
