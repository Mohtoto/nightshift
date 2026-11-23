import Foundation
import Supabase

final class SupabaseRepository: NightshiftRepository, Sendable {
    private let client: SupabaseClient
    private let hub = SignalHub()
    private let gate = RealtimeGate()

    init(client: SupabaseClient) {
        self.client = client
    }

    func restoreSession() async throws -> Profile? {
        guard let id = client.auth.currentSession?.user.id else { return nil }
        return try await profileRow(id)
    }

    func signUp(email: String, password: String, username: String, displayName: String) async throws -> AuthOutcome {
        try validateCredentials(email: email, password: password, username: username, displayName: displayName)
        let response = try await client.auth.signUp(
            email: normalizeEmail(email),
            password: password,
            data: [
                "username": AnyJSON.string(normalizeUsername(username)),
                "display_name": AnyJSON.string(displayName.trimmingCharacters(in: .whitespacesAndNewlines))
            ]
        )
        guard let session = response.session else { return .confirmationRequired }
        return .signedIn(try await profileRow(session.user.id))
    }

    func signIn(email: String, password: String) async throws -> Profile {
        let session = try await client.auth.signIn(email: normalizeEmail(email), password: password)
        return try await profileRow(session.user.id)
    }

    func signInWithApple(userID: String, idToken: String?, nonce: String, fullName: PersonNameComponents?) async throws -> Profile {
        guard let idToken else { throw NightshiftError.message("Apple didn't return an identity token.") }
        let session = try await client.auth.signInWithIdToken(
            credentials: OpenIDConnectCredentials(provider: .apple, idToken: idToken, nonce: nonce)
        )
        var profile = try await profileRow(session.user.id)
        if profile.displayName == "Driver", let name = formatted(fullName) {
            profile.displayName = name
            profile = try await updateProfile(profile)
        }
        return profile
    }

    func requestPasswordReset(email: String) async throws {
        if let message = Validators.email(email) { throw NightshiftError.message(message) }
        try await client.auth.resetPasswordForEmail(normalizeEmail(email))
    }

    func setPassword(email: String, newPassword: String) async throws {
        throw NightshiftError.message("Use the link in your reset email to choose a new password.")
    }

    func signOut() async throws {
        try await client.auth.signOut()
    }

    func deleteAccount() async throws {
        _ = try requireUser()
        try await client.rpc("delete_own_account").execute()
        try? await client.auth.signOut()
        await hub.emit(.profile)
    }

    func profile(id: UUID) async throws -> ProfileCard {
        let me = try requireUser()
        var row = try await profileRow(id)
        let blockedByMe = try await didBlock(me, other: id)
        let eitherBlocked = id == me ? false : try await eitherBlock(me, id)
        if id != me && eitherBlocked && !blockedByMe { throw NightshiftError.notFound }
        if id != me && !row.showCity { row.homeCity = nil }
        async let followers = count("follows", column: "following_id", value: id)
        async let following = count("follows", column: "follower_id", value: id)
        let followed: Bool
        if id == me {
            followed = false
        } else {
            let rows: [Follow] = try await client.from("follows").select()
                .eq("follower_id", value: me)
                .eq("following_id", value: id)
                .limit(1)
                .execute()
                .value
            followed = !rows.isEmpty
        }
        return ProfileCard(
            profile: row,
            followerCount: try await followers,
            followingCount: try await following,
            isFollowedByMe: followed,
            isBlockedByMe: blockedByMe
        )
    }

    func updateProfile(_ profile: Profile) async throws -> Profile {
        let me = try requireUser()
        guard profile.id == me else { throw NightshiftError.message("You can only edit your profile.") }
        if let message = Validators.username(profile.username) { throw NightshiftError.message(message) }
        if let message = Validators.displayName(profile.displayName) { throw NightshiftError.message(message) }
        if let message = Validators.bio(profile.bio) { throw NightshiftError.message(message) }
        let write = ProfileWrite(profile: profile)
        let rows: [Profile] = try await client.from("profiles").update(write).eq("id", value: me).select().execute().value
        guard let updated = rows.first else { throw NightshiftError.notFound }
        await hub.emit(.profile)
        return updated
    }

