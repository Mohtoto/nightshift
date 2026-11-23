import XCTest

final class NightshiftUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        addUIInterruptionMonitor(withDescription: "System") { alert in
            for title in ["Not Now", "Don't Allow", "Allow While Using App"] {
                let button = alert.buttons[title]
                if button.exists {
                    button.tap()
                    return true
                }
            }
            return false
        }
    }

    func testCreateGarageMeetAndPost() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-skipLaunch"]
        app.launch()

        let next = app.buttons["onboarding.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 8))
        next.tap()
        next.tap()
        next.tap()
        app.buttons["onboarding.finish"].tap()

        let username = app.textFields["auth.username"]
        XCTAssertTrue(username.waitForExistence(timeout: 5))
        username.tap()
        username.typeText("ada_r")
        let name = app.textFields["auth.displayName"]
        name.tap()
        name.typeText("Ada R")
        let email = app.textFields["auth.email"]
        email.tap()
        email.typeText("ada@nightshift.test")
        let password = app.secureTextFields["auth.password"]
        password.tap()
        password.typeText("underground")
        app.buttons["auth.submit"].tap()

        XCTAssertTrue(app.tabBars.buttons["Map"].waitForExistence(timeout: 8))
        dismissSystemPrompts(app)
        attach(app, name: "map-empty")

        app.tabBars.buttons["Garage"].tap()
        app.buttons["garage.add"].tap()
        let make = app.textFields["vehicle.make"]
        XCTAssertTrue(make.waitForExistence(timeout: 4))
        app.buttons["useTestPhoto"].tap()
        make.tap()
        make.typeText("Nissan")
        let model = app.textFields["vehicle.model"]
        model.tap()
        model.typeText("Silvia")
        reveal(app.buttons["vehicle.save"], in: app)
        app.buttons["vehicle.save"].tap()
        let carTitle = "\(Calendar.current.component(.year, from: Date())) Nissan Silvia"
        XCTAssertTrue(app.descendants(matching: .any)[carTitle].waitForExistence(timeout: 8))
        attach(app, name: "garage")

        app.tabBars.buttons["Meets"].tap()
        tapHittable(app, identifier: "meets.create")
        let title = app.textFields["event.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 4))
        if app.buttons["useTestPhoto"].waitForExistence(timeout: 2) {
            app.buttons["useTestPhoto"].tap()
        }
        title.tap()
        title.typeText("Harbor Lights")
        let description = app.textFields["event.description"]
        description.tap()
        description.typeText("A lawful waterfront meet with no racing.")
        let testLocation = app.buttons["useTestLocation"]
        reveal(testLocation, in: app)
        testLocation.tap()
        let saveMeet = app.buttons["event.save"]
        reveal(saveMeet, in: app)
        saveMeet.tap()

        let meet = app.staticTexts["Harbor Lights"]
        XCTAssertTrue(meet.waitForExistence(timeout: 8))
        meet.tap()
        let join = app.buttons["event.join"]
        XCTAssertTrue(join.waitForExistence(timeout: 4))
        join.tap()
        if app.buttons["Join without a car"].waitForExistence(timeout: 2) {
            app.buttons["Join without a car"].tap()
        }
        XCTAssertTrue(app.buttons["event.join"].waitForExistence(timeout: 4))
        XCTAssertTrue(app.staticTexts["Attending"].waitForExistence(timeout: 4) || app.buttons["event.join"].label.contains("Attending"))
        attach(app, name: "event-detail")
        app.buttons["event.join"].tap()

        app.tabBars.buttons["Map"].tap()
        XCTAssertTrue(app.textFields["map.search"].waitForExistence(timeout: 4))
        attach(app, name: "map-with-meet")

        app.tabBars.buttons["Feed"].tap()
        app.buttons["feed.compose"].tap()
        let caption = app.textFields["post.caption"]
        XCTAssertTrue(caption.waitForExistence(timeout: 4))
        app.buttons["useTestPhoto"].tap()
        caption.tap()
        caption.typeText("Fresh alignment.")
        reveal(app.buttons["post.publish"], in: app)
        app.buttons["post.publish"].tap()
        XCTAssertTrue(app.staticTexts["Fresh alignment."].waitForExistence(timeout: 6))
        app.buttons["post.like"].firstMatch.tap()
        attach(app, name: "feed")

        app.tabBars.buttons["Profile"].tap()
        app.buttons["profile.settings"].tap()
        XCTAssertTrue(app.buttons["profile.signOut"].waitForExistence(timeout: 4))
        attach(app, name: "settings")
        app.buttons["profile.signOut"].tap()
        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 6))
        let returnEmail = app.textFields["auth.email"]
        returnEmail.tap()
        returnEmail.typeText("ada@nightshift.test")
        let returnPassword = app.secureTextFields["auth.password"]
        returnPassword.tap()
        returnPassword.typeText("underground")
        app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.tabBars.buttons["Garage"].waitForExistence(timeout: 8))
        app.tabBars.buttons["Garage"].tap()
        XCTAssertTrue(app.descendants(matching: .any)[carTitle].waitForExistence(timeout: 6))
    }

    private func dismissSystemPrompts(_ app: XCUIApplication) {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) {
            notNow.tap()
        }
    }

    private func tapHittable(_ app: XCUIApplication, identifier: String) {
        let matches = app.buttons.matching(identifier: identifier)
        for index in 0..<matches.count {
            let element = matches.element(boundBy: index)
            if element.exists && element.isHittable {
                element.tap()
                return
            }
        }
        matches.firstMatch.tap()
    }

    private func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        var swipes = 0
        while element.exists && !element.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
    }

    func testDeniedLocationStillAllowsCitySearch() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-UITesting", "-skipLaunch"]
        app.launch()
        addUIInterruptionMonitor(withDescription: "Location") { alert in
            let deny = alert.buttons["Don't Allow"]
            if deny.exists {
                deny.tap()
                return true
            }
            return false
        }
        if app.buttons["onboarding.next"].waitForExistence(timeout: 4) {
            app.buttons["onboarding.next"].tap()
            app.buttons["onboarding.next"].tap()
            app.buttons["onboarding.next"].tap()
            app.buttons["onboarding.finish"].tap()
            let username = app.textFields["auth.username"]
            XCTAssertTrue(username.waitForExistence(timeout: 4))
            username.tap()
            username.typeText("bo_r")
            app.textFields["auth.displayName"].tap()
            app.typeText("Bo")
            app.textFields["auth.email"].tap()
            app.typeText("bo@nightshift.test")
            app.secureTextFields["auth.password"].tap()
            app.typeText("underground")
            app.buttons["auth.submit"].tap()
        }
        XCTAssertTrue(app.tabBars.buttons["Map"].waitForExistence(timeout: 8))
        app.swipeDown()
        XCTAssertTrue(app.textFields["map.search"].exists)
    }

    private func attach(_ app: XCUIApplication, name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
