# Destination-first navigation and LiDAR update

## Current indoor controls and short-distance correction

The indoor navigation dropdown now contains **Map** and **Camera** only. The duplicate inline Show camera action and previous menu sheets/actions are removed from this screen. Repeat, microphone and Stop/Done remain direct controls. Settings and the existing agent/navigation engine are unchanged; older menu descriptions below document prior iterations.

The preview used integer rounding on the first recorded bend distance, so a sub-meter bend could display “Straight for 0 meters.” Turn extraction now requires at least 0.75 m of measured heading support on both sides, rejecting tiny start wobble while retaining genuine one-metre early turns. An actual short first turn is described as “At the recorded start, turn …” with the corresponding turn arrow. Positive sub-half-unit distances display “less than 1 meter/foot”; invalid distances display “distance unavailable” rather than a fabricated zero. Full route geometry, recorded endpoints and live progress remain unchanged.

Apple/Core Location fixes continue to drive the existing outdoor map dot and route follower. Saved indoor scans use local AR metres; their optional GPS entrance record has no global yaw/floor alignment for the interior path. A GPS dot is therefore not substituted for a relocalized indoor position. The indoor map's blue dot remains tied to the same trusted pose used for distance and directions.

## Simplified recorded walk — current default

Indoor routes immediately show the recorded top-down path with a single instruction card. The main controls are Repeat, Speak and Stop/Done. Once position matches, the arrow and live distance describe the next measured turn or endpoint. No live position or walking command is invented before matching. The camera, diagnostics and recovery remain optional tools. No 3D mesh is displayed by default and camera route-marker geometry is not built while that overlay is hidden. Voice/agent commands and accessibility controls remain available. Turning the phone does not change the recorded start, destination or planned maneuver sequence.

Before initial matching, the path now includes static direction chevrons and the card shows the first recorded leg, explicitly labeled “Route preview · from recorded start.” Distances in that preview are from the recording, never guessed distances from the phone. Repeat and VoiceOver also identify the preview and unmatched position. Preview reads cannot update progress, issue live turn cues, claim arrival or start travel audio. After a previously established position is lost, recovery warnings take precedence rather than reverting to a start-of-route preview. Live guidance can begin near any uniquely matched point on the saved route, not just the exact start; the existing 1.2 m route-distance, floor and confidence requirements remain intact.

The initial follower/turn plan is reused instead of constructed twice, static map chevrons are cached once (bounded at 120), and derived positioning-archive encoding/compression runs at background priority after the usable map has returned. Two independent two-second settling checks now run concurrently and must both pass. Synthetic integration measurement: the previous serial windows started at 4.0 seconds; concurrent windows start at 2.0 seconds, **excluding ARKit's actual map-load/relocalization time**. An impossible position jump restarts settling. This is not an on-device sensor-latency or accuracy measurement.

Preview/startup validation: all 193 core tests and two targeted simulator UI tests passed. Tests cover left/right previews without a live position, unchanged progress/arrival guards, matched mid-route starts 0.8 m off the centerline, VoiceOver preview labeling and visible recorded direction arrows. The final signed build was installed and launched on the paired iPhone; real walking accuracy and real relocalization duration still require a physical walk.

At the existing sustained, trusted endpoint threshold, the app says “You’ve arrived at the recorded endpoint” and completes the walk without another form or sign-confirmation button. This geometric completion does **not** verify a room sign or increment independently verified room visits. Existing OCR-backed room confirmation can still do that when its evidence is available. Position matching, stale-pose rejection, floor/route checks and tracking-loss recovery remain required.

An optional disposable binary navigation cache stores the already bounded measured surface-reference samples and a low-detail outline (at most 1,500 edges, down from 12,000). It is limited to 6 MB and invalidated on a source file size/date change. Surface reference points retain their precision; only display detail is reduced. Original mesh files, saved routes and ARWorldMaps are not rewritten, reduced or deleted. Only an existing compact surface cache is read during startup; an uncached full mesh conversion waits until positioning succeeds, independently of the route follower. Corrupt/stale caches are rejected. This is not a measured physical-device latency or accuracy claim.

### Loading and relocalization correction

The earlier simple mode deliberately hid both camera and map, leaving a large empty area while matching. That is now replaced by the immediate recorded-path view. Opening the saved positioning archive, matching the surroundings and startup failure have distinct messages. After 20 seconds of unsuccessful matching, a retry action is visible; the route and destination stay selected. A camera preview is available while matching. Backgrounding previously paused tracking without restarting it on activation; an active-scene task now resumes the same session, with starts serialized across in-flight archive loads.

