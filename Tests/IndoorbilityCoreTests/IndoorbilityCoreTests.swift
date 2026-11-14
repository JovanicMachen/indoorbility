import XCTest
@testable import IndoorbilityCore

final class IndoorbilityCoreTests: XCTestCase {
    func testNarrationPrioritizesUnavailableRouteAndLostPosition() throws {
        var session = try NavigationSession(building: Building.demo())
        try session.confirmCheckpoint("entrance")
        try session.selectDestination("room_204")
        session.startGuidance()
        var previous = session
        try session.confirmReport(BarrierReport(targetEdgeID: "lift_a"))
        XCTAssertTrue(try XCTUnwrap(NavigationNarration.update(from: previous, to: session, instruction: "Next checkpoint.")).contains("Route recalculated"))
        previous = session
        try session.confirmReport(BarrierReport(targetEdgeID: "lift_b"))
        XCTAssertTrue(try XCTUnwrap(NavigationNarration.update(from: previous, to: session, instruction: "Stale instruction")).hasPrefix("No route is available"))
        previous = session
        session.forgetPosition()
        XCTAssertTrue(try XCTUnwrap(NavigationNarration.update(from: previous, to: session, instruction: "Stale instruction")).hasPrefix("Starting point is not confirmed"))
    }

    func testNarrationArrivalPauseAndUnrelatedPreferences() throws {
        var session = try NavigationSession(building: Building.demo())
        try session.confirmCheckpoint("entrance")
        try session.selectDestination("room_204")
        session.startGuidance()
        var previous = session
        session.stopGuidance()
        XCTAssertTrue(try XCTUnwrap(NavigationNarration.update(from: previous, to: session, instruction: "Next")).contains("paused"))
        previous = session
        var preferences = session.saved.preferences
        preferences.haptics.toggle()
        try session.setPreferences(preferences)
        XCTAssertNil(NavigationNarration.update(from: previous, to: session, instruction: "Next"))
        previous = session
        try session.confirmCheckpoint("room_204")
        XCTAssertTrue(try XCTUnwrap(NavigationNarration.update(from: previous, to: session, instruction: "Next")).hasPrefix("Arrival confirmed at Room 204"))
    }

