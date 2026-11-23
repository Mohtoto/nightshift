import XCTest
@testable import Nightshift

@MainActor
final class NightshiftTests: XCTestCase {
    func testValidatorsRejectIncompleteEventsAndUsernames() {
        XCTAssertNotNil(Validators.username("ab"))
        XCTAssertNotNil(Validators.username("Bad Name"))
        XCTAssertNil(Validators.username("ada_r"))
        XCTAssertNotNil(Validators.password("short"))
        var draft = EventDraft()
        draft.title = "No"
        draft.description = "too short"
        draft.address = "x"
        XCTAssertNotNil(Validators.event(draft, editing: false))
        draft.title = "Harbor meet"
        draft.description = "A lawful evening cruise with no racing."
        draft.address = "1 Main Street"
        draft.latitude = 34.05
        draft.longitude = -118.25
        draft.startsAt = Date().addingTimeInterval(3600)
        draft.endsAt = Date().addingTimeInterval(1800)
        draft.coverData = Data([0x1])
        XCTAssertEqual(Validators.event(draft, editing: false), "End time must be after the start time.")
        draft.endsAt = Date().addingTimeInterval(7200)
        XCTAssertNil(Validators.event(draft, editing: false))
    }

    func testLocalSocialGraphPersistsAndEnforcesRules() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let repository = LocalRepository(directory: directory)
        let photo = TestImages.jpeg(seed: 1)
        guard case .signedIn(let ada) = try await repository.signUp(email: "ada@nightshift.test", password: "underground", username: "ada_r", displayName: "Ada R") else {
            return XCTFail("Expected a session")
        }
        var vehicle = VehicleDraft()
        vehicle.make = "Nissan"
        vehicle.model = "Silvia"
        vehicle.year = 1999
        vehicle.nickname = "Afterhours"
        vehicle.photos = [PhotoUpload(source: .new(photo))]
        let saved = try await repository.saveVehicle(vehicle, existingID: nil)
        let loaded = try await repository.vehicle(id: saved.id)
        XCTAssertEqual(loaded.photos.count, 1)
        let image = try await repository.imageData(storagePath: loaded.photos[0].storagePath, thumbnail: true)
        XCTAssertFalse(image.isEmpty)

        var event = futureEvent()
        event.visibility = .public
        let meet = try await repository.saveEvent(event, existingID: nil)
        let listed = try await repository.events(filter: EventQuery(endingAfter: Date(), limit: 20))
        XCTAssertEqual(listed.map(\.id), [meet.id])
        XCTAssertEqual(listed[0].attendeeCount, 0)

        var hidden = futureEvent()
        hidden.title = "Private garage night"
        hidden.visibility = .private
        let privateMeet = try await repository.saveEvent(hidden, existingID: nil)
        let discovery = try await repository.events(filter: EventQuery(endingAfter: Date(), limit: 20))
        XCTAssertFalse(discovery.contains { $0.id == privateMeet.id })
        let privateDetail = try await repository.event(id: privateMeet.id)
        XCTAssertEqual(privateDetail.event.visibility, .private)

        try await repository.joinEvent(id: meet.id, vehicleID: saved.id)
        let joined = try await repository.event(id: meet.id)
        XCTAssertTrue(joined.joined)
        XCTAssertEqual(joined.attendeeCount, 1)
        XCTAssertEqual(joined.myVehicleID, saved.id)
        try await repository.leaveEvent(id: meet.id)
        let left = try await repository.event(id: meet.id)
        XCTAssertFalse(left.joined)
        XCTAssertEqual(left.attendeeCount, 0)

        var full = futureEvent()
        full.title = "Two car cap"
        full.limitsCapacity = true
        full.capacity = 2
        let capped = try await repository.saveEvent(full, existingID: nil)
        try await repository.signOut()
        _ = try await repository.signUp(email: "bo@nightshift.test", password: "underground", username: "bo_r", displayName: "Bo")
        try await repository.joinEvent(id: capped.id, vehicleID: nil)
        try await repository.signOut()
        _ = try await repository.signUp(email: "cy@nightshift.test", password: "underground", username: "cy_r", displayName: "Cy")
        try await repository.joinEvent(id: capped.id, vehicleID: nil)
        try await repository.signOut()
        let adaAgain = try await repository.signIn(email: "ada@nightshift.test", password: "underground")
        XCTAssertEqual(adaAgain.id, ada.id)
        do {
            try await repository.joinEvent(id: capped.id, vehicleID: saved.id)
            XCTFail("Expected the meet to be full")
        } catch let error as NightshiftError {
            XCTAssertEqual(error, .message("This meet is full."))
        }

