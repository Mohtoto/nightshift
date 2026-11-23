import CryptoKit
import Foundation

protocol NightshiftRepository: Sendable {
    func restoreSession() async throws -> Profile?
    func signUp(email: String, password: String, username: String, displayName: String) async throws -> AuthOutcome
    func signIn(email: String, password: String) async throws -> Profile
    func signInWithApple(userID: String, idToken: String?, nonce: String, fullName: PersonNameComponents?) async throws -> Profile
    func requestPasswordReset(email: String) async throws
    func setPassword(email: String, newPassword: String) async throws
    func signOut() async throws
    func deleteAccount() async throws

    func profile(id: UUID) async throws -> ProfileCard
    func updateProfile(_ profile: Profile) async throws -> Profile
    func uploadAvatar(_ data: Data) async throws -> Profile
    func uploadCover(_ data: Data) async throws -> Profile

    func vehicles(ownerID: UUID) async throws -> [VehicleSummary]
    func vehicle(id: UUID) async throws -> VehicleDetail
    func saveVehicle(_ draft: VehicleDraft, existingID: UUID?) async throws -> Vehicle
    func deleteVehicle(id: UUID) async throws
    func setVehicleLike(id: UUID, liked: Bool) async throws
    func vehicleNotes(id: UUID) async throws -> [ConversationNote]
    func addVehicleNote(id: UUID, content: String) async throws

    func events(filter: EventQuery) async throws -> [EventSummary]
    func event(id: UUID) async throws -> EventDetail
    func saveEvent(_ draft: EventDraft, existingID: UUID?) async throws -> Event
    func cancelEvent(id: UUID) async throws
    func joinEvent(id: UUID, vehicleID: UUID?) async throws
    func leaveEvent(id: UUID) async throws

    func posts(authorID: UUID?, before: Date?, limit: Int) async throws -> [PostItem]
    func post(id: UUID) async throws -> PostItem
    func createPost(_ draft: PostDraft) async throws -> Post
    func deletePost(id: UUID) async throws
    func setPostLike(id: UUID, liked: Bool) async throws
    func notes(postID: UUID) async throws -> [ConversationNote]
    func addNote(postID: UUID, content: String) async throws
    func deleteNote(id: UUID) async throws

    func setFollowing(userID: UUID, following: Bool) async throws
    func followers(of userID: UUID) async throws -> [Profile]
    func following(of userID: UUID) async throws -> [Profile]
    func report(target: ReportTarget, targetID: UUID, reason: String) async throws
    func reportsFiled() async throws -> [Report]
    func setBlocked(userID: UUID, blocked: Bool) async throws
    func blockedUsers() async throws -> [Profile]

    func notifications() async throws -> [AppNotification]
    func unreadNotificationCount() async throws -> Int
    func markNotificationsRead() async throws

    func imageData(storagePath: String, thumbnail: Bool) async throws -> Data
    func changes() -> AsyncStream<ChangeSignal>
}

actor SignalHub {
    private var subscribers: [UUID: AsyncStream<ChangeSignal>.Continuation] = [:]

    nonisolated func stream() -> AsyncStream<ChangeSignal> {
        AsyncStream { continuation in
            let id = UUID()
            Task { await self.add(id, continuation) }
            continuation.onTermination = { _ in
                Task { await self.remove(id) }
            }
        }
    }

    func emit(_ signal: ChangeSignal) {
        for continuation in subscribers.values {
            continuation.yield(signal)
        }
    }

    private func add(_ id: UUID, _ continuation: AsyncStream<ChangeSignal>.Continuation) {
        subscribers[id] = continuation
    }

    private func remove(_ id: UUID) {
        subscribers[id] = nil
    }
}

enum PasswordHash {
    static func hash(_ password: String) -> String {
        let digest = SHA256.hash(data: Data(password.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
