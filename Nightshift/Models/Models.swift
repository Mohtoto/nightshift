import CoreLocation
import Foundation

enum EventCategory: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case meet
    case jdm
    case euro
    case classic
    case track
    case coffee
    case show

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meet: "Meet"
        case .jdm: "JDM"
        case .euro: "Euro"
        case .classic: "Classic"
        case .track: "Track day"
        case .coffee: "Cars & coffee"
        case .show: "Car show"
        }
    }

    var symbol: String {
        switch self {
        case .meet: "car.2.fill"
        case .jdm: "bolt.fill"
        case .euro: "shield.fill"
        case .classic: "clock.fill"
        case .track: "flag.checkered"
        case .coffee: "cup.and.saucer.fill"
        case .show: "star.fill"
        }
    }

    var isFeatured: Bool { self == .show }
}

enum EventVisibility: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case `public`
    case `private`

    var id: String { rawValue }
    var title: String { self == .public ? "Public" : "Unlisted" }
}

enum EventStatus: String, Codable, Hashable, Sendable {
    case scheduled
    case cancelled
}

enum ReportTarget: String, Codable, CaseIterable, Identifiable, Hashable, Sendable {
    case post
    case comment
    case event
    case profile
    case vehicle

    var id: String { rawValue }
}

enum NotificationKind: String, Codable, Hashable, Sendable {
    case follow
    case like
    case comment
    case eventJoin = "event_join"
    case vehicleComment = "vehicle_comment"
}

enum AuthOutcome: Sendable {
    case signedIn(Profile)
    case confirmationRequired
}

enum ChangeSignal: Sendable {
    case events
    case social
    case garage
    case profile
}

struct Profile: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var username: String
    var displayName: String
    var avatarURL: String?
    var coverURL: String?
    var bio: String
    var homeCity: String?
    var showGarage: Bool
    var showCity: Bool
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case displayName = "display_name"
        case avatarURL = "avatar_url"
        case coverURL = "cover_url"
        case bio
        case homeCity = "home_city"
        case showGarage = "show_garage"
        case showCity = "show_city"
        case createdAt = "created_at"
    }

    var handle: String { "@\(username)" }
}

struct ProfileCard: Identifiable, Hashable, Sendable {
    var profile: Profile
    var followerCount: Int
    var followingCount: Int
    var isFollowedByMe: Bool
    var isBlockedByMe: Bool

    var id: UUID { profile.id }
}

struct Vehicle: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var ownerID: UUID
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
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case ownerID = "owner_id"
        case make
        case model
        case year
        case trim
        case color
        case bodyStyle = "body_style"
        case transmission
        case engine
        case power
        case nickname
        case description
        case createdAt = "created_at"
    }

    var displayName: String {
        let nick = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if nick.isEmpty { return "\(year) \(make) \(model)" }
        return nick
    }

    var subtitle: String { "\(year) \(make) \(model)" }
}

struct VehiclePhoto: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var vehicleID: UUID
    var storagePath: String
    var sortOrder: Int
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case vehicleID = "vehicle_id"
        case storagePath = "storage_path"
        case sortOrder = "sort_order"
        case createdAt = "created_at"
    }
}

struct VehicleModification: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var vehicleID: UUID
    var category: String
    var name: String
    var description: String

    enum CodingKeys: String, CodingKey {
        case id
        case vehicleID = "vehicle_id"
        case category
        case name
        case description
    }
}

struct VehicleSummary: Identifiable, Hashable, Sendable {
    var vehicle: Vehicle
    var coverPath: String?
    var photoCount: Int
    var id: UUID { vehicle.id }
}

struct VehicleDetail: Identifiable, Hashable, Sendable {
    var vehicle: Vehicle
    var photos: [VehiclePhoto]
    var modifications: [VehicleModification]
    var owner: Profile
    var likeCount: Int
    var likedByMe: Bool
    var commentCount: Int
    var attendedMeets: [EventSummary]
    var id: UUID { vehicle.id }
}