    func uploadAvatar(_ data: Data) async throws -> Profile {
        try await uploadProfileImage(data, bucket: "avatars", column: "avatar_url")
    }

    func uploadCover(_ data: Data) async throws -> Profile {
        try await uploadProfileImage(data, bucket: "covers", column: "cover_url")
    }

    func vehicles(ownerID: UUID) async throws -> [VehicleSummary] {
        _ = try requireUser()
        let vehicles: [Vehicle] = try await client.from("vehicles").select()
            .eq("owner_id", value: ownerID)
            .order("created_at", ascending: false)
            .execute()
            .value
        return try await summaries(for: vehicles)
    }

    func vehicle(id: UUID) async throws -> VehicleDetail {
        let me = try requireUser()
        let vehicles: [Vehicle] = try await client.from("vehicles").select().eq("id", value: id).limit(1).execute().value
        guard let vehicle = vehicles.first else { throw NightshiftError.notFound }
        var owner = try await profileRow(vehicle.ownerID)
        if owner.id != me && !owner.showCity { owner.homeCity = nil }
        async let photos: [VehiclePhoto] = client.from("vehicle_photos").select().eq("vehicle_id", value: id).order("sort_order").execute().value
        async let mods: [VehicleModification] = client.from("vehicle_modifications").select().eq("vehicle_id", value: id).execute().value
        async let likes: [VehicleLike] = client.from("vehicle_likes").select().eq("vehicle_id", value: id).execute().value
        async let notes: [VehicleComment] = client.from("vehicle_comments").select().eq("vehicle_id", value: id).execute().value
        let attendance: [Attendance] = try await client.from("event_attendees").select()
            .eq("vehicle_id", value: id)
            .execute()
            .value
        let eventIDs = attendance.map(\.eventID)
        let meets: [EventSummary]
        if eventIDs.isEmpty {
            meets = []
        } else {
            let cards: [EventCardRow] = try await client.from("event_cards").select().in("id", values: eventIDs).execute().value
            let joined = Set(try await myEventIDs())
            meets = cards.map { $0.summary(joined: joined.contains($0.event.id)) }
        }
        let likeRows = try await likes
        return VehicleDetail(
            vehicle: vehicle,
            photos: try await photos.sorted { $0.sortOrder < $1.sortOrder },
            modifications: try await mods,
            owner: owner,
            likeCount: likeRows.count,
            likedByMe: likeRows.contains { $0.userID == me },
            commentCount: try await notes.filter { !$0.hidden }.count,
            attendedMeets: meets
        )
    }

    func saveVehicle(_ draft: VehicleDraft, existingID: UUID?) async throws -> Vehicle {
        let me = try requireUser()
        if let message = Validators.vehicle(draft) { throw NightshiftError.message(message) }
        let id = existingID ?? UUID()
        if let existingID {
            let current: [Vehicle] = try await client.from("vehicles").select().eq("id", value: existingID).limit(1).execute().value
            guard let vehicle = current.first, vehicle.ownerID == me else {
                throw NightshiftError.message("You can only edit cars in your garage.")
            }
        }
        let record = Vehicle(
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
            createdAt: Date()
        )
        let saved: [Vehicle]
        if existingID == nil {
            saved = try await client.from("vehicles").insert(record).select().execute().value
        } else {
            saved = try await client.from("vehicles").update(VehicleWrite(record)).eq("id", value: id).select().execute().value
        }
        guard let vehicle = saved.first else { throw NightshiftError.message("The car couldn't be saved.") }
        try await replaceVehiclePhotos(vehicleID: id, uploads: draft.photos)
        try await client.from("vehicle_modifications").delete().eq("vehicle_id", value: id).execute()
        if !draft.modifications.isEmpty {
            let rows = draft.modifications.map {
                VehicleModification(
                    id: UUID(),
                    vehicleID: id,
                    category: trimmed($0.category).isEmpty ? "Other" : trimmed($0.category),
                    name: trimmed($0.name),
                    description: trimmed($0.description)
                )
            }
            try await client.from("vehicle_modifications").insert(rows).execute()
        }
        await hub.emit(.garage)
        return vehicle
    }