Navigation previously enabled classified mesh reconstruction even though no mesh was displayed. Playback now keeps world tracking and live depth without rebuilding triangle meshes. A separate derived positioning archive removes only ARMeshAnchor objects from a newly decoded navigation copy, retains raw feature points and all non-mesh anchors, and uses lossless LZFSE compression. Its source size/date is checked on each opening; an invalid cache falls back to the original. Original scan files and exact route geometry are untouched. Outdoor-to-indoor preloading uses this same loader. Apple's [world-map documentation](https://developer.apple.com/documentation/arkit/arworldmap) distinguishes saved anchors from positioning state, and [initialWorldMap](https://developer.apple.com/documentation/arkit/arpositionaltrackingconfiguration/initialworldmap) still requires real relocalization before directions can start. Compression cannot establish a user's position in the wrong room or with an unmatched camera view.

Validation: 190 core tests passed, including lossless archive round trips, unchanged source bytes, stale-source rejection and corrupt-cache fallback; two targeted UI tests passed, including immediate route visibility and retry without losing that route. The signed build was installed and launched on the paired iPhone. Simulator screenshots verify layout only. No physical relocalization, real-scan compression ratio, walking accuracy or on-device latency result has been measured for this change.

## Saved indoor map navigation — latest layout

Saved room routes now open on a top-down map rather than the camera matching screen described below. The map projects captured vertical LiDAR surfaces and the existing recorded route in local AR coordinates. It supports pan, zoom, full-route overview and Recenter. Panning does not trigger the camera screen's swipe-to-go-back gesture. The camera stays mounted under the map, so switching views preserves its AR session.

One bottom card shows the current instruction, trusted remaining distance, Repeat, microphone and camera/map switch. Before localization, the saved route remains visible but no live position or directional maneuver is drawn. Matching uses the saved ARWorldMap, sustained stable tracking and the follower's existing unique-segment checks. Normal tracking after loading that map is accepted even if the app did not observe an intermediate relocalizing callback. Initial matching interruptions remain retryable; established tracking loss and surface discrepancies still stop untrustworthy guidance.

Map display and surface comparison share one bounded background mesh load. The display is not geographic GPS and does not infer walkability from a mesh. Physical relocalization, walking accuracy and turn timing still require a real saved route on a LiDAR iPhone; synthetic UI fixtures cannot establish those results.

### Waypoint indoor-positioning comparison

