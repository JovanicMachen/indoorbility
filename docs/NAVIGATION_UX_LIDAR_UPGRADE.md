# Destination-first navigation and LiDAR update

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