    func deleteVehicle(id: UUID) async throws {
        _ = try requireUser()
        try await client.from("vehicles").delete().eq("id", value: id).execute()
        await hub.emit(.garage)
    }

    func setVehicleLike(id: UUID, liked: Bool) async throws {
        let me = try requireUser()
        try await client.from("vehicle_likes").delete().eq("vehicle_id", value: id).eq("user_id", value: me).execute()
        if liked {
            try await client.from("vehicle_likes").insert(VehicleLike(vehicleID: id, userID: me, createdAt: Date())).execute()
        }
        await hub.emit(.garage)
    }

    func vehicleNotes(id: UUID) async throws -> [ConversationNote] {
        let me = try requireUser()
        let notes: [VehicleComment] = try await client.from("vehicle_comments").select()
            .eq("vehicle_id", value: id)
            .order("created_at")
            .execute()
            .value
        return try await conversation(notes.map { ($0.id, $0.authorID, $0.content, $0.createdAt) }, viewer: me)
    }

    func addVehicleNote(id: UUID, content: String) async throws {
        let me = try requireUser()
        if let message = Validators.comment(content) { throw NightshiftError.message(message) }
        let note = VehicleComment(id: UUID(), vehicleID: id, authorID: me, content: trimmed(content), createdAt: Date(), hidden: false)
        try await client.from("vehicle_comments").insert(note).execute()
        await hub.emit(.social)
    }

    func events(filter: EventQuery) async throws -> [EventSummary] {
        let me = try requireUser()
        var query = client.from("event_cards").select()
        let subject = filter.subjectID ?? me
        if filter.hostedOnly {
            query = query.eq("host_id", value: subject)
        }
        if filter.subjectID != nil && filter.subjectID != me {
            query = query.eq("visibility", value: "public").eq("status", value: "scheduled")
        }
        if let category = filter.category {
            query = query.eq("category", value: category.rawValue)
        }
        if let south = filter.south { query = query.gte("latitude", value: south) }
        if let north = filter.north { query = query.lte("latitude", value: north) }
        if let west = filter.west, let east = filter.east, west <= east {
            query = query.gte("longitude", value: west).lte("longitude", value: east)
        }
        if let endingAfter = filter.endingAfter {
            query = query.gte("ends_at", value: JSONCoding.isoString(from:  endingAfter))
        }
        if let startsAfter = filter.startsAfter {
            query = query.gte("starts_at", value: JSONCoding.isoString(from:  startsAfter))
        }
        if let startsBefore = filter.startsBefore {
            query = query.lte("starts_at", value: JSONCoding.isoString(from:  startsBefore))
        }
        if let search = filter.search?.trimmingCharacters(in: .whitespacesAndNewlines), !search.isEmpty {
            let cleaned = search.replacingOccurrences(of: "%", with: "").replacingOccurrences(of: ",", with: " ")
            query = query.or("title.ilike.%\(cleaned)%,address.ilike.%\(cleaned)%")
        }
        if filter.joinedOnly {
            let ids = try await eventIDs(for: subject)
            if ids.isEmpty { return [] }
            query = query.in("id", values: ids)
        }
        let rows: [EventCardRow] = try await query
            .order("starts_at", ascending: !(filter.joinedOnly || filter.hostedOnly))
            .limit(filter.limit)
            .execute()
            .value
        let joined = Set(try await myEventIDs())
        return rows.map { $0.summary(joined: joined.contains($0.event.id)) }
    }

    func event(id: UUID) async throws -> EventDetail {
        _ = try requireUser()
        let detail: EventDetail = try await client.rpc("event_detail", params: IDParams(target: id)).execute().value
        return detail
    }