        try await repository.signOut()
        _ = try await repository.signIn(email: "bo@nightshift.test", password: "underground")
        do {
            _ = try await repository.saveVehicle(vehicle, existingID: saved.id)
            XCTFail("Expected ownership to be enforced")
        } catch {
            XCTAssertFalse(nightshiftMessage(error).isEmpty)
        }

        var post = PostDraft()
        post.caption = "Alignment done."
        post.photos = [PhotoUpload(source: .new(photo))]
        let created = try await repository.createPost(post)
        try await repository.setPostLike(id: created.id, liked: true)
        try await repository.addNote(postID: created.id, content: "Clean.")
        let item = try await repository.post(id: created.id)
        XCTAssertEqual(item.likeCount, 1)
        XCTAssertEqual(item.commentCount, 1)

        try await repository.signOut()
        let cy = try await repository.signIn(email: "cy@nightshift.test", password: "underground")
        let beforeBlock = try await repository.posts(authorID: nil, before: nil, limit: 20)
        XCTAssertTrue(beforeBlock.contains { $0.id == created.id })
        try await repository.setBlocked(userID: created.authorID, blocked: true)
        let afterBlock = try await repository.posts(authorID: nil, before: nil, limit: 20)
        XCTAssertFalse(afterBlock.contains { $0.id == created.id })
        try await repository.report(target: .post, targetID: created.id, reason: "Spam")
        let filed = try await repository.reportsFiled()
        XCTAssertEqual(filed.count, 1)

        var cyCar = VehicleDraft()
        cyCar.make = "Mazda"
        cyCar.model = "RX-7"
        cyCar.year = 1993
        cyCar.photos = [PhotoUpload(source: .new(photo))]
        let cyVehicle = try await repository.saveVehicle(cyCar, existingID: nil)
        try await repository.signOut()
        _ = try await repository.signIn(email: "ada@nightshift.test", password: "underground")
        let visibleGarage = try await repository.vehicles(ownerID: cy.id)
        XCTAssertEqual(visibleGarage.map(\.id), [cyVehicle.id])
        try await repository.signOut()
        _ = try await repository.signIn(email: "cy@nightshift.test", password: "underground")
        var profile = try await repository.profile(id: cy.id)
        profile.profile.showGarage = false
        profile.profile.showCity = false
        profile.profile.homeCity = "Long Beach"
        _ = try await repository.updateProfile(profile.profile)
        try await repository.signOut()
        _ = try await repository.signIn(email: "ada@nightshift.test", password: "underground")
        let hiddenGarage = try await repository.vehicles(ownerID: cy.id)
        XCTAssertTrue(hiddenGarage.isEmpty)
        let cyCard = try await repository.profile(id: cy.id)
        XCTAssertNil(cyCard.profile.homeCity)

        try await repository.cancelEvent(id: meet.id)
        do {
            try await repository.joinEvent(id: meet.id, vehicleID: nil)
            XCTFail("Cancelled meets should reject joins")
        } catch {
            XCTAssertTrue(nightshiftMessage(error).contains("no longer open"))
        }

        let reopened = LocalRepository(directory: directory)
        let restored = try await reopened.restoreSession()
        XCTAssertEqual(restored?.id, ada.id)
        try await reopened.deleteAccount()
        let gone = try await reopened.restoreSession()
        XCTAssertNil(gone)
    }

    private func futureEvent() -> EventDraft {
        var draft = EventDraft()
        draft.title = "Harbor Lights"
        draft.description = "A lawful waterfront cars and coffee. No racing."
        draft.address = "200 N Harbor Blvd, Los Angeles"
        draft.latitude = 33.75
        draft.longitude = -118.19
        draft.startsAt = Date().addingTimeInterval(86_400)
        draft.endsAt = Date().addingTimeInterval(90_000)
        draft.coverData = TestImages.jpeg(seed: 2)
        return draft
    }
}
