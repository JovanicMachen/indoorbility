import XCTest

final class IndoorbilityUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        continueAfterFailure = false
        app.terminate()
        app.launchArguments = ["-agentCloudEnabled", "NO"] // UI regressions use the deterministic offline assistant.
        app.launch()
        openSettingsTool("Advanced & testing")
        reveal(app.buttons["resetDemo"])
        app.buttons["resetDemo"].tap()
        XCTAssertTrue(app.buttons["Reset reports and preferences"].waitForExistence(timeout: 5))
        app.buttons["Reset reports and preferences"].tap()
        openSettingsTool("Demo navigation")
    }

    func testFullScreenLeftSwipeReturnsFromSearchAndSettings() throws {
        app.tabBars.buttons["Home"].tap()
        let field = app.textFields["destinationSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Room 006")
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.42))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.42))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Search destinations")
        settingsRoot()
        app.buttons["AI connection"].tap()
        XCTAssertTrue(app.navigationBars["AI connection"].waitForExistence(timeout: 5))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 5))
    }

    func testLeftSwipeOverSearchResultReturnsHome() throws {
        app.tabBars.buttons["Home"].tap()
        let field = app.textFields["destinationSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Friend Center 008")
        app.staticTexts["destinationPrompt"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        let result = app.buttons.containing(.staticText, identifier: "Room 008 · Friend Center").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: result.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.5)))
        XCTAssertEqual(field.value as? String, "Search destinations")
        XCTAssertFalse(app.buttons["closeDestinationSearch"].exists)
        field.tap(); field.typeText("Friend Center 006")
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Room 006 · Friend Center").firstMatch.waitForExistence(timeout: 5))
    }

    func testCloseSearchClearsQueryAndCanSearchAgain() throws {
        app.tabBars.buttons["Home"].tap()
        let field = app.textFields["destinationSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Friend Center 006")
        app.buttons["closeDestinationSearch"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Search destinations")
        XCTAssertFalse(app.buttons["closeDestinationSearch"].exists)
        capture("home-middle-voice-controls")
        field.tap(); field.typeText("Friend Center 008")
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Room 008 · Friend Center").firstMatch.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Friend Center 008")
    }

    func testGeneralQuestionOfflineDoesNotBecomeADestination() throws {
        app.tabBars.buttons["Home"].tap()
        let field = app.textFields["destinationSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("What is LiDAR?")
        app.buttons["Find destination"].tap()
        let status = app.staticTexts["destinationStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 5))
        XCTAssertEqual(status.label, "General questions need an AI connection. Local navigation still works.")
        XCTAssertEqual(field.value as? String, "What is LiDAR?")
        app.buttons["closeDestinationSearch"].tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "Search destinations")
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        field.typeText("Friend Center 008")
        XCTAssertTrue(app.buttons.containing(.staticText, identifier: "Room 008 · Friend Center").firstMatch.waitForExistence(timeout: 5))
    }

    func testProductionGuidanceSimulationAndMute() throws {
        settingsRoot()
        reveal(app.buttons["AI connection"])
        app.buttons["AI connection"].tap()
        let developer = app.switches["Show agent timeline"]
        reveal(developer)
        if developer.value as? String != "1" { developer.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        XCTAssertEqual(developer.value as? String, "1")
        let testLink = app.buttons["testNavigation"]
        reveal(testLink)
        testLink.tap()
        app.buttons["Start Test"].tap()
        XCTAssertEqual(app.staticTexts["testGuidanceInstruction"].label, "Continue straight for 328 feet.") // Feet is the default unit.
        let loop = app.staticTexts["testJourneyLoopState"]
        XCTAssertTrue(NSPredicate(format: "label == %@", "Travel loop: Playing").evaluate(with: loop) ||
            XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Travel loop: Playing"), object: loop)], timeout: 5) == .completed)
        app.buttons["Simulate tracking loss"].tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Travel loop: Stopped"), object: loop)], timeout: 5) == .completed)
        app.buttons["Recover at simulated landmark"].tap()
        XCTAssertTrue(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Travel loop: Playing"), object: loop)], timeout: 5) == .completed)
        for _ in 0..<8 { app.buttons["Advance position"].tap() }
        XCTAssertEqual(app.staticTexts["testGuidanceInstruction"].label, "Continue straight. In 66 feet, turn left.")
        XCTAssertEqual(loop.label, "Travel loop: Playing")
        let mute = app.switches["Mute all app sound"]
        reveal(mute)
        if mute.value as? String != "1" { mute.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        XCTAssertEqual(mute.value as? String, "1")
        mute.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    func testRoutesTabRecordsBetweenNamedPlaces() throws {
        app.tabBars.buttons["Routes"].tap()
        XCTAssertTrue(app.navigationBars["Routes"].waitForExistence(timeout: 5))
        app.buttons["recordRoute"].tap()
        // One main question; building is preselected when one was used before.
        let destination = app.textFields["Room or destination"]
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap(); destination.typeText("Library door")
        if !app.textFields["Building name"].exists { app.buttons["Change building"].tap() }
        let building = app.textFields["Building name"]
        XCTAssertTrue(building.waitForExistence(timeout: 5))
        building.tap(); building.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 1) { app.menuItems["Select All"].tap(); building.typeText(XCUIKeyboardKey.delete.rawValue) }
        building.typeText("Friend Center")
        app.buttons["More options"].tap()
        let start = app.textFields["Start location"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap(); start.typeText("Main elevator")
        XCTAssertEqual(building.value as? String, "Friend Center")
        XCTAssertEqual(destination.value as? String, "Library door")
        XCTAssertEqual(start.value as? String, "Main elevator")
        XCTAssertFalse(app.buttons["Start recording"].isEnabled) // Simulator cannot record LiDAR.
    }
    func testSavedRoomButtonOpensRegularGuidanceWithoutEndpointSetup() throws {
        app.terminate(); app.launchArguments = ["--saved-room-ui-test"]; app.launch()
        defer {
            app.terminate(); app.launchArguments = []; app.launch()
            app.tabBars.buttons["Routes"].tap() // Remove only the marked simulator fixture.
        }
        app.tabBars.buttons["Routes"].tap()
        let room = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "savedRoom-")).firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 5))
        XCTAssertEqual(room.label, "Room 005, SIMULATED UI Test Building")
        XCTAssertTrue(app.staticTexts["SIMULATED UI Test Building"].firstMatch.exists)
        room.tap()
        XCTAssertTrue(app.buttons["End navigation"].waitForExistence(timeout: 10))
        // The fixture has no world map and the simulator cannot provide ARKit.
        // Dismiss that expected hardware message; this test checks screen flow only.
        if app.alerts["Check your position"].waitForExistence(timeout: 2) {
            app.alerts["Check your position"].buttons["OK"].tap()
        }
        XCTAssertTrue(app.buttons["holdToTalk"].isHittable)
        XCTAssertTrue(app.buttons["stopIndoorDirections"].isHittable)
        XCTAssertTrue(app.buttons["repeatCameraGuidance"].isHittable)
        XCTAssertFalse(app.buttons["matchSavedIndoorMap"].exists)
        XCTAssertFalse(app.buttons["toggleNavigationMap"].exists)
        // Directions are the default view: one big arrow and a distance from the
        // recorded start, clearly labeled as a preview until the sensors match.
        let directions = app.descendants(matching: .any)["liveInstruction"].firstMatch
        XCTAssertTrue(directions.waitForExistence(timeout: 5))
        XCTAssertTrue(directions.label.contains("Straight for"))
        XCTAssertTrue(directions.label.contains("Live position not matched"))
        XCTAssertTrue(app.staticTexts["recordedRoutePreview"].exists)
        XCTAssertFalse(app.descendants(matching: .any)["indoorSavedRouteMap"].firstMatch.exists)
        XCTAssertTrue(app.staticTexts["Positioning unavailable"].exists)
        XCTAssertTrue(app.buttons["retryIndoorPositioning"].isHittable)
        app.buttons["retryIndoorPositioning"].tap()
        if app.alerts["Check your position"].waitForExistence(timeout: 2) {
            app.alerts["Check your position"].buttons["OK"].tap()
        }
        capture("indoor-directions-preview")
        // The recorded route map remains available from the options menu.
        app.buttons["Navigation options"].tap()
        XCTAssertTrue(app.buttons["Directions"].exists)
        app.buttons["Map"].tap()
        let savedMap = app.descendants(matching: .any)["indoorSavedRouteMap"].firstMatch
        XCTAssertTrue(savedMap.waitForExistence(timeout: 5))
        XCTAssertTrue((savedMap.value as? String)?.contains("route trace") == true)
        XCTAssertTrue((savedMap.value as? String)?.contains("recorded direction arrows") == true)
        capture("indoor-immediate-route")
        XCTAssertTrue((savedMap.value as? String)?.hasPrefix("Position not matched") == true)
        XCTAssertFalse(app.descendants(matching: .any)["liveDirectionBadge"].firstMatch.exists) // No guessed arrow before a real map match.
        XCTAssertFalse(app.buttons["indoorRouteRecenter"].isEnabled)
        savedMap.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.4))
            .press(forDuration: 0.05, thenDragTo: savedMap.coordinate(withNormalizedOffset: CGVector(dx: 0.3, dy: 0.4)))
        XCTAssertTrue(app.buttons["End navigation"].exists) // A map pan must not navigate back.
        XCTAssertTrue(app.buttons["indoorRouteOverview"].isHittable)
        app.buttons["indoorRouteOverview"].tap()
        capture("lidar-map-navigation")
        XCTAssertFalse(app.buttons["startSavedRoute"].exists)
        XCTAssertFalse(app.buttons["Confirm first landmark"].exists)
        app.buttons["Navigation options"].tap()
        XCTAssertTrue(app.buttons["Map"].exists)
        XCTAssertTrue(app.buttons["Camera"].exists)
        for removed in ["Simple guidance", "Repeat directions", "Mute", "Accessibility", "What’s ahead?", "Read a sign", "Recover at a landmark", "Report a closure", "Pause guidance", "Ask someone for help"] {
            XCTAssertFalse(app.buttons[removed].exists)
        }
        app.buttons["Camera"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["indoorSavedRouteMap"].firstMatch.exists)
        XCTAssertFalse(app.buttons["showMatchingCamera"].exists)
        app.buttons["Navigation options"].tap()
        app.buttons["Map"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["indoorSavedRouteMap"].firstMatch.exists)
        app.buttons["Navigation options"].tap()
        app.buttons["Directions"].tap()
        XCTAssertFalse(app.descendants(matching: .any)["indoorSavedRouteMap"].firstMatch.exists)
        XCTAssertTrue(app.descendants(matching: .any)["liveInstruction"].firstMatch.exists)
        app.buttons["End navigation"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "savedRoom-")).firstMatch.waitForExistence(timeout: 5))
    }

    func testKnownRoomSearchAcceptsShortNumber() throws {
        app.tabBars.buttons["Home"].tap()
        let field = app.textFields["destinationSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Friend Center 6")
        let room = app.buttons.containing(.staticText, identifier: "Room 006 · Friend Center").firstMatch
        XCTAssertTrue(room.waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Places near you"].exists)
    }

    func testKnownRoomBuildingDirectionsOpensGPSWithoutSearch() throws {
        app.tabBars.buttons["Home"].tap()
        let field = app.textFields["destinationSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Friend 006")
        app.buttons["Find destination"].tap()
        let directions = app.buttons["Directions to building"]
        XCTAssertTrue(directions.waitForExistence(timeout: 5))
        directions.tap()
        XCTAssertTrue(app.buttons["End directions"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.navigationBars["Find building"].exists)
        XCTAssertFalse(app.textFields["Building or address"].exists)
        // Camera-first presentation with the fixed map available on demand.
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 5))
        app.buttons["Map"].tap()
        XCTAssertTrue(app.buttons["Camera"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Recenter"].waitForExistence(timeout: 5))
        app.buttons["Recenter"].tap()
        app.buttons["Camera"].tap()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 5))
    }

    func testCameraRouteControlsWorkBeforeGPSIsReady() throws {
        app.tabBars.buttons["Home"].tap()
        let field = app.textFields["destinationSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Friend 006")
        app.buttons["Find destination"].tap()
        XCTAssertTrue(app.buttons["Directions to building"].waitForExistence(timeout: 5))
        app.buttons["Directions to building"].tap()
        XCTAssertTrue(app.buttons["End directions"].waitForExistence(timeout: 10))

        let repeatButton = app.buttons["repeatCameraGuidance"]
        XCTAssertTrue(repeatButton.waitForExistence(timeout: 5))
        let provider = app.staticTexts["outdoorRoutingProvider"]
        XCTAssertEqual(provider.value as? String, "Apple walking directions")
        XCTAssertFalse(app.buttons["continueSavedIndoorRoute"].exists)
        XCTAssertTrue(repeatButton.isHittable)
        repeatButton.tap()
        XCTAssertTrue(app.buttons["holdToTalk"].exists)
        let readSign = app.buttons["readNavigationSign"]
        XCTAssertTrue(readSign.isHittable)
        readSign.tap()
        XCTAssertTrue(app.staticTexts["navigationSignText"].waitForExistence(timeout: 5))

        app.buttons["Navigation options"].tap()
        let accessibility = app.buttons["cameraNavigationAccessibility"]
        XCTAssertTrue(accessibility.waitForExistence(timeout: 5))
        accessibility.tap()
        XCTAssertTrue(app.navigationBars["Accessibility"].waitForExistence(timeout: 5))
        app.buttons["Done"].tap()
        XCTAssertTrue(app.buttons["Map"].waitForExistence(timeout: 5))
        app.buttons["Map"].tap()
        XCTAssertTrue(app.buttons["Camera"].waitForExistence(timeout: 5))
        app.buttons["Camera"].tap()
        XCTAssertTrue(app.buttons["readNavigationSign"].waitForExistence(timeout: 5))
        let standardRoute = app.buttons["standardOutdoorRoute"]
        XCTAssertTrue(standardRoute.waitForExistence(timeout: 5))
        standardRoute.tap()
        XCTAssertTrue(standardRoute.waitForNonExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["Step-free route unavailable"].exists)
        XCTAssertEqual(provider.value as? String, "Apple walking directions")
        capture("camera-route-controls")
        app.buttons["End directions"].tap()
        XCTAssertTrue(app.buttons["Directions to building"].waitForExistence(timeout: 5))
    }

    func testKnownRoomOffersPrefilledRecording() throws {
        app.tabBars.buttons["Home"].tap()
        let field = app.textFields["destinationSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Friend 006")
        app.buttons["Find destination"].tap()
        let record = app.buttons["recordKnownDestination"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Level LL"].exists)
        record.tap()
        app.buttons["Change building"].tap()
        XCTAssertTrue(app.textFields["Building name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Building name"].value as? String, "Friend Center for Engineering Education")
        XCTAssertEqual(app.textFields["Room or destination"].value as? String, "Room 006")
        app.buttons["More options"].tap()
        XCTAssertEqual(app.textFields["Floor label (confirm from building signage)"].value as? String, "LL")
        XCTAssertFalse(app.buttons["Start recording"].isEnabled)
    }

    func testFriendRoomCardOpensRecordingInsteadOfDirectory() throws {
        app.tabBars.buttons["Home"].tap()
        let field = app.textFields["destinationSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Friend 006")
        let card = app.buttons.containing(.staticText, identifier: "Room 006 · Friend Center").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        XCTAssertTrue(app.buttons["recordKnownDestination"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Level LL"].exists)
        XCTAssertFalse(app.navigationBars["Friend Center"].exists)
    }

    func testUnmappedFriendRoomKeepsBuildingAndUnknownFloor() throws {
        app.tabBars.buttons["Home"].tap()
        let field = app.textFields["destinationSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Friend Center 005")
        app.buttons["Find destination"].tap()
        XCTAssertTrue(app.buttons["recordKnownDestination"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Friend Center"].exists)
        XCTAssertFalse(app.staticTexts["Level LL"].exists)
        app.buttons["recordKnownDestination"].tap()
        app.buttons["Change building"].tap()
        XCTAssertTrue(app.textFields["Building name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Building name"].value as? String, "Friend Center for Engineering Education")
        XCTAssertEqual(app.textFields["Room or destination"].value as? String, "Room 005")
        app.buttons["More options"].tap()
        XCTAssertEqual(app.textFields["Floor label (confirm from building signage)"].value as? String, "Floor label (optional)")
        XCTAssertFalse(app.buttons["Start recording"].isEnabled)
    }

    func testHomeSearchOffersRoomTracing() throws {
        app.tabBars.buttons["Home"].tap()
        let field = app.textFields["destinationSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Friend Center room 005")
        app.buttons["Find destination"].tap()
        XCTAssertTrue(app.buttons["recordKnownDestination"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Room 005"].exists)
        XCTAssertTrue(app.staticTexts["Friend Center"].exists)
        XCTAssertFalse(app.staticTexts["Level LL"].exists)
    }

    func testDestinationSearchMovesUpWhenEditing() throws {
        app.tabBars.buttons["Home"].tap()
        let field = app.textFields["destinationSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        let initialY = field.frame.midY
        XCTAssertGreaterThan(initialY, app.frame.height * 0.3)
        capture("21-centered-search")
        field.tap()
        field.typeText("Room 105")
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertEqual(field.value as? String, "Room 105")
        XCTAssertLessThan(field.frame.midY, initialY - 40)
        XCTAssertTrue(field.isHittable)
        capture("22-search-editing")
    }

    func testCameraAssistanceIsReachableWithoutSavedRoute() throws {
        settingsRoot()
        XCTAssertTrue(app.buttons["cameraAssistance"].waitForExistence(timeout: 5))
        app.buttons["cameraAssistance"].tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if permission.waitForExistence(timeout: 3) { permission.tap() }
        XCTAssertTrue(app.staticTexts["Camera help"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["This device does not support this spatial capture mode."].waitForExistence(timeout: 10))
        XCTAssertFalse(app.staticTexts["Position confirmed"].exists)
        capture("20-camera-help-simulator")
        app.buttons["Done"].tap()
    }
    func testHomeAccessibilityHasSimplePreferences() throws {
        app.tabBars.buttons["Home"].tap()
        app.buttons["Accessibility"].tap()
        XCTAssertTrue(app.switches["Tap to speak"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Avoid stairs"].exists)
        XCTAssertTrue(app.switches["Higher contrast"].exists)
        capture("19-accessibility-preferences")
    }
    func testAIConnectionExplainsOptInAndKeychainToken() throws {
        settingsRoot()
        reveal(app.buttons["AI connection"])
        app.buttons["AI connection"].tap()
        XCTAssertTrue(app.navigationBars["AI connection"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["agentConnectionStatus"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.switches["Cloud AI"].exists)
        XCTAssertFalse(app.secureTextFields["One-time pairing code"].exists)
        capture("17-agent-connection")
        app.buttons["Privacy"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Camera images")).firstMatch.exists)
    }
    func testShoppingAgentOfflineUsesActualDemoPlanner() throws {
        openSettingsTool("Shopping demonstration")
        let field = app.textFields["Add shampoo, then optimize my route"]
        reveal(field)
        field.tap(); field.typeText("Add milk")
        app.buttons["Ask assistant"].tap()
        let result = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Demo route:")).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 8))
        XCTAssertTrue(result.label.contains("Checkout"))
    }

    func testDestinationHomeHasGuidedMappingPath() throws {
        app.tabBars.buttons["Home"].tap()
        XCTAssertTrue(app.staticTexts["destinationPrompt"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["suggestedDestination"].exists)
        XCTAssertTrue(app.buttons["holdToTalk"].exists)
        XCTAssertFalse(app.tabBars.buttons["Scan"].exists)
        capture("18-plum-peach-home")
        openSettingsTool("Remember a route")
        XCTAssertTrue(app.staticTexts["Recording requires a LiDAR-equipped iPhone or iPad."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start recording"].isEnabled)
    }

    func testOfflineShoppingKeepsUnknownProductsUnlocated() throws {
        openSettingsTool("Shopping demonstration")
        let input = app.textViews["Add or paste shopping items"]
        input.tap(); input.typeText("milk, cereal, unknown product")
        app.buttons["Add items"].tap()
        let unknown = app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Location unknown: unknown product")).firstMatch
        reveal(unknown)
        XCTAssertTrue(unknown.label.contains("excluded from routing"))
    }

    func testBlankAreaDismissesSearchKeyboard() throws {
        app.tabBars.buttons["Home"].tap()
        let field = app.textFields["destinationSearch"]
        field.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 5))
        XCTAssertTrue(app.buttons["holdToTalk"].isHittable)
    }

    func testRouteReportRerouteAndNoRoute() throws {
        app.buttons["suggestedDestination"].tap()
        reveal(app.buttons["confirmStart"])
        app.buttons["confirmStart"].tap()
        reveal(app.buttons["showRoute"])
        app.buttons["showRoute"].tap()
        XCTAssertTrue(app.staticTexts["Via Lift A"].waitForExistence(timeout: 5))
        capture("01-route-lift-a")

        app.buttons["reportToolbar"].tap()
        app.buttons["acknowledgeReport"].tap()
        XCTAssertTrue(app.buttons["submitReport"].isEnabled)
        app.buttons["submitReport"].tap()
        XCTAssertTrue(app.staticTexts["Via Lift B"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["routeDelta"].label.contains("8"))
        capture("02-reroute-lift-b")

        app.buttons["reportToolbar"].tap()
        app.buttons["reportTarget"].tap()
        app.buttons["Lift B"].tap()
        app.buttons["acknowledgeReport"].tap()
        XCTAssertTrue(app.buttons["submitReport"].isEnabled)
        app.buttons["submitReport"].tap()
        XCTAssertTrue(app.staticTexts["noRoute"].waitForExistence(timeout: 5))
        capture("03-no-route")

        openSettingsTool("Demo building and reports")
        XCTAssertTrue(app.staticTexts["Lift availability"].waitForExistence(timeout: 5))
        capture("04-building")
        app.terminate()
        app.launch()
        openSettingsTool("Demo building and reports")
        XCTAssertTrue(app.staticTexts["Excluded from routes"].firstMatch.waitForExistence(timeout: 5))
    }

    func testCancelReportDoesNotChangeRouteAndGuidanceConfirmsPosition() throws {
        app.buttons["suggestedDestination"].tap()
        reveal(app.buttons["confirmStart"])
        app.buttons["confirmStart"].tap()
        reveal(app.buttons["showRoute"])
        app.buttons["showRoute"].tap()
        app.buttons["reportToolbar"].tap()
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.staticTexts["Via Lift A"].waitForExistence(timeout: 5))
        reveal(app.buttons["startGuidance"])
        app.buttons["startGuidance"].tap()
        XCTAssertEqual(app.staticTexts["routeHeadline"].label, "Main Lobby")
        app.buttons["confirmNext"].tap()
        XCTAssertEqual(app.staticTexts["routeHeadline"].label, "Level 1 Junction")
    }

    func testSampleOCRRequiresReviewAndReroutes() throws {
        capture("00-home")
        app.buttons["suggestedDestination"].tap()
        reveal(app.buttons["confirmStart"])
        app.buttons["confirmStart"].tap()
        reveal(app.buttons["showRoute"])
        app.buttons["showRoute"].tap()
        openSettingsTool("Manage scans and landmarks")
        capture("05-scan")
        if !app.buttons["readSign"].exists {
            reveal(app.buttons["Map tools"])
            app.buttons["Map tools"].tap()
        }
        reveal(app.buttons["readSign"])
        app.buttons["readSign"].tap()
        reveal(app.buttons["sampleSign"])
        app.buttons["sampleSign"].tap()
        XCTAssertTrue(app.staticTexts["recognizedSignText"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["recognizedSignText"].label.contains("OUT OF SERVICE"))
        reveal(app.buttons["reviewScannedReport"])
        capture("06-ocr")
        app.buttons["reviewScannedReport"].tap()
        XCTAssertFalse(app.buttons["submitReport"].isEnabled)
        reveal(app.buttons["acknowledgeReport"])
        app.buttons["acknowledgeReport"].tap()
        reveal(app.buttons["submitReport"])
        app.buttons["submitReport"].tap()
        app.buttons["Done"].tap()
        openSettingsTool("Demo navigation")
        XCTAssertTrue(app.staticTexts["Via Lift B"].waitForExistence(timeout: 5))
        openSettingsTool("Manage scans and landmarks")
        if !app.buttons["newSpatialScan"].exists {
            reveal(app.buttons["Map tools"])
            app.buttons["Map tools"].tap()
        }
        reveal(app.buttons["newSpatialScan"])
        app.buttons["newSpatialScan"].tap()
        XCTAssertTrue(app.staticTexts["LiDAR device required"].waitForExistence(timeout: 5))
        capture("07-lidar-device-state")
    }

    func testScanStartingPointThenChooseDestination() throws {
        app.buttons["scanStartingSign"].tap()
        reveal(app.buttons["sampleSign"])
        app.buttons["sampleSign"].tap()
        XCTAssertTrue(app.buttons["confirmScannedStart_entrance"].waitForExistence(timeout: 30))
        reveal(app.buttons["confirmScannedStart_entrance"])
        capture("08-scan-start")
        app.buttons["confirmScannedStart_entrance"].tap()
        app.buttons["destinationPicker"].tap()
        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 5))
        search.tap()
        search.typeText("204")
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Room 204")).firstMatch.tap()
        reveal(app.buttons["showRoute"])
        XCTAssertTrue(app.buttons["showRoute"].isEnabled)
        app.buttons["showRoute"].tap()
        XCTAssertTrue(app.staticTexts["Via Lift A"].waitForExistence(timeout: 5))
    }

    func testInlineCameraCaptureAndMapSwitch() throws {
        XCTAssertTrue(app.buttons["inlineSampleSign"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["captureNavigationSign"].isEnabled)
        capture("09-camera-start")
        app.segmentedControls["navigationSurface"].buttons["Map"].tap()
        XCTAssertFalse(app.buttons["captureNavigationSign"].exists)
        app.segmentedControls["navigationSurface"].buttons["Camera"].tap()
        app.buttons["inlineSampleSign"].tap()
        XCTAssertTrue(app.staticTexts["inlineRecognizedText"].waitForExistence(timeout: 30))
        XCTAssertTrue(app.staticTexts["inlineRecognizedText"].label.contains("ENTRANCE"))
        app.buttons["captureNavigationSign"].tap()
        XCTAssertTrue(app.buttons["inlineConfirmStart_entrance"].waitForExistence(timeout: 5))
        capture("10-camera-review")
        app.buttons["Cancel"].tap()
        app.buttons["suggestedDestination"].tap()
        XCTAssertFalse(app.buttons["showRoute"].isEnabled)
        app.buttons["captureNavigationSign"].tap()
        app.buttons["inlineConfirmStart_entrance"].tap()
        reveal(app.buttons["showRoute"])
        XCTAssertTrue(app.buttons["showRoute"].isEnabled)
        app.buttons["showRoute"].tap()
        XCTAssertTrue(app.staticTexts["Via Lift A"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["captureNavigationSign"].exists)
    }

    func testNarrationControlsPersistAndCameraReviewIsSpoken() throws {
        app.buttons["toggleNarration"].tap()
        XCTAssertEqual(app.buttons["toggleNarration"].label, "Turn narration off")
        app.buttons["inlineSampleSign"].tap()
        XCTAssertTrue(app.staticTexts["inlineRecognizedText"].waitForExistence(timeout: 30))
        app.buttons["captureNavigationSign"].tap()
        XCTAssertTrue(app.buttons["Read sign"].waitForExistence(timeout: 5))
        app.buttons["Read sign"].tap()
        app.buttons["Cancel"].tap()
        openSettingsTool("AI connection")
        let developer = app.switches["Show agent timeline"]
        reveal(developer)
        if developer.value as? String != "1" { developer.switches.firstMatch.exists ? developer.switches.firstMatch.tap() : developer.tap() }
        reveal(app.buttons["testNavigation"]); app.buttons["testNavigation"].tap()
        let lastSpeech = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Last requested speech:")).firstMatch
        reveal(lastSpeech)
        XCTAssertTrue(lastSpeech.label.contains("cancelled"))
        app.terminate()
        app.launch()
        openSettingsTool("Demo navigation")
        XCTAssertEqual(app.buttons["toggleNarration"].label, "Turn narration off")
        app.buttons["toggleNarration"].tap()
        XCTAssertEqual(app.buttons["toggleNarration"].label, "Turn narration on")
    }

    func testAccessibleCommandsRequireConfirmationAndFaceFallback() throws {
        app.buttons["openCommands"].tap()
        XCTAssertTrue(app.buttons["listenCommand"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["commandYes"].isEnabled)
        reveal(app.buttons["Narration on"])
        app.buttons["Narration on"].tap()
        app.swipeDown()
        app.buttons["commandNo"].tap()
        app.buttons["Close"].tap()
        XCTAssertEqual(app.buttons["toggleNarration"].label, "Turn narration on")
        app.buttons["openCommands"].tap()
        reveal(app.buttons["Narration on"])
        app.buttons["Narration on"].tap()
        app.swipeDown()
        app.buttons["commandYes"].tap()
        XCTAssertTrue(app.staticTexts["commandPrompt"].label.contains("Setting updated"))
        XCTAssertFalse(app.buttons["commandYes"].isEnabled)
        app.segmentedControls["commandMode"].buttons["Face"].tap()
        XCTAssertTrue(app.staticTexts["faceUnavailable"].waitForExistence(timeout: 5))
        capture("12-accessible-controls")
        app.buttons["Close"].tap()
        XCTAssertEqual(app.buttons["toggleNarration"].label, "Turn narration off")
    }

    func testScannedStartCanBeConfirmedThroughCommandPanel() throws {
        app.buttons["inlineSampleSign"].tap()
        XCTAssertTrue(app.staticTexts["inlineRecognizedText"].waitForExistence(timeout: 30))
        app.buttons["captureNavigationSign"].tap()
        app.buttons["answerSignCommands"].tap()
        XCTAssertTrue(app.staticTexts["commandPrompt"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["commandPrompt"].label.contains("Entrance"))
        app.buttons["commandYes"].tap()
        XCTAssertTrue(app.buttons["suggestedDestination"].waitForExistence(timeout: 5))
        app.buttons["suggestedDestination"].tap()
        reveal(app.buttons["showRoute"])
        XCTAssertTrue(app.buttons["showRoute"].isEnabled)
    }

    private func settingsRoot() {
        app.tabBars.buttons["Settings"].tap()
        for _ in 0..<5 {
            if app.navigationBars["Settings"].exists { break }
            let back = app.navigationBars.buttons.element(boundBy: 0)
            if back.exists { back.tap() }
        }
    }
    private func openSettingsTool(_ title: String) {
        settingsRoot()
        let renamed = ["Shopping demonstration": "Shopping demo", "Demo building and reports": "Demo building & reports", "Remember a route": "Record a route", "Manage scans and landmarks": "Saved rooms & maps"]
        let label = renamed[title] ?? title
        if ["Demo navigation", "Demo building & reports", "Shopping demo"].contains(label) {
            app.buttons["Advanced & testing"].tap()
        }
        reveal(app.buttons[label]); app.buttons[label].tap()
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 {
            let top = app.navigationBars.firstMatch.exists ? app.navigationBars.firstMatch.frame.maxY : 100
            if element.exists && element.frame.minY < top {
                app.swipeDown()
            } else if element.isHittable && element.frame.maxY < app.frame.maxY - 110 { return }
            else { app.swipeUp() }
        }
        XCTAssertTrue(element.isHittable, "Control is not reachable: \(element)")
    }
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