    func saveEvent(_ draft: EventDraft, existingID: UUID?) async throws -> Event {
        let me = try requireUser()
        if let message = Validators.event(draft, editing: existingID != nil) { throw NightshiftError.message(message) }
        guard let latitude = draft.latitude, let longitude = draft.longitude else {
            throw NightshiftError.message("Set a location before publishing.")
        }
        let id = existingID ?? UUID()
        var cover = draft.existingCoverPath
        if let data = draft.coverData {
            cover = try await uploadImage(data, bucket: "event-covers")
        }
        if existingID != nil {
            let current: [Event] = try await client.from("events").select().eq("id", value: id).limit(1).execute().value
            guard let event = current.first, event.hostID == me else {
                throw NightshiftError.message("You can only edit meets you host.")
            }
            if cover == nil { cover = event.coverImagePath }
        }
        let record = Event(
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
            status: .scheduled,
            createdAt: Date()
        )
        let saved: [Event]
        if existingID == nil {
            saved = try await client.from("events").insert(record).select().execute().value
        } else {
            saved = try await client.from("events").update(EventWrite(record)).eq("id", value: id).select().execute().value
        }
        guard let event = saved.first else { throw NightshiftError.message("The meet couldn't be saved.") }
        await hub.emit(.events)
        return event
    }

    func cancelEvent(id: UUID) async throws {
        _ = try requireUser()
        try await client.from("events").update(StatusWrite(status: .cancelled)).eq("id", value: id).execute()
        await hub.emit(.events)
    }

    func joinEvent(id: UUID, vehicleID: UUID?) async throws {
        _ = try requireUser()
        try await client.rpc("join_event", params: JoinParams(target: id, car: vehicleID)).execute()
        await hub.emit(.events)
    }

    func leaveEvent(id: UUID) async throws {
        let me = try requireUser()
        try await client.from("event_attendees").delete().eq("event_id", value: id).eq("user_id", value: me).execute()
        await hub.emit(.events)
    }

    func posts(authorID: UUID?, before: Date?, limit: Int) async throws -> [PostItem] {
        let me = try requireUser()
        var query = client.from("post_cards").select()
        if let authorID { query = query.eq("author_id", value: authorID) }
        if let before { query = query.lt("created_at", value: JSONCoding.isoString(from:  before)) }
        let rows: [PostCardRow] = try await query.order("created_at", ascending: false).limit(limit).execute().value
        return try await assemble(rows, viewer: me)
    }

    func post(id: UUID) async throws -> PostItem {
        let me = try requireUser()
        let rows: [PostCardRow] = try await client.from("post_cards").select().eq("id", value: id).limit(1).execute().value
        guard let row = rows.first, let item = try await assemble([row], viewer: me).first else { throw NightshiftError.notFound }
        return item
    }

    func createPost(_ draft: PostDraft) async throws -> Post {
        let me = try requireUser()
        if let message = Validators.post(caption: draft.caption, hasImage: !draft.photos.isEmpty) {
            throw NightshiftError.message(message)
        }
        let post = Post(id: UUID(), authorID: me, vehicleID: draft.vehicleID, caption: trimmed(draft.caption), createdAt: Date(), hidden: false)
        let saved: [Post] = try await client.from("posts").insert(post).select().execute().value
        guard let created = saved.first else { throw NightshiftError.message("The post couldn't be published.") }
        if !draft.photos.isEmpty {
            var images: [PostImage] = []
            for (index, upload) in draft.photos.enumerated() {
                let path: String
                switch upload.source {
                case .existing(let existing): path = existing
                case .new(let data): path = try await uploadImage(data, bucket: "post-images")
                }
                images.append(PostImage(id: UUID(), postID: created.id, storagePath: path, sortOrder: index))
            }
            try await client.from("post_images").insert(images).execute()
        }
        await hub.emit(.social)
        return created
    }

    func deletePost(id: UUID) async throws {
        _ = try requireUser()
        try await client.from("posts").delete().eq("id", value: id).execute()
        await hub.emit(.social)
    }

    func setPostLike(id: UUID, liked: Bool) async throws {
        let me = try requireUser()
        try await client.from("post_likes").delete().eq("post_id", value: id).eq("user_id", value: me).execute()
        if liked {
            try await client.from("post_likes").insert(PostLike(postID: id, userID: me, createdAt: Date())).execute()
        }
        await hub.emit(.social)
    }