struct Event: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var hostID: UUID
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
    var status: EventStatus
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case hostID = "host_id"
        case title
        case description
        case rules
        case latitude
        case longitude
        case address
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case category
        case capacity
        case visibility
        case coverImagePath = "cover_image_path"
        case status
        case createdAt = "created_at"
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct EventCardRow: Decodable, Sendable {
    var event: Event
    var attendeeCount: Int
    var hostDisplayName: String
    var hostUsername: String

    enum CodingKeys: String, CodingKey {
        case attendeeCount = "attendee_count"
        case hostDisplayName = "host_display_name"
        case hostUsername = "host_username"
    }

    init(from decoder: Decoder) throws {
        event = try Event(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attendeeCount = try container.decode(Int.self, forKey: .attendeeCount)
        hostDisplayName = try container.decode(String.self, forKey: .hostDisplayName)
        hostUsername = try container.decode(String.self, forKey: .hostUsername)
    }

    func summary(joined: Bool) -> EventSummary {
        EventSummary(
            event: event,
            attendeeCount: attendeeCount,
            joined: joined,
            hostDisplayName: hostDisplayName,
            hostUsername: hostUsername
        )
    }
}

struct EventSummary: Identifiable, Hashable, Sendable {
    var event: Event
    var attendeeCount: Int
    var joined: Bool
    var hostDisplayName: String
    var hostUsername: String

    var id: UUID { event.id }
}

struct Attendee: Codable, Identifiable, Hashable, Sendable {
    var userID: UUID
    var joinedAt: Date
    var profile: Profile
    var vehicle: Vehicle?

    var id: UUID { userID }

    enum CodingKeys: String, CodingKey {
        case profile
        case vehicle
        case userID = "user_id"
        case joinedAt = "joined_at"
    }
}

struct EventDetail: Codable, Identifiable, Hashable, Sendable {
    var event: Event
    var host: Profile
    var attendees: [Attendee]
    var attendeeCount: Int
    var joined: Bool
    var myVehicleID: UUID?

    var id: UUID { event.id }

    enum CodingKeys: String, CodingKey {
        case event
        case host
        case attendees
        case joined
        case attendeeCount = "attendee_count"
        case myVehicleID = "my_vehicle_id"
    }
}

struct Post: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var authorID: UUID
    var vehicleID: UUID?
    var caption: String
    var createdAt: Date
    var hidden: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case authorID = "author_id"
        case vehicleID = "vehicle_id"
        case caption
        case createdAt = "created_at"
        case hidden
    }
}

struct PostImage: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var postID: UUID
    var storagePath: String
    var sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case storagePath = "storage_path"
        case sortOrder = "sort_order"
    }
}

struct PostCardRow: Decodable, Sendable {
    var post: Post
    var likeCount: Int
    var commentCount: Int

    enum CodingKeys: String, CodingKey {
        case likeCount = "like_count"
        case commentCount = "comment_count"
    }

    init(from decoder: Decoder) throws {
        post = try Post(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        likeCount = try container.decode(Int.self, forKey: .likeCount)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
    }
}

struct PostItem: Identifiable, Hashable, Sendable {
    var post: Post
    var author: Profile
    var vehicle: Vehicle?
    var images: [PostImage]
    var likeCount: Int
    var commentCount: Int
    var likedByMe: Bool

    var id: UUID { post.id }
}

struct Comment: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var postID: UUID
    var authorID: UUID
    var content: String
    var createdAt: Date
    var hidden: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case postID = "post_id"
        case authorID = "author_id"
        case content
        case createdAt = "created_at"
        case hidden
    }
}

struct VehicleComment: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var vehicleID: UUID
    var authorID: UUID
    var content: String
    var createdAt: Date
    var hidden: Bool

    enum CodingKeys: String, CodingKey {
        case id
        case vehicleID = "vehicle_id"
        case authorID = "author_id"
        case content
        case createdAt = "created_at"
        case hidden
    }
}

struct ConversationNote: Identifiable, Hashable, Sendable {
    var id: UUID
    var author: Profile
    var content: String
    var createdAt: Date
    var isMine: Bool
}

struct Follow: Codable, Hashable, Sendable {
    var followerID: UUID
    var followingID: UUID
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case followerID = "follower_id"
        case followingID = "following_id"
        case createdAt = "created_at"
    }
}

struct Block: Codable, Hashable, Sendable {
    var blockerID: UUID
    var blockedID: UUID
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case blockerID = "blocker_id"
        case blockedID = "blocked_id"
        case createdAt = "created_at"
    }
}

struct Report: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var reporterID: UUID
    var targetType: ReportTarget
    var targetID: UUID
    var reason: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case reporterID = "reporter_id"
        case targetType = "target_type"
        case targetID = "target_id"
        case reason
        case createdAt = "created_at"
    }
}

struct AppNotification: Codable, Identifiable, Hashable, Sendable {
    var id: UUID
    var recipientID: UUID
    var type: NotificationKind
    var payload: NotificationPayload
    var readAt: Date?
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case payload
        case recipientID = "recipient_id"
        case readAt = "read_at"
        case createdAt = "created_at"
    }

    var message: String {
        let name = payload.actorName ?? "Someone"
        switch type {
        case .follow: return "\(name) started following you."
        case .like: return "\(name) liked your post."
        case .comment: return "\(name) commented on your post."
        case .eventJoin: return "\(name) is coming to your meet."
        case .vehicleComment: return "\(name) commented on your car."
        }
    }
}

struct NotificationPayload: Codable, Hashable, Sendable {
    var actorID: UUID?
    var actorName: String?
    var postID: UUID?
    var eventID: UUID?
    var vehicleID: UUID?
    var commentID: UUID?

    enum CodingKeys: String, CodingKey {
        case actorID = "actor_id"
        case actorName = "actor_name"
        case postID = "post_id"
        case eventID = "event_id"
        case vehicleID = "vehicle_id"
        case commentID = "comment_id"
    }
}

