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
        XCTAssertEqual(app.staticTexts["testGuidanceInstruction"].label, "Continue straight for 100 meters.")
        for _ in 0..<8 { app.buttons["Advance position"].tap() }
        XCTAssertEqual(app.staticTexts["testGuidanceInstruction"].label, "Continue straight. In 20 meters, turn left.")
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
        let building = app.textFields["Building name"]
        XCTAssertTrue(building.waitForExistence(timeout: 5))
        building.tap(); building.typeText("Friend Center")
        let destination = app.textFields["Room or destination"]
        destination.tap(); destination.typeText("Library door")
        let start = app.textFields["Start location"]
        start.tap(); start.typeText("Main elevator")
        XCTAssertEqual(building.value as? String, "Friend Center")
        XCTAssertEqual(destination.value as? String, "Library door")
        XCTAssertEqual(start.value as? String, "Main elevator")
        XCTAssertFalse(app.textFields["Floor label (confirm from building signage)"].isHittable)
        XCTAssertFalse(app.buttons["Start recording"].isEnabled) // Simulator cannot record LiDAR.
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
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textFields["Building name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Building name"].value as? String, "Friend Center for Engineering Education")
        XCTAssertEqual(app.textFields["Room or destination"].value as? String, "Room 006")
        app.buttons["Optional details"].tap()
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
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textFields["Building name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Building name"].value as? String, "Friend Center for Engineering Education")
        XCTAssertEqual(app.textFields["Room or destination"].value as? String, "Room 005")
        app.buttons["Optional details"].tap()
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
        XCTAssertTrue(app.secureTextFields["One-time pairing code"].exists)
        XCTAssertTrue(app.switches["Cloud AI"].exists)
        capture("17-agent-connection")
        app.buttons["Privacy & pairing"].tap()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Never enter an OpenAI API key")).firstMatch.exists)
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