    func notes(postID: UUID) async throws -> [ConversationNote] {
        let me = try requireUser()
        let notes: [Comment] = try await client.from("comments").select().eq("post_id", value: postID).order("created_at").execute().value
        return try await conversation(notes.map { ($0.id, $0.authorID, $0.content, $0.createdAt) }, viewer: me)
    }

    func addNote(postID: UUID, content: String) async throws {
        let me = try requireUser()
        if let message = Validators.comment(content) { throw NightshiftError.message(message) }
        let note = Comment(id: UUID(), postID: postID, authorID: me, content: trimmed(content), createdAt: Date(), hidden: false)
        try await client.from("comments").insert(note).execute()
        await hub.emit(.social)
    }

    func deleteNote(id: UUID) async throws {
        _ = try requireUser()
        try await client.from("comments").delete().eq("id", value: id).execute()
        await hub.emit(.social)
    }

    func setFollowing(userID: UUID, following: Bool) async throws {
        let me = try requireUser()
        guard userID != me else { throw NightshiftError.message("You can't follow yourself.") }
        try await client.from("follows").delete().eq("follower_id", value: me).eq("following_id", value: userID).execute()
        if following {
            try await client.from("follows").insert(Follow(followerID: me, followingID: userID, createdAt: Date())).execute()
        }
        await hub.emit(.profile)
    }

    func followers(of userID: UUID) async throws -> [Profile] {
        _ = try requireUser()
        let links: [Follow] = try await client.from("follows").select().eq("following_id", value: userID).execute().value
        return try await profiles(ids: links.map(\.followerID))
    }

    func following(of userID: UUID) async throws -> [Profile] {
        _ = try requireUser()
        let links: [Follow] = try await client.from("follows").select().eq("follower_id", value: userID).execute().value
        return try await profiles(ids: links.map(\.followingID))
    }

    func report(target: ReportTarget, targetID: UUID, reason: String) async throws {
        let me = try requireUser()
        if let message = Validators.reportReason(reason) { throw NightshiftError.message(message) }
        let report = Report(id: UUID(), reporterID: me, targetType: target, targetID: targetID, reason: trimmed(reason), createdAt: Date())
        try await client.from("reports").insert(report).execute()
    }

    func reportsFiled() async throws -> [Report] {
        let me = try requireUser()
        let rows: [Report] = try await client.from("reports").select().eq("reporter_id", value: me).order("created_at", ascending: false).execute().value
        return rows
    }

    func setBlocked(userID: UUID, blocked: Bool) async throws {
        let me = try requireUser()
        guard userID != me else { throw NightshiftError.message("You can't block yourself.") }
        try await client.from("blocks").delete().eq("blocker_id", value: me).eq("blocked_id", value: userID).execute()
        if blocked {
            try await client.from("blocks").insert(Block(blockerID: me, blockedID: userID, createdAt: Date())).execute()
            try await client.from("follows").delete().eq("follower_id", value: me).eq("following_id", value: userID).execute()
            try await client.from("follows").delete().eq("follower_id", value: userID).eq("following_id", value: me).execute()
        }
        await hub.emit(.social)
    }

    func blockedUsers() async throws -> [Profile] {
        let me = try requireUser()
        let rows: [Block] = try await client.from("blocks").select().eq("blocker_id", value: me).execute().value
        return try await profiles(ids: rows.map(\.blockedID))
    }

    func notifications() async throws -> [AppNotification] {
        let me = try requireUser()
        let rows: [AppNotification] = try await client.from("notifications").select()
            .eq("recipient_id", value: me)
            .order("created_at", ascending: false)
            .limit(80)
            .execute()
            .value
        return rows
    }

    func unreadNotificationCount() async throws -> Int {
        let me = try requireUser()
        let response = try await client.from("notifications").select("id", head: true, count: .exact)
            .eq("recipient_id", value: me)
            .is("read_at", value: nil)
            .execute()
        return response.count ?? 0
    }

    func markNotificationsRead() async throws {
        _ = try requireUser()
        try await client.rpc("mark_notifications_read").execute()
    }

