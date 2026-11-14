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
        XCTAssertEqual(app.staticTexts["testGuidanceInstruction"].label, "In 20 meters, turn left.")
        let mute = app.switches["Mute all app sound"]
        reveal(mute)
        if mute.value as? String != "1" { mute.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap() }
        XCTAssertEqual(mute.value as? String, "1")
        mute.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5)).tap()
    }

    func testKnownRoomOffersPrefilledRecording() throws {
        app.tabBars.buttons["Home"].tap()
        let field = app.textFields["destinationSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Friend 006")
        app.buttons["Find destination"].tap()
        let record = app.buttons["recordKnownDestination"]
        XCTAssertTrue(record.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Friend Center · Level LL"].exists)
        record.tap()
        XCTAssertTrue(app.textFields["Building name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Building name"].value as? String, "Friend Center for Engineering Education")
        XCTAssertEqual(app.textFields["Room or destination"].value as? String, "Room 006")
        XCTAssertEqual(app.textFields["Floor label (confirm from building signage)"].value as? String, "LL")
        XCTAssertFalse(app.buttons["Start mapping"].isEnabled)
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
        XCTAssertTrue(app.staticTexts["Friend Center · Level LL"].exists)
        XCTAssertFalse(app.navigationBars["Friend Center"].exists)
    }

    func testUnmappedFriendRoomKeepsBuildingAndUnknownFloor() throws {
        app.tabBars.buttons["Home"].tap()
        let field = app.textFields["destinationSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Friend Center 005")
        app.buttons["Find destination"].tap()
        XCTAssertTrue(app.buttons["recordKnownDestination"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Friend Center · confirm the floor"].exists)
        app.buttons["recordKnownDestination"].tap()
        XCTAssertTrue(app.textFields["Building name"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["Building name"].value as? String, "Friend Center for Engineering Education")
        XCTAssertEqual(app.textFields["Room or destination"].value as? String, "Room 005")
        XCTAssertEqual(app.textFields["Floor label (confirm from building signage)"].value as? String, "Floor")
        XCTAssertFalse(app.buttons["Start mapping"].isEnabled)
    }

    func testMapSearchOffersRoomTracing() throws {
        app.tabBars.buttons["Home"].tap()
        app.buttons["Map"].firstMatch.tap()
        let field = app.textFields["mapDestinationSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("Friend Center room 005")
        app.buttons["Find"].tap()
        XCTAssertTrue(app.buttons["recordKnownDestination"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Room 005"].exists)
        XCTAssertTrue(app.staticTexts["Friend Center · confirm the floor"].exists)
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
        app.tabBars.buttons["Help"].tap()
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
        XCTAssertTrue(app.switches["Tap instead of holding to speak"].waitForExistence(timeout: 5))
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
        XCTAssertTrue(app.switches["Use cloud navigation assistant"].exists)
        capture("17-agent-connection")
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
        XCTAssertTrue(app.staticTexts["Mapping requires a physical LiDAR-equipped iPhone or iPad."].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Start mapping"].isEnabled)
    }

    func testLocalAssistantRejectsUnknownPlaceAndOptimizesShopping() throws {
        app.tabBars.buttons["Help"].tap()
        let request = app.descendants(matching: .any).matching(identifier: "assistantRequest").firstMatch
        request.tap(); request.typeText("Take me to Room 999")
        reveal(app.buttons["assistantPlan"])
        app.buttons["assistantPlan"].tap()
        capture("23-assistant-answer")
        reveal(app.staticTexts["assistantResponse"])
        XCTAssertTrue(app.staticTexts["assistantResponse"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["assistantResponse"].label.contains("verified location"))
        request.tap()
        request.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: "Take me to Room 999".count))
        request.typeText("Buy milk, cereal, unknown product")
        app.buttons["assistantPlan"].tap()
        XCTAssertTrue(app.staticTexts["Fictional store simulation"].waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "Location unknown: unknown product")).firstMatch.exists)
        capture("16-shopping-demo")
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
        settingsRoot()
        reveal(app.staticTexts["lastNarration"])
        XCTAssertTrue(app.staticTexts["lastNarration"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["lastNarration"].label.contains("cancelled"))
        // Wait for SwiftUI to render the new spoken-preview text after the tap.
        reveal(app.buttons["previewNarration"])
        app.buttons["previewNarration"].tap()
        let ready = expectation(for: NSPredicate(format: "label CONTAINS %@", "narration is ready"), evaluatedWith: app.staticTexts["lastNarration"])
        wait(for: [ready], timeout: 5)
        capture("11-narration-settings")
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
