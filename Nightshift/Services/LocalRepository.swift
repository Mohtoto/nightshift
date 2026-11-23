import Foundation

actor LocalRepository: NightshiftRepository {
    struct Account: Codable, Hashable, Sendable {
        var id: UUID
        var email: String
        var passwordHash: String
        var appleUserID: String?
    }

    struct Database: Codable, Sendable {
        var accounts: [Account] = []
        var profiles: [Profile] = []
        var vehicles: [Vehicle] = []
        var vehiclePhotos: [VehiclePhoto] = []
        var modifications: [VehicleModification] = []
        var vehicleLikes: [VehicleLike] = []
        var vehicleComments: [VehicleComment] = []
        var events: [Event] = []
        var attendees: [Attendance] = []
        var posts: [Post] = []
        var postImages: [PostImage] = []
        var postLikes: [PostLike] = []
        var comments: [Comment] = []
        var follows: [Follow] = []
        var reports: [Report] = []
        var blocks: [Block] = []
        var notifications: [AppNotification] = []
    }

    private let directory: URL
    private var database: Database
    private var subscribers: [UUID: AsyncStream<ChangeSignal>.Continuation] = [:]

    init(directory: URL) {
        self.directory = directory
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("store.json")
        if let data = try? Data(contentsOf: url),
           let decoded = try? JSONCoding.decoder.decode(Database.self, from: data) {
            database = decoded
        } else {
            database = Database()
        }
    }

    static func makeDefault() -> LocalRepository {
        if CommandLine.arguments.contains("-UITesting") {
            let directory = uiTestDirectory()
            try? FileManager.default.removeItem(at: directory)
            return LocalRepository(directory: directory)
        }
        return LocalRepository(directory: defaultDirectory())
    }

    static func defaultDirectory() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Nightshift", isDirectory: true)
    }

    static func uiTestDirectory() -> URL {
        defaultDirectory().appendingPathComponent("UITest", isDirectory: true)
    }

    static func temporary() -> LocalRepository {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Nightshift-\(UUID().uuidString)", isDirectory: true)
        return LocalRepository(directory: directory)
    }

    func restoreSession() async throws -> Profile? {
        guard let id = readSession() else { return nil }
        return database.profiles.first { $0.id == id }
    }

    func signUp(email: String, password: String, username: String, displayName: String) async throws -> AuthOutcome {
        try validateCredentials(email: email, password: password, username: username, displayName: displayName)
        let normalizedEmail = normalizeEmail(email)
        let normalizedUsername = normalizeUsername(username)
        if database.accounts.contains(where: { $0.email == normalizedEmail }) {
            throw NightshiftError.message("An account with that email already exists.")
        }
        if database.profiles.contains(where: { $0.username == normalizedUsername }) {
            throw NightshiftError.message("That username is taken.")
        }
        let profile = Profile(
            id: UUID(),
            username: normalizedUsername,
            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
            avatarURL: nil,
            coverURL: nil,
            bio: "",
            homeCity: nil,
            showGarage: true,
            showCity: true,
            createdAt: Date()
        )
        database.accounts.append(Account(id: profile.id, email: normalizedEmail, passwordHash: PasswordHash.hash(password), appleUserID: nil))
        database.profiles.append(profile)
        try persist()
        try writeSession(profile.id)
        return .signedIn(profile)
    }

    func signIn(email: String, password: String) async throws -> Profile {
        let normalizedEmail = normalizeEmail(email)
        guard let account = database.accounts.first(where: { $0.email == normalizedEmail }) else {
            throw NightshiftError.message("That email and password don't match.")
        }
        guard account.passwordHash == PasswordHash.hash(password) else {
            throw NightshiftError.message("That email and password don't match.")
        }
        guard let profile = database.profiles.first(where: { $0.id == account.id }) else {
            throw NightshiftError.notFound
        }
        try writeSession(profile.id)
        return profile
    }

    func signInWithApple(userID: String, idToken: String?, nonce: String, fullName: PersonNameComponents?) async throws -> Profile {
        if let account = database.accounts.first(where: { $0.appleUserID == userID }),
           let profile = database.profiles.first(where: { $0.id == account.id }) {
            try writeSession(profile.id)
            return profile
        }
        let id = UUID()
        let preferred = "driver" + id.uuidString.prefix(8).lowercased()
        let username = uniqueUsername(preferred.filter { $0.isLetter || $0.isNumber })
        let name = formatted(fullName) ?? "Driver"
        let profile = Profile(
            id: id,
            username: username,
            displayName: name,
            avatarURL: nil,
            coverURL: nil,
            bio: "",
            homeCity: nil,
            showGarage: true,
            showCity: true,
            createdAt: Date()
        )
        database.accounts.append(Account(id: id, email: "\(username)@apple.nightshift.local", passwordHash: "", appleUserID: userID))
        database.profiles.append(profile)
        try persist()
        try writeSession(id)
        return profile
    }

    func requestPasswordReset(email: String) async throws {
        throw NightshiftError.message("This iPhone is storing Nightshift on device. Set a new password below instead of waiting for an email.")
    }

    func setPassword(email: String, newPassword: String) async throws {
        if let message = Validators.password(newPassword) { throw NightshiftError.message(message) }
        let normalizedEmail = normalizeEmail(email)
        guard let index = database.accounts.firstIndex(where: { $0.email == normalizedEmail }) else {
            throw NightshiftError.message("No account on this iPhone uses that email.")
        }
        database.accounts[index].passwordHash = PasswordHash.hash(newPassword)
        try persist()
    }

    func signOut() async throws {
        try? FileManager.default.removeItem(at: sessionURL)
    }

    func deleteAccount() async throws {
        let me = try requireUser()
        let vehicleIDs = Set(database.vehicles.filter { $0.ownerID == me }.map(\.id))
        let eventIDs = Set(database.events.filter { $0.hostID == me }.map(\.id))
        let postIDs = Set(database.posts.filter { $0.authorID == me }.map(\.id))
        for photo in database.vehiclePhotos where vehicleIDs.contains(photo.vehicleID) {
            removeFile(photo.storagePath)
        }
        for event in database.events where event.hostID == me {
            if let path = event.coverImagePath { removeFile(path) }
        }
        for image in database.postImages where postIDs.contains(image.postID) {
            removeFile(image.storagePath)
        }
        if let profile = database.profiles.first(where: { $0.id == me }) {
            if let path = profile.avatarURL { removeFile(path) }
            if let path = profile.coverURL { removeFile(path) }
        }
        database.accounts.removeAll { $0.id == me }
        database.profiles.removeAll { $0.id == me }
        database.vehicles.removeAll { $0.ownerID == me }
        database.vehiclePhotos.removeAll { vehicleIDs.contains($0.vehicleID) }
        database.modifications.removeAll { vehicleIDs.contains($0.vehicleID) }
        database.vehicleLikes.removeAll { $0.userID == me || vehicleIDs.contains($0.vehicleID) }
        database.vehicleComments.removeAll { $0.authorID == me || vehicleIDs.contains($0.vehicleID) }
        database.events.removeAll { $0.hostID == me }
        database.attendees.removeAll { $0.userID == me || eventIDs.contains($0.eventID) }
        database.posts.removeAll { $0.authorID == me }
        database.postImages.removeAll { postIDs.contains($0.postID) }
        database.postLikes.removeAll { $0.userID == me || postIDs.contains($0.postID) }
        database.comments.removeAll { $0.authorID == me || postIDs.contains($0.postID) }
        database.follows.removeAll { $0.followerID == me || $0.followingID == me }
        database.reports.removeAll { $0.reporterID == me }
        database.blocks.removeAll { $0.blockerID == me || $0.blockedID == me }
        database.notifications.removeAll { $0.recipientID == me || $0.payload.actorID == me }
        try persist()
        try? FileManager.default.removeItem(at: sessionURL)
        emit(.profile)
    }

    func profile(id: UUID) async throws -> ProfileCard {
        let me = try requireUser()
        guard var profile = database.profiles.first(where: { $0.id == id }) else { throw NightshiftError.notFound }
        let blockedByMe = blocked(by: me, other: id)
        let blockedByThem = blocked(by: id, other: me)
        if id != me && blockedByThem && !blockedByMe { throw NightshiftError.notFound }
        if id != me && !profile.showCity { profile.homeCity = nil }
        return ProfileCard(
            profile: profile,
            followerCount: database.follows.filter { $0.followingID == id }.count,
            followingCount: database.follows.filter { $0.followerID == id }.count,
            isFollowedByMe: database.follows.contains { $0.followerID == me && $0.followingID == id },
            isBlockedByMe: blockedByMe
        )
    }

    func updateProfile(_ profile: Profile) async throws -> Profile {
        let me = try requireUser()
        guard profile.id == me else { throw NightshiftError.message("You can only edit your profile.") }
        if let message = Validators.username(profile.username) { throw NightshiftError.message(message) }
        if let message = Validators.displayName(profile.displayName) { throw NightshiftError.message(message) }
        if let message = Validators.bio(profile.bio) { throw NightshiftError.message(message) }
        let username = normalizeUsername(profile.username)
        if database.profiles.contains(where: { $0.username == username && $0.id != me }) {
            throw NightshiftError.message("That username is taken.")
        }
        guard let index = database.profiles.firstIndex(where: { $0.id == me }) else { throw NightshiftError.notFound }
        var updated = profile
        updated.username = username
        updated.displayName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.homeCity = blankToNil(profile.homeCity ?? "")
        database.profiles[index] = updated
        try persist()
        emit(.profile)
        return updated
    }

    func uploadAvatar(_ data: Data) async throws -> Profile {
        try await uploadProfileImage(data, isCover: false)
    }

    func uploadCover(_ data: Data) async throws -> Profile {
        try await uploadProfileImage(data, isCover: true)
    }

    func vehicles(ownerID: UUID) async throws -> [VehicleSummary] {
        let me = try requireUser()
        if ownerID != me {
            if isBlockedEither(me, ownerID) { return [] }
            if database.profiles.first(where: { $0.id == ownerID })?.showGarage == false { return [] }
        }
        return database.vehicles
            .filter { $0.ownerID == ownerID }
            .sorted { $0.createdAt > $1.createdAt }
            .map { vehicleSummary($0) }
    }

    func vehicle(id: UUID) async throws -> VehicleDetail {
        let me = try requireUser()
        guard let vehicle = database.vehicles.first(where: { $0.id == id }) else { throw NightshiftError.notFound }
        if vehicle.ownerID != me {
            if isBlockedEither(me, vehicle.ownerID) { throw NightshiftError.notFound }
            if database.profiles.first(where: { $0.id == vehicle.ownerID })?.showGarage == false {
                throw NightshiftError.notFound
            }
        }
        guard var owner = database.profiles.first(where: { $0.id == vehicle.ownerID }) else { throw NightshiftError.notFound }
        if owner.id != me && !owner.showCity { owner.homeCity = nil }
        let photos = database.vehiclePhotos.filter { $0.vehicleID == id }.sorted { $0.sortOrder < $1.sortOrder }
        let mods = database.modifications.filter { $0.vehicleID == id }
        let joined = Set(database.attendees.filter { $0.userID == vehicle.ownerID && $0.vehicleID == id }.map(\.eventID))
        let meets = database.events
            .filter { event in
                guard joined.contains(event.id) else { return false }
                if me == vehicle.ownerID { return true }
                if isBlockedEither(me, event.hostID) { return false }
                if event.visibility == .public && event.status == .scheduled { return true }
                return database.attendees.contains { $0.eventID == event.id && $0.userID == me }
            }
            .sorted { $0.startsAt > $1.startsAt }
            .map { summary(for: $0, viewer: me) }
        return VehicleDetail(
            vehicle: vehicle,
            photos: photos,
            modifications: mods,
            owner: owner,
            likeCount: database.vehicleLikes.filter { $0.vehicleID == id }.count,
            likedByMe: database.vehicleLikes.contains { $0.vehicleID == id && $0.userID == me },
            commentCount: database.vehicleComments.filter { $0.vehicleID == id && !$0.hidden }.count,
            attendedMeets: meets
        )
    }

    func saveVehicle(_ draft: VehicleDraft, existingID: UUID?) async throws -> Vehicle {
        let me = try requireUser()
        if let message = Validators.vehicle(draft) { throw NightshiftError.message(message) }
        let id = existingID ?? UUID()
        let createdAt: Date
        if let existingID {
            guard let current = database.vehicles.first(where: { $0.id == existingID }) else { throw NightshiftError.notFound }
            guard current.ownerID == me else { throw NightshiftError.message("You can only edit cars in your garage.") }
            createdAt = current.createdAt
        } else {
            createdAt = Date()
        }
        let vehicle = Vehicle(
            id: id,
            ownerID: me,
            make: trimmed(draft.make),
            model: trimmed(draft.model),
            year: draft.year,
            trim: blankToNil(draft.trim),
            color: blankToNil(draft.color),
            bodyStyle: blankToNil(draft.bodyStyle),
            transmission: blankToNil(draft.transmission),
            engine: blankToNil(draft.engine),
            power: blankToNil(draft.power),
            nickname: blankToNil(draft.nickname),
            description: trimmed(draft.description),
            createdAt: createdAt
        )
        if let index = database.vehicles.firstIndex(where: { $0.id == id }) {
            database.vehicles[index] = vehicle
        } else {
            database.vehicles.append(vehicle)
        }
        try await replaceVehiclePhotos(vehicleID: id, uploads: draft.photos)
        database.modifications.removeAll { $0.vehicleID == id }
        for draftMod in draft.modifications {
            database.modifications.append(VehicleModification(
                id: draftMod.id,
                vehicleID: id,
                category: trimmed(draftMod.category).isEmpty ? "Other" : trimmed(draftMod.category),
                name: trimmed(draftMod.name),
                description: trimmed(draftMod.description)
            ))
        }
        try persist()
        emit(.garage)
        return vehicle
    }

    func deleteVehicle(id: UUID) async throws {
        let me = try requireUser()
        guard let vehicle = database.vehicles.first(where: { $0.id == id }) else { throw NightshiftError.notFound }
        guard vehicle.ownerID == me else { throw NightshiftError.message("You can only remove cars in your garage.") }
        for photo in database.vehiclePhotos where photo.vehicleID == id { removeFile(photo.storagePath) }
        database.vehicles.removeAll { $0.id == id }
        database.vehiclePhotos.removeAll { $0.vehicleID == id }
        database.modifications.removeAll { $0.vehicleID == id }
        database.vehicleLikes.removeAll { $0.vehicleID == id }
        database.vehicleComments.removeAll { $0.vehicleID == id }
        for index in database.attendees.indices where database.attendees[index].vehicleID == id {
            database.attendees[index].vehicleID = nil
        }
        for index in database.posts.indices where database.posts[index].vehicleID == id {
            database.posts[index].vehicleID = nil
        }
        try persist()
        emit(.garage)
    }

    func setVehicleLike(id: UUID, liked: Bool) async throws {
        let me = try requireUser()
        guard database.vehicles.contains(where: { $0.id == id }) else { throw NightshiftError.notFound }
        database.vehicleLikes.removeAll { $0.vehicleID == id && $0.userID == me }
        if liked {
            database.vehicleLikes.append(VehicleLike(vehicleID: id, userID: me, createdAt: Date()))
        }
        try persist()
        emit(.garage)
    }

    func vehicleNotes(id: UUID) async throws -> [ConversationNote] {
        let me = try requireUser()
        return database.vehicleComments
            .filter { $0.vehicleID == id && (!$0.hidden || $0.authorID == me) && !isBlockedEither(me, $0.authorID) }
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap { comment in
                guard let author = database.profiles.first(where: { $0.id == comment.authorID }) else { return nil }
                return ConversationNote(id: comment.id, author: author, content: comment.content, createdAt: comment.createdAt, isMine: comment.authorID == me)
            }
    }

    func addVehicleNote(id: UUID, content: String) async throws {
        let me = try requireUser()
        if let message = Validators.comment(content) { throw NightshiftError.message(message) }
        guard let vehicle = database.vehicles.first(where: { $0.id == id }) else { throw NightshiftError.notFound }
        let note = VehicleComment(id: UUID(), vehicleID: id, authorID: me, content: trimmed(content), createdAt: Date(), hidden: false)
        database.vehicleComments.append(note)
        if vehicle.ownerID != me {
            notify(recipient: vehicle.ownerID, type: .vehicleComment, actor: me, vehicleID: id, commentID: note.id)
        }
        try persist()
        emit(.social)
    }

    func events(filter: EventQuery) async throws -> [EventSummary] {
        let me = try requireUser()
        let subject = filter.subjectID ?? me
        let joinedIDs = Set(database.attendees.filter { $0.userID == subject }.map(\.eventID))
        let rows = database.events.filter { event in
            if isBlockedEither(me, event.hostID) { return false }
            if filter.hostedOnly && event.hostID != subject { return false }
            if filter.joinedOnly && !joinedIDs.contains(event.id) { return false }
            if subject != me {
                guard event.visibility == .public, event.status == .scheduled else { return false }
            } else if !filter.hostedOnly && !filter.joinedOnly {
                guard event.visibility == .public, event.status == .scheduled else { return false }
            }
            if let category = filter.category, event.category != category { return false }
            if let south = filter.south, event.latitude < south { return false }
            if let north = filter.north, event.latitude > north { return false }
            if let west = filter.west, let east = filter.east, west <= east {
                if event.longitude < west || event.longitude > east { return false }
            }
            if let endingAfter = filter.endingAfter, event.endsAt < endingAfter { return false }
            if let startsAfter = filter.startsAfter, event.startsAt < startsAfter { return false }
            if let startsBefore = filter.startsBefore, event.startsAt > startsBefore { return false }
            if let search = filter.search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
                let haystack = "\(event.title) \(event.address)".lowercased()
                if !haystack.contains(search.lowercased()) { return false }
            }
            return true
        }
        let sorted: [Event]
        if filter.hostedOnly || filter.joinedOnly {
            sorted = rows.sorted { $0.startsAt > $1.startsAt }
        } else {
            sorted = rows.sorted { $0.startsAt < $1.startsAt }
        }
        return sorted.prefix(filter.limit).map { summary(for: $0, viewer: me) }
    }

    func event(id: UUID) async throws -> EventDetail {
        let me = try requireUser()
        guard let event = database.events.first(where: { $0.id == id }) else { throw NightshiftError.notFound }
        if isBlockedEither(me, event.hostID) { throw NightshiftError.notFound }
        let isHost = event.hostID == me
        let isAttending = database.attendees.contains { $0.eventID == id && $0.userID == me }
        if event.visibility == .private && !isHost && !isAttending && event.status != .scheduled {
            throw NightshiftError.notFound
        }
        if event.visibility == .public && event.status != .scheduled && !isHost && !isAttending {
            throw NightshiftError.notFound
        }
        guard var host = database.profiles.first(where: { $0.id == event.hostID }) else { throw NightshiftError.notFound }
        if host.id != me && !host.showCity { host.homeCity = nil }
        let attendees: [Attendee] = database.attendees
            .filter { $0.eventID == id && !isBlockedEither(me, $0.userID) }
            .sorted { $0.joinedAt < $1.joinedAt }
            .compactMap { row in
                guard let profile = database.profiles.first(where: { $0.id == row.userID }) else { return nil }
                let vehicle = row.vehicleID.flatMap { vehicleID in database.vehicles.first { $0.id == vehicleID } }
                return Attendee(userID: row.userID, joinedAt: row.joinedAt, profile: profile, vehicle: vehicle)
            }
        let mine = database.attendees.first { $0.eventID == id && $0.userID == me }
        return EventDetail(
            event: event,
            host: host,
            attendees: attendees,
            attendeeCount: database.attendees.filter { $0.eventID == id }.count,
            joined: mine != nil,
            myVehicleID: mine?.vehicleID
        )
    }

    func saveEvent(_ draft: EventDraft, existingID: UUID?) async throws -> Event {
        let me = try requireUser()
        if let message = Validators.event(draft, editing: existingID != nil) { throw NightshiftError.message(message) }
        let id = existingID ?? UUID()
        let createdAt: Date
        let status: EventStatus
        var cover = draft.existingCoverPath
        if let existingID {
            guard let current = database.events.first(where: { $0.id == existingID }) else { throw NightshiftError.notFound }
            guard current.hostID == me else { throw NightshiftError.message("You can only edit meets you host.") }
            createdAt = current.createdAt
            status = current.status
            if cover == nil { cover = current.coverImagePath }
        } else {
            createdAt = Date()
            status = .scheduled
        }
        if let data = draft.coverData {
            cover = try await storeImage(data)
        }
        guard let latitude = draft.latitude, let longitude = draft.longitude else {
            throw NightshiftError.message("Set a location before publishing.")
        }
        let event = Event(
            id: id,
            hostID: me,
            title: trimmed(draft.title),
            description: trimmed(draft.description),
            rules: trimmed(draft.rules),
            latitude: latitude,
            longitude: longitude,
            address: trimmed(draft.address),
            startsAt: draft.startsAt,
            endsAt: draft.endsAt,
            category: draft.category,
            capacity: draft.limitsCapacity ? draft.capacity : nil,
            visibility: draft.visibility,
            coverImagePath: cover,
            status: status,
            createdAt: createdAt
        )
        if let index = database.events.firstIndex(where: { $0.id == id }) {
            database.events[index] = event
        } else {
            database.events.append(event)
        }
        try persist()
        emit(.events)
        return event
    }

    func cancelEvent(id: UUID) async throws {
        let me = try requireUser()
        guard let index = database.events.firstIndex(where: { $0.id == id }) else { throw NightshiftError.notFound }
        guard database.events[index].hostID == me else { throw NightshiftError.message("You can only cancel meets you host.") }
        database.events[index].status = .cancelled
        try persist()
        emit(.events)
    }

    func joinEvent(id: UUID, vehicleID: UUID?) async throws {
        let me = try requireUser()
        guard let event = database.events.first(where: { $0.id == id }) else { throw NightshiftError.notFound }
        if isBlockedEither(me, event.hostID) { throw NightshiftError.notFound }
        if let vehicleID, !database.vehicles.contains(where: { $0.id == vehicleID && $0.ownerID == me }) {
            throw NightshiftError.message("That car is not in your garage.")
        }
        if let index = database.attendees.firstIndex(where: { $0.eventID == id && $0.userID == me }) {
            guard event.status == .scheduled else { throw NightshiftError.message("This meet is no longer open.") }
            database.attendees[index].vehicleID = vehicleID
            try persist()
            emit(.events)
            return
        }
        guard event.status == .scheduled else { throw NightshiftError.message("This meet is no longer open.") }
        guard event.endsAt >= Date() else { throw NightshiftError.message("This meet has ended.") }
        let count = database.attendees.filter { $0.eventID == id }.count
        if let capacity = event.capacity, count >= capacity {
            throw NightshiftError.message("This meet is full.")
        }
        database.attendees.append(Attendance(id: UUID(), eventID: id, userID: me, vehicleID: vehicleID, joinedAt: Date()))
        if event.hostID != me {
            notify(recipient: event.hostID, type: .eventJoin, actor: me, eventID: id)
        }
        try persist()
        emit(.events)
    }

    func leaveEvent(id: UUID) async throws {
        let me = try requireUser()
        let before = database.attendees.count
        database.attendees.removeAll { $0.eventID == id && $0.userID == me }
        guard database.attendees.count != before else { return }
        try persist()
        emit(.events)
    }

    func posts(authorID: UUID?, before: Date?, limit: Int) async throws -> [PostItem] {
        let me = try requireUser()
        return database.posts
            .filter { post in
                if let authorID, post.authorID != authorID { return false }
                if let before, post.createdAt >= before { return false }
                if post.hidden && post.authorID != me { return false }
                if isBlockedEither(me, post.authorID) { return false }
                return true
            }
            .sorted { $0.createdAt > $1.createdAt }
            .prefix(limit)
            .compactMap { postItem($0, viewer: me) }
    }

    func post(id: UUID) async throws -> PostItem {
        let me = try requireUser()
        guard let post = database.posts.first(where: { $0.id == id }) else { throw NightshiftError.notFound }
        if isBlockedEither(me, post.authorID) { throw NightshiftError.notFound }
        if post.hidden && post.authorID != me { throw NightshiftError.notFound }
        guard let item = postItem(post, viewer: me) else { throw NightshiftError.notFound }
        return item
    }

    func createPost(_ draft: PostDraft) async throws -> Post {
        let me = try requireUser()
        if let message = Validators.post(caption: draft.caption, hasImage: !draft.photos.isEmpty) {
            throw NightshiftError.message(message)
        }
        if let vehicleID = draft.vehicleID, !database.vehicles.contains(where: { $0.id == vehicleID && $0.ownerID == me }) {
            throw NightshiftError.message("That car is not in your garage.")
        }
        let post = Post(id: UUID(), authorID: me, vehicleID: draft.vehicleID, caption: trimmed(draft.caption), createdAt: Date(), hidden: false)
        database.posts.append(post)
        for (index, upload) in draft.photos.enumerated() {
            let path: String
            switch upload.source {
            case .existing(let existing): path = existing
            case .new(let data): path = try await storeImage(data)
            }
            database.postImages.append(PostImage(id: UUID(), postID: post.id, storagePath: path, sortOrder: index))
        }
        try persist()
        emit(.social)
        return post
    }

    func deletePost(id: UUID) async throws {
        let me = try requireUser()
        guard let post = database.posts.first(where: { $0.id == id }) else { throw NightshiftError.notFound }
        guard post.authorID == me else { throw NightshiftError.message("You can only delete your own posts.") }
        for image in database.postImages where image.postID == id { removeFile(image.storagePath) }
        database.posts.removeAll { $0.id == id }
        database.postImages.removeAll { $0.postID == id }
        database.postLikes.removeAll { $0.postID == id }
        database.comments.removeAll { $0.postID == id }
        try persist()
        emit(.social)
    }

    func setPostLike(id: UUID, liked: Bool) async throws {
        let me = try requireUser()
        guard let post = database.posts.first(where: { $0.id == id }) else { throw NightshiftError.notFound }
        let already = database.postLikes.contains { $0.postID == id && $0.userID == me }
        database.postLikes.removeAll { $0.postID == id && $0.userID == me }
        if liked {
            database.postLikes.append(PostLike(postID: id, userID: me, createdAt: Date()))
            if !already && post.authorID != me {
                notify(recipient: post.authorID, type: .like, actor: me, postID: id)
            }
        }
        try persist()
        emit(.social)
    }

    func notes(postID: UUID) async throws -> [ConversationNote] {
        let me = try requireUser()
        return database.comments
            .filter { $0.postID == postID && (!$0.hidden || $0.authorID == me) && !isBlockedEither(me, $0.authorID) }
            .sorted { $0.createdAt < $1.createdAt }
            .compactMap { comment in
                guard let author = database.profiles.first(where: { $0.id == comment.authorID }) else { return nil }
                return ConversationNote(id: comment.id, author: author, content: comment.content, createdAt: comment.createdAt, isMine: author.id == me)
            }
    }

    func addNote(postID: UUID, content: String) async throws {
        let me = try requireUser()
        if let message = Validators.comment(content) { throw NightshiftError.message(message) }
        guard let post = database.posts.first(where: { $0.id == postID }) else { throw NightshiftError.notFound }
        let note = Comment(id: UUID(), postID: postID, authorID: me, content: trimmed(content), createdAt: Date(), hidden: false)
        database.comments.append(note)
        if post.authorID != me {
            notify(recipient: post.authorID, type: .comment, actor: me, postID: postID, commentID: note.id)
        }
        try persist()
        emit(.social)
    }

    func deleteNote(id: UUID) async throws {
        let me = try requireUser()
        guard let comment = database.comments.first(where: { $0.id == id }) else { throw NightshiftError.notFound }
        guard comment.authorID == me else { throw NightshiftError.message("You can only delete your own comments.") }
        database.comments.removeAll { $0.id == id }
        try persist()
        emit(.social)
    }

    func setFollowing(userID: UUID, following: Bool) async throws {
        let me = try requireUser()
        guard userID != me else { throw NightshiftError.message("You can't follow yourself.") }
        guard database.profiles.contains(where: { $0.id == userID }) else { throw NightshiftError.notFound }
        if isBlockedEither(me, userID) { throw NightshiftError.message("That driver isn't available.") }
        database.follows.removeAll { $0.followerID == me && $0.followingID == userID }
        if following {
            database.follows.append(Follow(followerID: me, followingID: userID, createdAt: Date()))
            notify(recipient: userID, type: .follow, actor: me)
        }
        try persist()
        emit(.profile)
    }

    func followers(of userID: UUID) async throws -> [Profile] {
        let me = try requireUser()
        return database.follows
            .filter { $0.followingID == userID }
            .compactMap { follow in database.profiles.first { $0.id == follow.followerID && !isBlockedEither(me, follow.followerID) } }
    }

    func following(of userID: UUID) async throws -> [Profile] {
        let me = try requireUser()
        return database.follows
            .filter { $0.followerID == userID }
            .compactMap { follow in database.profiles.first { $0.id == follow.followingID && !isBlockedEither(me, follow.followingID) } }
    }

    func report(target: ReportTarget, targetID: UUID, reason: String) async throws {
        let me = try requireUser()
        if let message = Validators.reportReason(reason) { throw NightshiftError.message(message) }
        if database.reports.contains(where: { $0.reporterID == me && $0.targetType == target && $0.targetID == targetID }) {
            throw NightshiftError.message("You already reported this.")
        }
        database.reports.append(Report(id: UUID(), reporterID: me, targetType: target, targetID: targetID, reason: trimmed(reason), createdAt: Date()))
        try persist()
    }

    func reportsFiled() async throws -> [Report] {
        let me = try requireUser()
        return database.reports.filter { $0.reporterID == me }.sorted { $0.createdAt > $1.createdAt }
    }

    func setBlocked(userID: UUID, blocked: Bool) async throws {
        let me = try requireUser()
        guard userID != me else { throw NightshiftError.message("You can't block yourself.") }
        database.blocks.removeAll { $0.blockerID == me && $0.blockedID == userID }
        if blocked {
            database.blocks.append(Block(blockerID: me, blockedID: userID, createdAt: Date()))
            database.follows.removeAll { ($0.followerID == me && $0.followingID == userID) || ($0.followerID == userID && $0.followingID == me) }
        }
        try persist()
        emit(.social)
    }

    func blockedUsers() async throws -> [Profile] {
        let me = try requireUser()
        return database.blocks
            .filter { $0.blockerID == me }
            .compactMap { block in database.profiles.first { $0.id == block.blockedID } }
    }

    func notifications() async throws -> [AppNotification] {
        let me = try requireUser()
        return database.notifications.filter { $0.recipientID == me }.sorted { $0.createdAt > $1.createdAt }
    }

    func unreadNotificationCount() async throws -> Int {
        let me = try requireUser()
        return database.notifications.filter { $0.recipientID == me && $0.readAt == nil }.count
    }

    func markNotificationsRead() async throws {
        let me = try requireUser()
        var changed = false
        for index in database.notifications.indices where database.notifications[index].recipientID == me && database.notifications[index].readAt == nil {
            database.notifications[index].readAt = Date()
            changed = true
        }
        if changed { try persist() }
    }

    func imageData(storagePath: String, thumbnail: Bool) async throws -> Data {
        let path = thumbnail ? MediaPath.thumbnail(for: storagePath) : storagePath
        if let data = readFile(path) { return data }
        if thumbnail, let data = readFile(storagePath) { return data }
        throw NightshiftError.notFound
    }

    nonisolated func changes() -> AsyncStream<ChangeSignal> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.addSubscriber(id, continuation) }
            continuation.onTermination = { _ in
                Task { await self.removeSubscriber(id) }
            }
        }
    }

    private func addSubscriber(_ id: UUID, _ continuation: AsyncStream<ChangeSignal>.Continuation) {
        subscribers[id] = continuation
    }

    private func removeSubscriber(_ id: UUID) {
        subscribers[id] = nil
    }

    private func emit(_ signal: ChangeSignal) {
        for continuation in subscribers.values {
            continuation.yield(signal)
        }
    }

    private var storeURL: URL { directory.appendingPathComponent("store.json") }
    private var sessionURL: URL { directory.appendingPathComponent("session.txt") }

    private func persist() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONCoding.encoder.encode(database)
        try data.write(to: storeURL, options: .atomic)
    }

    private func readSession() -> UUID? {
        guard let raw = try? String(contentsOf: sessionURL, encoding: .utf8) else { return nil }
        return UUID(uuidString: raw.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func writeSession(_ id: UUID) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try id.uuidString.write(to: sessionURL, atomically: true, encoding: .utf8)
    }

    private func requireUser() throws -> UUID {
        guard let id = readSession(), database.profiles.contains(where: { $0.id == id }) else {
            throw NightshiftError.notSignedIn
        }
        return id
    }

    private func validateCredentials(email: String, password: String, username: String, displayName: String) throws {
        if let message = Validators.email(email) { throw NightshiftError.message(message) }
        if let message = Validators.password(password) { throw NightshiftError.message(message) }
        if let message = Validators.username(username) { throw NightshiftError.message(message) }
        if let message = Validators.displayName(displayName) { throw NightshiftError.message(message) }
    }

    private func normalizeEmail(_ email: String) -> String {
        email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func normalizeUsername(_ username: String) -> String {
        username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    private func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func blankToNil(_ value: String) -> String? {
        let value = trimmed(value)
        return value.isEmpty ? nil : value
    }

    private func uniqueUsername(_ preferred: String) -> String {
        var candidate = preferred
        var suffix = 1
        while database.profiles.contains(where: { $0.username == candidate }) {
            candidate = String(preferred.prefix(14)) + "\(suffix)"
            suffix += 1
        }
        return candidate
    }

    private func formatted(_ name: PersonNameComponents?) -> String? {
        guard let name else { return nil }
        let formatted = PersonNameComponentsFormatter().string(from: name).trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }

    private func blocked(by blocker: UUID, other: UUID) -> Bool {
        database.blocks.contains { $0.blockerID == blocker && $0.blockedID == other }
    }

    private func isBlockedEither(_ a: UUID, _ b: UUID) -> Bool {
        a != b && (blocked(by: a, other: b) || blocked(by: b, other: a))
    }

    private func uploadProfileImage(_ data: Data, isCover: Bool) async throws -> Profile {
        let me = try requireUser()
        guard let index = database.profiles.firstIndex(where: { $0.id == me }) else { throw NightshiftError.notFound }
        let path = try await storeImage(data)
        if isCover {
            database.profiles[index].coverURL = path
        } else {
            database.profiles[index].avatarURL = path
        }
        try persist()
        emit(.profile)
        return database.profiles[index]
    }

    private func replaceVehiclePhotos(vehicleID: UUID, uploads: [PhotoUpload]) async throws {
        var kept: [VehiclePhoto] = []
        for (index, upload) in uploads.enumerated() {
            switch upload.source {
            case .existing(let path):
                let created = database.vehiclePhotos.first { $0.vehicleID == vehicleID && $0.storagePath == path }?.createdAt ?? Date()
                kept.append(VehiclePhoto(id: UUID(), vehicleID: vehicleID, storagePath: path, sortOrder: index, createdAt: created))
            case .new(let data):
                let path = try await storeImage(data)
                kept.append(VehiclePhoto(id: UUID(), vehicleID: vehicleID, storagePath: path, sortOrder: index, createdAt: Date()))
            }
        }
        database.vehiclePhotos.removeAll { $0.vehicleID == vehicleID }
        database.vehiclePhotos.append(contentsOf: kept)
    }

    private func storeImage(_ data: Data) async throws -> String {
        let full = await ImageEncoder.jpeg(data, maxDimension: 1600, quality: 0.82)
        let thumb = await ImageEncoder.jpeg(data, maxDimension: 480, quality: 0.72)
        guard let full, let thumb else { throw NightshiftError.message("That photo couldn't be prepared.") }
        let folder = directory.appendingPathComponent("media", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = UUID().uuidString
        try full.write(to: folder.appendingPathComponent("\(name).jpg"), options: .atomic)
        try thumb.write(to: folder.appendingPathComponent("\(name)_thumb.jpg"), options: .atomic)
        return "local:media/\(name).jpg"
    }

    private func readFile(_ storagePath: String) -> Data? {
        guard let relative = MediaPath.localRelative(storagePath) else { return nil }
        return try? Data(contentsOf: directory.appendingPathComponent(relative))
    }

    private func removeFile(_ storagePath: String) {
        guard let relative = MediaPath.localRelative(storagePath) else { return }
        try? FileManager.default.removeItem(at: directory.appendingPathComponent(relative))
        if let thumb = MediaPath.localRelative(MediaPath.thumbnail(for: storagePath)) {
            try? FileManager.default.removeItem(at: directory.appendingPathComponent(thumb))
        }
    }

    private func vehicleSummary(_ vehicle: Vehicle) -> VehicleSummary {
        let photos = database.vehiclePhotos.filter { $0.vehicleID == vehicle.id }.sorted { $0.sortOrder < $1.sortOrder }
        return VehicleSummary(vehicle: vehicle, coverPath: photos.first?.storagePath, photoCount: photos.count)
    }

    private func summary(for event: Event, viewer: UUID) -> EventSummary {
        let host = database.profiles.first { $0.id == event.hostID }
        return EventSummary(
            event: event,
            attendeeCount: database.attendees.filter { $0.eventID == event.id }.count,
            joined: database.attendees.contains { $0.eventID == event.id && $0.userID == viewer },
            hostDisplayName: host?.displayName ?? "Driver",
            hostUsername: host?.username ?? "driver"
        )
    }

    private func postItem(_ post: Post, viewer: UUID) -> PostItem? {
        guard let author = database.profiles.first(where: { $0.id == post.authorID }) else { return nil }
        let vehicle = post.vehicleID.flatMap { id in database.vehicles.first { $0.id == id } }
        let images = database.postImages.filter { $0.postID == post.id }.sorted { $0.sortOrder < $1.sortOrder }
        return PostItem(
            post: post,
            author: author,
            vehicle: vehicle,
            images: images,
            likeCount: database.postLikes.filter { $0.postID == post.id }.count,
            commentCount: database.comments.filter { $0.postID == post.id && !$0.hidden }.count,
            likedByMe: database.postLikes.contains { $0.postID == post.id && $0.userID == viewer }
        )
    }

    private func notify(
        recipient: UUID,
        type: NotificationKind,
        actor: UUID,
        postID: UUID? = nil,
        eventID: UUID? = nil,
        vehicleID: UUID? = nil,
        commentID: UUID? = nil
    ) {
        let name = database.profiles.first { $0.id == actor }?.displayName
        database.notifications.append(AppNotification(
            id: UUID(),
            recipientID: recipient,
            type: type,
            payload: NotificationPayload(actorID: actor, actorName: name, postID: postID, eventID: eventID, vehicleID: vehicleID, commentID: commentID),
            readAt: nil,
            createdAt: Date()
        ))
    }
}