struct PostLike: Codable, Hashable, Sendable {
    var postID: UUID
    var userID: UUID
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case postID = "post_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

struct VehicleLike: Codable, Hashable, Sendable {
    var vehicleID: UUID
    var userID: UUID
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case vehicleID = "vehicle_id"
        case userID = "user_id"
        case createdAt = "created_at"
    }
}

struct Attendance: Codable, Hashable, Sendable {
    var id: UUID
    var eventID: UUID
    var userID: UUID
    var vehicleID: UUID?
    var joinedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case eventID = "event_id"
        case userID = "user_id"
        case vehicleID = "vehicle_id"
        case joinedAt = "joined_at"
    }
}

enum PhotoSource: Sendable, Equatable {
    case existing(String)
    case new(Data)
}

struct PhotoUpload: Identifiable, Sendable, Equatable {
    var id: UUID
    var source: PhotoSource

    init(id: UUID = UUID(), source: PhotoSource) {
        self.id = id
        self.source = source
    }
}

struct ModificationDraft: Identifiable, Hashable, Sendable {
    var id: UUID
    var category: String
    var name: String
    var description: String

    init(id: UUID = UUID(), category: String = "Exterior", name: String = "", description: String = "") {
        self.id = id
        self.category = category
        self.name = name
        self.description = description
    }
}

struct VehicleDraft: Sendable, Equatable {
    var make = ""
    var model = ""
    var year = 2020
    var trim = ""
    var color = ""
    var bodyStyle = ""
    var transmission = ""
    var engine = ""
    var power = ""
    var nickname = ""
    var description = ""
    var modifications: [ModificationDraft] = []
    var photos: [PhotoUpload] = []
}

struct EventDraft: Equatable, Sendable {
    var title = ""
    var description = ""
    var rules = ""
    var address = ""
    var latitude: Double?
    var longitude: Double?
    var startsAt = Date(timeIntervalSince1970: 0)
    var endsAt = Date(timeIntervalSince1970: 0)
    var category: EventCategory = .meet
    var limitsCapacity = false
    var capacity = 50
    var visibility: EventVisibility = .public
    var coverData: Data?
    var existingCoverPath: String?
}

struct PostDraft: Sendable {
    var caption = ""
    var vehicleID: UUID?
    var photos: [PhotoUpload] = []
}

struct EventQuery: Sendable {
    var south: Double?
    var north: Double?
    var west: Double?
    var east: Double?
    var category: EventCategory?
    var search: String?
    var startsAfter: Date?
    var startsBefore: Date?
    var endingAfter: Date?
    var joinedOnly = false
    var hostedOnly = false
    var subjectID: UUID?
    var limit = 40
}

enum NightshiftError: LocalizedError, Equatable {
    case message(String)
    case notSignedIn
    case notFound

    var errorDescription: String? {
        switch self {
        case .message(let text): text
        case .notSignedIn: "Sign in to continue."
        case .notFound: "That couldn't be found."
        }
    }
}

enum BackendMode: Equatable, Sendable {
    case local
    case supabase
    case invalid(String)
}

enum MediaPath {
    static func thumbnail(for path: String) -> String {
        guard let dot = path.lastIndex(of: ".") else { return path + "_thumb" }
        return path[..<dot] + "_thumb" + path[dot...]
    }

    static func localRelative(_ path: String) -> String? {
        guard path.hasPrefix("local:") else { return nil }
        return String(path.dropFirst("local:".count))
    }

    static func splitRemote(_ path: String) -> (bucket: String, object: String)? {
        guard localRelative(path) == nil, let index = path.firstIndex(of: ":") else { return nil }
        let bucket = String(path[..<index])
        let object = String(path[path.index(after: index)...])
        guard !bucket.isEmpty, !object.isEmpty else { return nil }
        return (bucket, object)
    }
}

enum NightshiftFormat {
    static func eventDay(_ date: Date) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
    }

    static func eventTimeRange(start: Date, end: Date) -> String {
        let sameDay = Calendar.current.isDate(start, inSameDayAs: end)
        let startText = start.formatted(date: .abbreviated, time: .shortened)
        if sameDay {
            return "\(startText) – \(end.formatted(date: .omitted, time: .shortened))"
        }
        return "\(startText) – \(end.formatted(date: .abbreviated, time: .shortened))"
    }

    static func relative(_ date: Date) -> String {
        date.formatted(.relative(presentation: .named))
    }

    static func distance(_ meters: CLLocationDistance) -> String {
        if meters < 1000 {
            return "\(Int(meters.rounded())) m"
        }
        let kilometers = meters / 1000
        if kilometers < 10 {
            return String(format: "%.1f km", kilometers)
        }
        return "\(Int(kilometers.rounded())) km"
    }

    static func memberSince(_ date: Date) -> String {
        date.formatted(.dateTime.month(.wide).year())
    }
}

enum JSONCoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    static func isoString(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    static func isoDate(from value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}