    func testDemoRoutesAndStrictStairConstraint() throws {
        let map = try Building.demo()
        let initial = try XCTUnwrap(Router.plan(in: map, from: "entrance", to: "room_204"))
        XCTAssertEqual(initial.cost, 39)
        XCTAssertEqual(initial.nodeIDs, ["entrance", "lobby", "junction_1", "lift_a_1", "lift_a_2", "junction_2", "room_204"])
        let alternate = try XCTUnwrap(Router.plan(in: map, from: "entrance", to: "room_204", excluding: ["lift_a"]))
        XCTAssertEqual(alternate.cost, 47)
        XCTAssertTrue(alternate.edgeIDs.contains("lift_b"))
        XCTAssertNil(try Router.plan(in: map, from: "entrance", to: "room_204", excluding: ["lift_a", "lift_b"]))
        let stairs = try XCTUnwrap(Router.plan(in: map, from: "entrance", to: "room_204", avoidStairs: false))
        XCTAssertEqual(stairs.cost, 33)
        XCTAssertTrue(stairs.edgeIDs.contains("stair_connector"))
    }
    func testReverseArrivalAndUnknownCheckpoints() throws {
        let map = try Building.demo()
        XCTAssertEqual(try Router.plan(in: map, from: "room_204", to: "entrance")?.cost, 39)
        XCTAssertEqual(try Router.plan(in: map, from: "entrance", to: "entrance")?.cost, 0)
        XCTAssertThrowsError(try Router.plan(in: map, from: "absent", to: "room_204"))
        XCTAssertThrowsError(try Router.plan(in: map, from: "entrance", to: "absent"))
    }
    func testBlockedUnverifiedAndDisconnectedMaps() throws {
        var map = try Building.demo()
        map.edges[5].blocked = true
        XCTAssertEqual(try Router.plan(in: map, from: "entrance", to: "room_204")?.cost, 47)
        map.edges[6].verified = false
        XCTAssertNil(try Router.plan(in: map, from: "entrance", to: "room_204"))
        map.edges = []
        XCTAssertNil(try Router.plan(in: map, from: "entrance", to: "room_204"))
    }
    func testMalformedMapsRejected() throws {
        let original = try JSONSerialization.jsonObject(with: JSONEncoder().encode(Building.demo())) as! [String: Any]
        var mutations: [[String: Any]] = []
        var version = original; version["schema_version"] = 2; mutations.append(version)
        var duplicates = original
        var nodes = original["nodes"] as! [[String: Any]]
        nodes.append(nodes[0]); duplicates["nodes"] = nodes; mutations.append(duplicates)
        for (key, value) in [("floor", 99 as Any), ("x", "nan" as Any)] {
            var copy = original; var n = original["nodes"] as! [[String: Any]]
            n[0][key] = value; copy["nodes"] = n; mutations.append(copy)
        }
        for (key, value) in [("from", "missing" as Any), ("distance", -1 as Any), ("distance", 0 as Any), ("kind", "teleport" as Any), ("verified", "true" as Any)] {
            var copy = original; var e = original["edges"] as! [[String: Any]]
            e[0][key] = value; copy["edges"] = e; mutations.append(copy)
        }
        for mutation in mutations {
            XCTAssertThrowsError(try Building.load(JSONSerialization.data(withJSONObject: mutation)))
        }
    }
    func testDuplicateFloorsEdgesAndNonfiniteCostRejected() throws {
        var map = try Building.demo(); map.floors.append(map.floors[0])
        XCTAssertThrowsError(try map.validate())
        map = try Building.demo(); map.edges.append(map.edges[0])
        XCTAssertThrowsError(try map.validate())
        let bad = Connection(id: "bad", from: "entrance", to: "lobby", distance: .infinity, kind: .hallway, verified: true, blocked: false)
        map = try Building.demo(); map.edges.append(bad)
        XCTAssertThrowsError(try map.validate())
    }
    func testStableTiesRegardlessOfEdgeOrder() throws {
        var map = try Building.demo()
        map.edges = [
            Connection(id: "a", from: "entrance", to: "lobby", distance: 1, kind: .hallway, verified: true, blocked: false),
            Connection(id: "b", from: "lobby", to: "room_204", distance: 1, kind: .hallway, verified: true, blocked: false),
            Connection(id: "c", from: "entrance", to: "junction_1", distance: 1, kind: .hallway, verified: true, blocked: false),
            Connection(id: "d", from: "junction_1", to: "room_204", distance: 1, kind: .hallway, verified: true, blocked: false)
        ]
        let route = try Router.plan(in: map, from: "entrance", to: "room_204")
        map.edges.reverse()
        XCTAssertEqual(route, try Router.plan(in: map, from: "entrance", to: "room_204"))
    }
    func testReportLifecycleAndOverlappingClosures() throws {
        var session = try readySession()
        let proposal = BarrierReport(targetEdgeID: "lift_a")
        XCTAssertEqual(session.route?.cost, 39) // Proposed sheet has no effect.
        try session.confirmReport(proposal)
        XCTAssertEqual(session.route?.cost, 47)
        XCTAssertEqual(session.routeDelta, 8)
        XCTAssertEqual(session.checkpointID, "entrance")
        let duplicate = BarrierReport(targetEdgeID: "lift_a")
        try session.confirmReport(duplicate)
        try session.resolveReport(proposal.id)
        XCTAssertEqual(session.route?.cost, 47)
        try session.resolveReport(duplicate.id)
        XCTAssertEqual(session.route?.cost, 39)
        XCTAssertThrowsError(try session.confirmReport(proposal))
    }
    func testBothClosuresStopGuidanceAndPreferencesAllowStairs() throws {
        var session = try readySession()
        session.startGuidance()
        XCTAssertTrue(session.isGuiding)
        try session.confirmReport(BarrierReport(targetEdgeID: "lift_a"))
        try session.confirmReport(BarrierReport(targetEdgeID: "lift_b"))
        XCTAssertNil(session.route)
        XCTAssertNil(session.nextCheckpoint)
        XCTAssertFalse(session.isGuiding)
        var preferences = session.saved.preferences; preferences.avoidStairs = false
        try session.setPreferences(preferences)
        XCTAssertEqual(session.route?.cost, 33)
    }
    func testCheckpointReroutesWithoutFalsePosition() throws {
        var session = try readySession()
        try session.confirmCheckpoint("lobby", at: Date(timeIntervalSince1970: 10))
        XCTAssertEqual(session.route?.cost, 31)
        XCTAssertNil(session.routeDelta)
        try session.confirmReport(BarrierReport(targetEdgeID: "lift_a"))
        XCTAssertEqual(session.route?.cost, 39)
        XCTAssertEqual(session.route?.nodeIDs.first, "lobby")
        XCTAssertEqual(session.checkpointDate, Date(timeIntervalSince1970: 10))
        session.forgetPosition()
        XCTAssertNil(session.route)
        XCTAssertNil(session.nextCheckpoint)
        XCTAssertTrue(session.needsPosition)
    }
    func testArrivalAndDestinationChangeClearGuidance() throws {
        var session = try readySession()
        session.startGuidance()
        try session.confirmCheckpoint("room_204")
        XCTAssertTrue(session.arrived)
        XCTAssertFalse(session.isGuiding)
        try session.selectDestination("entrance")
        XCTAssertFalse(session.arrived)
        XCTAssertFalse(session.isGuiding)
    }
    func testResolvingReportsNeverReopensBaseClosure() throws {
        var map = try Building.demo(); map.edges[5].blocked = true
        var session = try NavigationSession(building: map)
        try session.confirmCheckpoint("entrance"); try session.selectDestination("room_204")
        let report = BarrierReport(targetEdgeID: "lift_a")
        try session.confirmReport(report); try session.resolveReport(report.id)
        XCTAssertEqual(session.route?.cost, 47)
    }
    func testPersistenceRoundTripAndUnknownPositionAfterRelaunch() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storage = FileStatePersistence(url: directory.appendingPathComponent("state.json"))
        var session = try readySession()
        XCTAssertNil(try storage.load(for: session.building))
        try session.confirmReport(BarrierReport(targetEdgeID: "lift_a"))
        var prefs = session.saved.preferences; prefs.speech = true
        try session.setPreferences(prefs)
        try storage.save(session.saved)
        let restored = try XCTUnwrap(storage.load(for: session.building))
        XCTAssertEqual(restored, session.saved)
        let fresh = try NavigationSession(building: session.building, saved: restored)
        XCTAssertTrue(fresh.needsPosition)
        XCTAssertNil(fresh.route)
    }
    func testCorruptAndWrongBuildingStateArePreserved() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let storage = FileStatePersistence(url: url)
        let corrupt = Data("invalid json".utf8)
        try corrupt.write(to: url)
        XCTAssertThrowsError(try storage.load(for: Building.demo()))
        XCTAssertEqual(try Data(contentsOf: url), corrupt)
        try storage.save(SavedState(buildingID: "another-building"))
        XCTAssertThrowsError(try storage.load(for: Building.demo()))
    }
    func testExplicitRecoveryPreservesOriginalBytes() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("state.json")
        let bytes = Data("corrupt but valuable original".utf8)
        try bytes.write(to: url)
        let storage = FileStatePersistence(url: url)
        let backup = try XCTUnwrap(storage.backupForRecovery())
        XCTAssertEqual(try Data(contentsOf: backup), bytes)
        XCTAssertNil(try storage.load(for: Building.demo()))
        try storage.save(SavedState(buildingID: Building.demo().buildingID))
        XCTAssertEqual(try Data(contentsOf: backup), bytes)
    }
    func testWriteFailureIsThrown() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("not-a-directory")
        try Data().write(to: file)
        XCTAssertThrowsError(try FileStatePersistence(url: file.appendingPathComponent("state.json")).save(SavedState(buildingID: "demo")))
    }
    func testSearchHasNoFabricatedMatchesAndResetClearsDemo() throws {
        let map = try Building.demo()
        XCTAssertEqual(map.destinations(matching: "ROOM 204").map(\.id), ["room_204"])
        XCTAssertTrue(map.destinations(matching: "room 999").isEmpty)
        XCTAssertEqual(map.destinations(matching: "Lift A").count, 2)
        var session = try readySession()
        try session.confirmReport(BarrierReport(targetEdgeID: "lift_a"))
        session.reset()
        XCTAssertTrue(session.saved.reports.isEmpty)
        XCTAssertNil(session.destinationID)
        XCTAssertTrue(session.needsPosition)
    }
    func testOCRSuggestsOnlyUnambiguousKnownOutage() throws {
        let map = try Building.demo()
        XCTAssertEqual(BarrierInterpreter.interpret("LIFT A\nOUT OF SERVICE", in: map).targetEdgeID, "lift_a")
        XCTAssertEqual(BarrierInterpreter.interpret("Elevator B closed", in: map).targetEdgeID, "lift_b")
        for text in ["Lift A not out of service", "Lift A closed but now open", "Lift A and Lift B closed", "Lift C unavailable", "Room 204", "Lift AB closed"] {
            XCTAssertNil(BarrierInterpreter.interpret(text, in: map).targetEdgeID, text)
        }
    }
    func testScanDistanceDoesNotBridgeTrackingGaps() throws {
        let draft = ScanDraft(name: "Test", usesLiDAR: true, hasWorldMap: true, samples: [
            ScanSample(position: .init(x: 0, y: 0, z: 0), segment: 0),
            ScanSample(position: .init(x: 3, y: 0, z: 4), segment: 0),
            ScanSample(position: .init(x: 100, y: 0, z: 0), segment: 1),
            ScanSample(position: .init(x: 103, y: 0, z: 4), segment: 1)
        ], landmarks: [], meshVertexCount: 3, meshTriangleCount: 1)
        try draft.validate()
        XCTAssertEqual(draft.recordedDistance, 10)
        XCTAssertEqual(try JSONDecoder().decode(ScanDraft.self, from: JSONEncoder().encode(draft)), draft)
    }
    func testScanRejectsNonfiniteCoordinates() {
        let draft = ScanDraft(name: "Bad", usesLiDAR: true, hasWorldMap: true,
                              samples: [.init(position: .init(x: .infinity, y: 0, z: 0), segment: 0)], landmarks: [], meshVertexCount: 0, meshTriangleCount: 0)
        XCTAssertThrowsError(try draft.validate())
    }
    func testSignLocationMatchingRequiresCompleteLabel() throws {
        let map = try Building.demo()
        XCTAssertEqual(SignLocationMatcher.candidates(in: "ROOM 204", building: map).map(\.id), ["room_204"])
        XCTAssertEqual(SignLocationMatcher.candidates(in: "ENTRANCE\nLEARNING CENTER", building: map).map(\.id), ["entrance"])
        XCTAssertTrue(SignLocationMatcher.candidates(in: "Room 2045", building: map).isEmpty)
        XCTAssertTrue(SignLocationMatcher.candidates(in: "Lift A", building: map).isEmpty)
        XCTAssertEqual(SignLocationMatcher.candidates(in: "Lift A — Level 2", building: map).map(\.id), ["lift_a_2"])
        XCTAssertTrue(SignLocationMatcher.candidates(in: "Unreadable sign", building: map).isEmpty)
    }
    private func readySession() throws -> NavigationSession {
        var session = try NavigationSession(building: Building.demo())
        try session.confirmCheckpoint("entrance")
        try session.selectDestination("room_204")
        return session
    }
}