    func imageData(storagePath: String, thumbnail: Bool) async throws -> Data {
        let requested = thumbnail ? MediaPath.thumbnail(for: storagePath) : storagePath
        if let cached = readCache(requested) { return cached }
        do {
            let data = try await download(requested)
            writeCache(requested, data)
            return data
        } catch {
            if thumbnail {
                if let cached = readCache(storagePath) { return cached }
                let data = try await download(storagePath)
                writeCache(storagePath, data)
                return data
            }
            throw error
        }
    }

    func changes() -> AsyncStream<ChangeSignal> {
        let client = client
        let hub = hub
        Task {
            await gate.start {
                let channel = client.channel("nightshift-live")
                let events = channel.postgresChange(AnyAction.self, schema: "public", table: "events")
                await channel.subscribe()
                for await _ in events {
                    await hub.emit(.events)
                }
            }
        }
        return hub.stream()
    }

    private func requireUser() throws -> UUID {
        guard let id = client.auth.currentSession?.user.id else { throw NightshiftError.notSignedIn }
        return id
    }

    private func profileRow(_ id: UUID) async throws -> Profile {
        let rows: [Profile] = try await client.from("profiles").select().eq("id", value: id).limit(1).execute().value
        if let profile = rows.first { return profile }
        try await Task.sleep(for: .milliseconds(350))
        let retry: [Profile] = try await client.from("profiles").select().eq("id", value: id).limit(1).execute().value
        guard let profile = retry.first else { throw NightshiftError.notFound }
        return profile
    }

    private func myEventIDs() async throws -> [UUID] {
        try await eventIDs(for: try requireUser())
    }

    private func eventIDs(for userID: UUID) async throws -> [UUID] {
        let rows: [EventIDOnly] = try await client.from("event_attendees").select("event_id").eq("user_id", value: userID).execute().value
        return rows.map(\.eventID)
    }

    private func didBlock(_ blocker: UUID, other: UUID) async throws -> Bool {
        let rows: [Block] = try await client.from("blocks").select()
            .eq("blocker_id", value: blocker)
            .eq("blocked_id", value: other)
            .limit(1)
            .execute()
            .value
        return !rows.isEmpty
    }

    private func eitherBlock(_ a: UUID, _ b: UUID) async throws -> Bool {
        let value: Bool = try await client.rpc("is_blocked", params: BlockParams(a: a, b: b)).execute().value
        return value
    }

    private func count(_ table: String, column: String, value: UUID) async throws -> Int {
        let response = try await client.from(table).select(column, head: true, count: .exact).eq(column, value: value).execute()
        return response.count ?? 0
    }

    private func profiles(ids: [UUID]) async throws -> [Profile] {
        let unique = Array(Set(ids))
        if unique.isEmpty { return [] }
        let rows: [Profile] = try await client.from("profiles").select().in("id", values: unique).execute().value
        return rows
    }

    private func summaries(for vehicles: [Vehicle]) async throws -> [VehicleSummary] {
        let ids = vehicles.map(\.id)
        let photos: [VehiclePhoto]
        if ids.isEmpty {
            photos = []
        } else {
            photos = try await client.from("vehicle_photos").select().in("vehicle_id", values: ids).execute().value
        }
        return vehicles.map { vehicle in
            let mine = photos.filter { $0.vehicleID == vehicle.id }.sorted { $0.sortOrder < $1.sortOrder }
            return VehicleSummary(vehicle: vehicle, coverPath: mine.first?.storagePath, photoCount: mine.count)
        }
    }