Reviewed `sachin-khanal/uva-gwc-ghh-2026` at commit `8778e967a080d195d88b2726da57e0e9fab483f9`: [Relocalizer.swift](https://github.com/sachin-khanal/uva-gwc-ghh-2026/blob/8778e967a080d195d88b2726da57e0e9fab483f9/Waypoint/Relocalization/Relocalizer.swift), [NavigationController.swift](https://github.com/sachin-khanal/uva-gwc-ghh-2026/blob/8778e967a080d195d88b2726da57e0e9fab483f9/Waypoint/Navigation/NavigationController.swift), and `Routing/StartGate.swift`. Its indoor position comes from a loaded ARWorldMap and live ARKit camera pose, transformed into the saved map frame. This is the positioning source already used here. Indoorbility already starts from a uniquely matched current path position, rather than walking back to the recording start.

Adapted the automatic recovery behavior with an independent implementation in the existing follower/model. A brief loss hides position and stops directions/audio immediately. Automatic continuation requires the same saved map frame, two seconds of stable measured poses, displacement within 1.2 m of the last trusted pose, loss no longer than ten seconds, and a unique route projection within 1.5 m of retained progress. Existing floor, jump, closure and ambiguity checks remain active. Surface mismatch, established off-route movement, untrusted pose jumps and manual coordinate alignments do not arm automatic recovery. If recovery fails, destination/route remain selected. When the saved map has actually matched, a single nearby saved landmark can validate recovery; two-point alignment remains the fallback when there is no saved-frame match.

Waypoint also contains coarse image-fingerprint alignment, repeated graph replanning and camera-relative steering. These were not imported: existing scans do not contain those fingerprints, and continuously changing camera-relative steering conflicts with Indoorbility's stable route-segment instructions. No reference project code was copied wholesale; no service, dependency, map format, agent or branding was replaced. Physical behavior remains unverified until tested in the recorded space.

Recovery-adaptation validation: 186 Swift tests, 31 backend tests, and two targeted simulator UI regressions passed. The signed iPhone build also passed. Recovery regressions include sustained tracking, interrupted settling, teleport rejection, wrong floors, overlapping segments, manual-frame rejection, unchanged destination/progress, and stationary phone rotation after recovery. UI tests cover the saved room opening the indoor map without endpoint setup and the outdoor camera controls. These are automated checks, not physical walking evidence.

### Map display lag and app icon

The map previously rebuilt its complete SwiftUI Path and allocated/scanned coordinate arrays for its bounds on position-driven redraws. `IndoorRouteMapDrawing` now caches both until the destination changes. The full verified follower path, confidence thresholds, walls, live position updates and AR session are unchanged. Destination changes rebuild the drawing even when the underlying saved route ID is unchanged. Saved-mesh size and background preparation duration are available in the existing diagnostics.

Reproducible isolated benchmark: `swiftc -Onone scripts/benchmark_indoor_map.swift -o /tmp/indoor-map-bench`, then `/tmp/indoor-map-bench`. On this Mac, 1,000 synthetic updates with 5,000 points took 3,590.647 ms rebuilding versus 3.797 ms using the cache, including its initial construction. With 50,000 synthetic points: 35,942.950 ms versus 36.727 ms. This isolates CPU drawing preparation; it excludes Canvas rasterization, GPU work, ARKit, map-file decoding and physical phone behavior. It is not an overall app speedup or accuracy measurement. A later metadata-only device check found mesh files up to approximately 72 MB and positioning maps up to 59 MB. Large inputs can contribute to opening time; file sizes do not measure decoder latency, live sensor performance or thermal throttling. No scan contents were copied for this check.

The supplied Indoorbility logo is the native app's AppIcon asset, resized to an opaque 1024-pixel square without changing the artwork. Debug/Release asset settings and the project generator include it. No website branding was changed.

Indoor guidance now uses the same large direction badge as outdoor navigation in both map and camera views. It displays the current segment instruction (straight, left, right, turn around, stairs or arrival), with an arrival checkmark only after confirmed arrival. The badge is hidden until the saved map has a fresh confirmed position; tracking-loss/off-route warnings do not become guessed forward arrows. The map sits below the badge instead of being covered by it. Recorded entrance and destination markers remain fixed while measured progress changes; they are never exchanged by phone rotation. Extended end-to-end route tests check arrow direction and endpoint identity through different phone headings, along with confirmed arrival and tracking loss.

Implementation date: November 14, 2026. This modifies the existing Xcode app, core package and UI tests. The existing FastAPI/OpenAI agent, Keychain access-token configuration, deterministic router, closure persistence, Google discovery and saved scans remain in place. No Supabase was added.

## What changed

- Home now opens to “Where would you like to go?”, a single search field, a large hold-to-speak microphone, Map and Accessibility. The three tabs are Home, Help and Settings. Real saved rooms and real outdoor search results replace primary-screen demos. Mapping, saved scans, building reports and explicitly labeled demonstrations remain in Settings.
- Plum/Peach controls, warm light background, dark-mode colors, original animated edge glow, Reduce Motion handling, higher-contrast controls, Dynamic Type and VoiceOver/tap-to-talk alternative.
- Typed and spoken requests use the same building-qualified room resolver and existing connected agent, with deterministic offline fallback. A pending exact destination must be confirmed. Confirmations expire after 30 seconds; consumed, replaced or declined proposals cannot start another trip. Floor names come from optional manually confirmed metadata, never room-number digits. Existing scans without metadata show unknown.
- Indoor confirmation opens full-screen camera localization. Outdoor confirmation begins existing outdoor location/directions. GPS alone never authorizes indoor positioning. Saved entrance markers use manually confirmed entrance coordinates; no fabricated room map is shown.
- Live route changes now ask Yes/No before activating. Yes cancels obsolete agent output/speech, revalidates against the latest pose/closures, changes the existing follower and retains the ARSession. An explicitly different building is rejected. “Wrong building” pauses guidance and asks for landmark verification.
- The same camera view stays mounted beneath the Map overlay. Accessibility, diagnostics, reporting and agent sheets do not create a replacement navigation session. Sign reading uses the current AR frame; the separate scanner remains in Settings. Backgrounding, ending navigation and explicit tracking restart intentionally pause/reset as appropriate.
- Floating 3D chevrons use reviewed route coordinates transformed through the inverse live-to-saved alignment. They are hidden while alignment/tracking is uncertain, off-route, blocked or stale. They float 0.5 m below the recorded phone-height trace; they are NOT certified floor-surface or obstacle-free-path markers.
- Help accepts typed or spoken grounded questions through the existing agent. Camera help is directly accessible without a saved route. No global building knowledge or unrestricted factual chat capability is implied.

## Actual sensor data consumed

`App/SpatialScanning.swift` owns the navigation ARSCNView/ARSession. Capability checks choose supported sceneDepth/smoothedSceneDepth combinations and meshWithClassification → mesh fallback. Unsupported devices do not claim LiDAR.

`App/SceneAwarenessService.swift` consumes actual `ARFrame.sceneDepth` (smoothed depth only as fallback), Float32 `depthMap`, UInt8 `confidenceMap`, camera intrinsics, image resolution, camera transform and capture timestamp. It samples every second pixel in the central 20% of the depth image, requires high-confidence samples and at least 65% valid coverage, and uses a median measured surface distance. Camera forward pitch must be within the configured upright range. No object identities are generated from depth.

The depth job runs off the main actor, capped at one job at a time and a 100 ms sampling interval. Busy frames are skipped rather than queued. Late results (>500 ms) are rejected. This is a processing policy, not a measured device frame-rate claim. Pose delivery remains separate; follower updates are capped at 20 Hz. SwiftUI diagnostic updates are capped at 10 Hz. Existing pose/jump/off-route thresholds were not loosened to manufacture stability.

Mesh rendering uses ARKit's Metal vertex buffer directly, avoiding the prior main-thread vertex-by-vertex copy, and is throttled per anchor. Full mesh export iterates off the main actor. Mapping displays measured outlines continuously. Requested short previews remain available. OCR is bounded background work; entrance matching now retains the capture timestamp instead of incorrectly refreshing old evidence at completion.

Optional central depth points are projected with the captured camera calibration/pose, not drawn at invented screen positions. Diagnostics show real capability, AR tracking reason, mapping state, route alignment, depth dimensions/age, confidence coverage, mesh count, frame interval, processing duration, busy-frame skips, late result rejection and last valid camera-pose age. A supported capability is not evidence that a frame arrived.

Optional “Measured surface alerts” require three stable, fresh, upright, high-confidence observations and an eight-second repeat cooldown. The wording is “Possible surface ahead, approximately … metres.” This is advisory central-view awareness, not comprehensive obstacle avoidance. It cannot certify a clear path, stairs, glass or a safe walking corridor.

On-demand camera descriptions share the depth reader and run local Vision OCR. Results are rejected if stale (>1.5 s), the phone moved >=0.35 m or its forward direction changed substantially before completion. No images or audio streams are uploaded. The existing describeCurrentView tool remains the agent-facing entry point; it was not replaced with a parallel perception service.

## Changed code

- UI: `App/RootView.swift`, `Design.swift`, `PlacesHomeView.swift`, `VoiceControls.swift`, `SettingsView.swift`, `AssistantView.swift`.
- Navigation/camera: `App/HallwayNavigationView.swift`, `SpatialScanning.swift`, `SceneAwarenessService.swift`, `AgentSceneObservation.swift`, `EntranceRecognition.swift`, `RememberRouteView.swift`, `OutdoorNavigation.swift`.
- Agent/audio integration: `App/NavigationAgent.swift`, `VoiceCommandInput.swift`.
- Core policy: `Sources/IndoorbilityCore/NavigationExperience.swift`.
- Tests: `Tests/IndoorbilityCoreTests/NavigationExperienceTests.swift`, `UITests/IndoorbilityUITests.swift` (existing test assertions retained; relocated entry points updated).
- `Indoorbility.xcodeproj/project.pbxproj` includes the two new native source files.

## Verification commands

From the project root:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test
backend/.venv/bin/python -m unittest discover -s backend -v
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Indoorbility.xcodeproj -scheme Indoorbility -sdk iphoneos -configuration Debug -derivedDataPath /tmp/indoorbility-ux-device CODE_SIGNING_ALLOWED=NO build
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project Indoorbility.xcodeproj -scheme Indoorbility -destination 'platform=iOS Simulator,id=3941C08E-9C0F-4410-BE49-E350A4397859' -derivedDataPath /tmp/indoorbility-ux-build CODE_SIGNING_ALLOWED=NO test
```

The unsigned build verifies compilation, not signing or installation. Xcode's Run action with your signing team installs on your iPhone. Backend credentials/configuration were not changed. The former real OpenAI fixture trace remains in REAL_AGENT_VERIFICATION.json; it is synthetic-position evidence, not a recording of this new confirmation UI on a physical device.

## Automated results

- 69 Swift core tests passed (59 existing + 10 new).
- 11 backend tests passed; no credential/model calls were needed for these regression tests.
- 14 distinct UI tests passed across the full legacy suite and focused reruns. The initial full run had one narration-test scrolling failure after Settings reorganization; the scroll target was corrected and that same assertion passed on rerun. New Home, Accessibility and camera-entry checks passed.
- Final unsigned iPhone build passed. Simulator build passed.
- Simulator Home and Accessibility screenshots were visually inspected and saved under docs/screenshots/18-plum-peach-home.png and 19-accessibility-preferences.png.
- No physical depth frames, walking-speed measurements, obstacle accuracy or live AR continuity were captured during this implementation. No new end-to-end physical model run is claimed.

Machine-readable case list: UX_TEST_RESULTS.json. The screenshots show the actual SwiftUI app, not generated mockups.

## Physical iPhone procedure — not yet performed

1. Build/run the updated target on your LiDAR-equipped iPhone. Keep the Mac backend/tunnel running if testing the connected agent. Confirm AI connection in Settings. Enable Show agent timeline to expose Sensor diagnostics.
2. **No map needed for the first check:** Help → Use camera assistance. Grant camera access, face a textured wall/large stationary object and open Sensor diagnostics. Record whether real depth dimensions are nonzero, depth age remains fresh, confidence coverage is meaningful and mesh anchors arrive. Enable calibrated depth points and compare with visible surfaces. An empty/unsupported buffer must be reported honestly.
3. While stationary, ask “What’s ahead?” Compare the reported central surface distance to a tape-measured distance. Check recognized sign text. Repeat with weak lighting, tilted camera and low-confidence surfaces; expect unavailable/qualified readings. Do not use this to test walking into obstacles.
4. Settings → Your maps → Remember a route. Enter the real building, entrance, room and a floor label only if verified from signage. Record one known, same-floor, step-free hallway with a sighted spotter. Observe the live measured mesh, confirm endpoints and review the path before saving.
5. Home → type or hold-to-speak the exact saved room/building → Yes. Camera opens in localization, not confident guidance. Confirm a known entrance only when independently identifiable. At normal comfortable pace, record frame interval, depth age, processing duration/skips, route progress and any camera stalls. Initial relocalization may still require a clear view of the known entrance.
6. Use a saved scan with both Room 106 and Room 105 registered as reviewed reachable landmarks. Navigate to 106, say “Actually, Room 105 instead,” then say Yes or tap Yes. Check actual agent tool events, the confirmation execution event, ARSession-preserved flag, new destination and audible updated instruction. Say No on a second proposal; confirm no route change. Wait >30 s before another Yes; confirm it expires.
7. Switch Camera/Map, open Accessibility, request a sign reading and use the microphone. Verify frame timestamps continue without AR restart. Cover the camera or leave the mapped area: route arrows/directions must pause and landmark recovery remain available. Wrong building/unknown room must never fabricate a route. Confirm a closure using existing reporting; this single-path graph may correctly have no alternative.
8. Repeat with VoiceOver, larger system text, Reduce Motion, tap-to-talk, speech off and haptics off. Try denied microphone permission and typed search. Disconnect the backend and confirm deterministic fallback.
9. Save diagnostic screenshots and record device/iOS, conditions, distance error, localization time, voice latency, frame interval distribution, skipped/late count and peak memory in Xcode Instruments. Before/after walking-speed and accuracy measurements remain **unmeasured** until a physical trial supplies evidence.

Remaining scope limits: no automatic campus-wide room/floor catalogue, no inferred corridors from public maps, no multi-floor/cross-scan live routing, no general semantic visual-object recognition, no guaranteed obstacle avoidance, and no hardware-validated accuracy/performance claim. Unknown map coverage stays unknown. Google discovery remains available as a secondary settings utility; default outdoor search uses the existing native search without asking the user to choose a provider.

API reference used when checking capability handling: https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/scenereconstruction