    private func assemble(_ rows: [PostCardRow], viewer: UUID) async throws -> [PostItem] {
        let postIDs = rows.map(\.post.id)
        let authorIDs = Array(Set(rows.map(\.post.authorID)))
        let vehicleIDs = Array(Set(rows.compactMap(\.post.vehicleID)))
        let images: [PostImage] = postIDs.isEmpty ? [] : try await client.from("post_images").select().in("post_id", values: postIDs).execute().value
        let authors = try await profiles(ids: authorIDs)
        let vehicles: [Vehicle] = vehicleIDs.isEmpty ? [] : try await client.from("vehicles").select().in("id", values: vehicleIDs).execute().value
        let likes: [PostLike] = postIDs.isEmpty ? [] : try await client.from("post_likes").select().eq("user_id", value: viewer).in("post_id", values: postIDs).execute().value
        return rows.compactMap { row in
            guard let author = authors.first(where: { $0.id == row.post.authorID }) else { return nil }
            return PostItem(
                post: row.post,
                author: author,
                vehicle: vehicles.first { $0.id == row.post.vehicleID },
                images: images.filter { $0.postID == row.post.id }.sorted { $0.sortOrder < $1.sortOrder },
                likeCount: row.likeCount,
                commentCount: row.commentCount,
                likedByMe: likes.contains { $0.postID == row.post.id }
            )
        }
    }

    private func conversation(_ rows: [(UUID, UUID, String, Date)], viewer: UUID) async throws -> [ConversationNote] {
        let authors = try await profiles(ids: rows.map { $0.1 })
        return rows.compactMap { row in
            guard let author = authors.first(where: { $0.id == row.1 }) else { return nil }
            return ConversationNote(id: row.0, author: author, content: row.2, createdAt: row.3, isMine: row.1 == viewer)
        }
    }

    private func replaceVehiclePhotos(vehicleID: UUID, uploads: [PhotoUpload]) async throws {
        try await client.from("vehicle_photos").delete().eq("vehicle_id", value: vehicleID).execute()
        var rows: [VehiclePhoto] = []
        for (index, upload) in uploads.enumerated() {
            let path: String
            switch upload.source {
            case .existing(let existing): path = existing
            case .new(let data): path = try await uploadImage(data, bucket: "vehicle-photos")
            }
            rows.append(VehiclePhoto(id: UUID(), vehicleID: vehicleID, storagePath: path, sortOrder: index, createdAt: Date()))
        }
        if !rows.isEmpty {
            try await client.from("vehicle_photos").insert(rows).execute()
        }
    }

    private func uploadProfileImage(_ data: Data, bucket: String, column: String) async throws -> Profile {
        let me = try requireUser()
        let path = try await uploadImage(data, bucket: bucket)
        let rows: [Profile]
        if column == "avatar_url" {
            rows = try await client.from("profiles").update(AvatarWrite(avatarURL: path)).eq("id", value: me).select().execute().value
        } else {
            rows = try await client.from("profiles").update(CoverWrite(coverURL: path)).eq("id", value: me).select().execute().value
        }
        guard let profile = rows.first else { throw NightshiftError.notFound }
        await hub.emit(.profile)
        return profile
    }

    private func uploadImage(_ data: Data, bucket: String) async throws -> String {
        let me = try requireUser()
        let full = await ImageEncoder.jpeg(data, maxDimension: 1600, quality: 0.82)
        let thumb = await ImageEncoder.jpeg(data, maxDimension: 480, quality: 0.72)
        guard let full, let thumb else { throw NightshiftError.message("That photo couldn't be prepared.") }
        let name = UUID().uuidString
        let object = "\(me.uuidString.lowercased())/\(name).jpg"
        let thumbObject = "\(me.uuidString.lowercased())/\(name)_thumb.jpg"
        let options = FileOptions(contentType: "image/jpeg", upsert: false)
        try await client.storage.from(bucket).upload(object, data: full, options: options)
        try await client.storage.from(bucket).upload(thumbObject, data: thumb, options: options)
        return "\(bucket):\(object)"
    }

    private func download(_ storagePath: String) async throws -> Data {
        guard let parts = MediaPath.splitRemote(storagePath) else { throw NightshiftError.notFound }
        return try await client.storage.from(parts.bucket).download(path: parts.object)
    }

    private func cacheDirectory() -> URL {
        let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NightshiftImages", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func cacheKey(_ path: String) -> URL {
        let encoded = Data(path.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_")
        return cacheDirectory().appendingPathComponent(encoded)
    }

    private func readCache(_ path: String) -> Data? {
        try? Data(contentsOf: cacheKey(path))
    }

    private func writeCache(_ path: String, _ data: Data) {
        try? data.write(to: cacheKey(path), options: .atomic)
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

    private func trimmed(_ value: String) -> String { value.trimmingCharacters(in: .whitespacesAndNewlines) }

    private func blankToNil(_ value: String) -> String? {
        let value = trimmed(value)
        return value.isEmpty ? nil : value
    }

    private func formatted(_ name: PersonNameComponents?) -> String? {
        guard let name else { return nil }
        let formatted = PersonNameComponentsFormatter().string(from: name).trimmingCharacters(in: .whitespacesAndNewlines)
        return formatted.isEmpty ? nil : formatted
    }
}

private actor RealtimeGate {
    private var started = false

    func start(_ body: @escaping @Sendable () async -> Void) {
        guard !started else { return }
        started = true
        Task { await body() }
    }
}

private struct IDParams: Encodable {
    let target: UUID
}

private struct JoinParams: Encodable {
    let target: UUID
    let car: UUID?
}

private struct EventIDOnly: Decodable {
    var eventID: UUID
    enum CodingKeys: String, CodingKey { case eventID = "event_id" }
}

private struct StatusWrite: Encodable {
    var status: EventStatus
}

private struct ProfileWrite: Encodable {
    var username: String
    var displayName: String
    var avatarURL: String?
    var coverURL: String?
    var bio: String
    var homeCity: String?
    var showGarage: Bool
    var showCity: Bool

    init(profile: Profile) {
        username = profile.username.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        displayName = profile.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        avatarURL = profile.avatarURL
        coverURL = profile.coverURL
        bio = profile.bio
        let city = profile.homeCity?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        homeCity = city.isEmpty ? nil : city
        showGarage = profile.showGarage
        showCity = profile.showCity
    }

    enum CodingKeys: String, CodingKey {
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case coverURL = "cover_url"
        case bio
        case homeCity = "home_city"
        case showGarage = "show_garage"
        case showCity = "show_city"
    }
}

private struct VehicleWrite: Encodable {
    var make: String
    var model: String
    var year: Int
    var trim: String?
    var color: String?
    var bodyStyle: String?
    var transmission: String?
    var engine: String?
    var power: String?
    var nickname: String?
    var description: String

    init(_ vehicle: Vehicle) {
        make = vehicle.make
        model = vehicle.model
        year = vehicle.year
        trim = vehicle.trim
        color = vehicle.color
        bodyStyle = vehicle.bodyStyle
        transmission = vehicle.transmission
        engine = vehicle.engine
        power = vehicle.power
        nickname = vehicle.nickname
        description = vehicle.description
    }

    enum CodingKeys: String, CodingKey {
        case make, model, year, trim, color, transmission, engine, power, nickname, description
        case bodyStyle = "body_style"
    }
}

private struct EventWrite: Encodable {
    var title: String
    var description: String
    var rules: String
    var latitude: Double
    var longitude: Double
    var address: String
    var startsAt: Date
    var endsAt: Date
    var category: EventCategory
    var capacity: Int?
    var visibility: EventVisibility
    var coverImagePath: String?

    init(_ event: Event) {
        title = event.title
        description = event.description
        rules = event.rules
        latitude = event.latitude
        longitude = event.longitude
        address = event.address
        startsAt = event.startsAt
        endsAt = event.endsAt
        category = event.category
        capacity = event.capacity
        visibility = event.visibility
        coverImagePath = event.coverImagePath
    }

    enum CodingKeys: String, CodingKey {
        case title, description, rules, latitude, longitude, address, category, capacity, visibility
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case coverImagePath = "cover_image_path"
    }
}

private struct AvatarWrite: Encodable {
    var avatarURL: String
    enum CodingKeys: String, CodingKey { case avatarURL = "avatar_url" }
}

private struct CoverWrite: Encodable {
    var coverURL: String
    enum CodingKeys: String, CodingKey { case coverURL = "cover_url" }
}

private struct BlockParams: Encodable {
    let a: UUID
    let b: UUID
}
