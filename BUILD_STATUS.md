# Live guidance upgrade — 2026-11-14

Added local measured-turn milestones, native voice selection/rate, original cue sounds, independent sound/mute controls, a production-follower simulation, richer live depth diagnostics, and Help keyboard/dock fix. Core: 72 passed; backend offline: 11 passed; UI: 15/16 full run, remaining case passed after fix on focused rerun. Physical accuracy and LiDAR performance remain unverified. See docs/LIVE_GUIDANCE_VALIDATION.md.

# Destination-first UX and depth processing — 2026-11-14

Plum & Peach Home/Help/Settings interface, hold-to-talk, expiring destination confirmation, full-screen camera/map continuity, direct camera help, calibrated depth diagnostics/overlay, continuous mapping mesh, and verified-world route chevrons are implemented in the existing app. Added bounded background depth processing, adaptive OCR, capture-age/movement validation, explicit floor metadata and wrong-building rejection. 69 core and 11 backend tests pass. 14 distinct UI cases pass across the suite and focused reruns (one obsolete narration scroll helper corrected). Final unsigned iPhone build passes. No physical LiDAR accuracy, walking-speed or AR continuity claim is made. See docs/NAVIGATION_UX_LIDAR_UPGRADE.md and docs/UX_TEST_RESULTS.json for exact scope, evidence and iPhone steps.

---

# AI agent bridge update — 2026-11-14

FastAPI/OpenAI Agents SDK backend and native validated tool bridge implemented. Cloud opt-in and expiring Keychain token configured in Settings → AI connection. Real OpenAI calls now execute actual Swift routing tools: Room 106 then Room 105 with preserved synthetic pose. Camera tool correctly returns unavailable in the command-line harness. Physical-phone success is not claimed. Backend automatically loads ignored backend/.env; server secrets remain outside iOS. 59 core tests, 11 backend tests, 10 existing UI tests and 2 new UI tests pass (new UI rerun after test scroll-helper fix). Simulator and unsigned iPhone builds pass. See docs/REAL_AGENT_VERIFICATION.json and docs/IPHONE_AGENT_TEST.md for current evidence and backend/README.md for exact setup, scope and real-inference probe.

---

# Destination-first upgrade — November 14, 2026

## Current implementation

- Navigate lists remembered rooms/buildings, with recent-destination ordering and confirmed-visit history. Mapping records are kept in Scan rather than presented as the primary user model.
- Guided first walk records entrance/room confirmations and builds the measured hallway route automatically. The existing scan/world-map pipeline is reused; invalid/interrupted traces remain unusable for routing. A timed SceneKit wireframe displays actual LiDAR mesh surfaces for five seconds.
- Saved-map relocalization plus fresh matching entrance-sign OCR and stable mapped proximity can start guidance automatically. Near-room dwell plus fresh exact room-label OCR can confirm arrival; explicit manual fallback remains. Neither GPS nor historical visits assert indoor position.
- Added native MapKit search/maps/walking previews and foreground Core Location. A manually confirmed accurate entrance fix links outdoor destination preparation to the saved hallway. No-stairs mode withholds unverified outdoor walking routes. Physical handoff remains unvalidated.
- Google Places (New) Text Search is configured locally using the supplied key. One live request succeeded, returning one result with expected response fields. Google content is attributed and kept separate from Apple's map; an independent Apple search uses the original user query. No Maps/Places SDK package or backend was added.
- Assistant uses a labeled deterministic fallback with catalog matching and validated route tools. No cloud model credential or service is configured. Shopping uses a fictional retail map, exact small-stop optimization, unknown-item handling, collected/skipped/removed items, persistent demo-trip state, checkout and closure replanning.
- Conservative OCR interpretation now supports uniquely identified hallways as well as lifts. Old confirmed reports request review after 24 hours and remain blocked until explicitly resolved. Live guidance exposes OCR reporting and a user-operated help-sharing sheet.
- Existing routing modules, demo, closure persistence, voice/face controls, accessibility settings and signing team are retained.

## Validation

- **53 core tests passed**, `/tmp/indoorbility-v7-core.log`. Includes the original 40 tests and new exact-label matching, handoff, arrival evidence, destination serialization, local intent/tool constraints, shopping optimization, unknown-product and review-state tests.
- Simulator integration build succeeded. Physical-iPhone build succeeded in `/tmp/indoorbility-v7-device-final.log`; unsigned compilation does not prove real navigation accuracy.
- Initial UI run: 9 of 10 passed in `/tmp/indoorbility-v7-ui.xcresult`. The new mapping and assistant/shopping tests passed; narration preview's immediate text assertion failed. A predicate-based wait now checks the rendered UI update. The final three targeted tests all passed in `/tmp/indoorbility-v7-final-ui.xcresult` (narration, destination home, assistant/shopping). All 10 UI flows therefore have passing results across the full run and follow-up; the initial full run was not a clean pass. Home and shopping screenshots were visually reviewed and saved in `docs/screenshots/15-destination-home.png` and `16-shopping-demo.png`.
- No real hallway walk, sensor-accuracy validation, camera-label reliability test, GPS-to-AR transition or accessibility participant trial was performed. README lists required physical tests and scope limits.

## Setup and demos

See README for permissions/API configuration and `docs/DEMO.md` for a two-minute campus/retail demo. Local Google credentials are in ignored configuration; their value is not reproduced here. Neither demo data nor simulated movement is represented as a real mapped building.

---

Historical records follow; the current destination-first update supersedes prior home-screen and manual-only arrival descriptions.

# Indoorbility — real hallway integration

## Current update (November 14, 2026)

- A reviewed continuous LiDAR scan trace now generates a two-node, one-edge measured hallway graph. The existing Router, NavigationSession, closure lifecycle and atomic persistence are reused. Reports are isolated per real route and retained when the route is reviewed again.
- Added rigid landmark alignment and a pure navigation follower: position/heading projection, automatic progress, two-second tracking stabilization, bounded progress search, motion-jump detection, off-route dwell, tracking-loss suspension and explicit arrival after near-room dwell.
- ARKit saved-world-map relocalization supplies poses. A watchdog invalidates stale frames. Optional fresh-session recovery needs two manually confirmed landmarks at least two metres apart; it cannot bypass alignment with a single entrance confirmation.
- Navigate now starts with saved spaces, search and a mapping action. The demo has a separate entry. Real hallway Go opens full-screen camera guidance; map toggle and Repeat remain visible, while recovery/reporting/pause are under More. Scan details are collapsed. Existing accessibility settings, narration, VoiceOver behavior and demo controls remain.
- Current core validation: **40 tests passed**, including 14 new hallway tests, `/tmp/indoorbility-hallway-core.log`. Simulator and generic physical-iPhone builds compile (`/tmp/indoorbility-v6-build.log`, `/tmp/indoorbility-v6-device-final.log`). **All 9 UI tests passed** in `/tmp/indoorbility-v6-ui.xcresult`: existing demo routing/closures, OCR, narration, command confirmations and the new saved-spaces → mapping path. These do not exercise physical AR poses. Xcode emitted a post-test simulator diagnostic-collection warning; the tests themselves succeeded.
- Final home-screen rebuild and targeted UI check passed in `/tmp/indoorbility-v6-final-home.xcresult`. The rendered screen was visually checked; screenshot: `docs/screenshots/14-spaces-home.png`.
- No physical hallway trial has been performed. AR accuracy, relocalization success, thresholds, turn directions, missing-frame recovery, audible/haptic feedback and accessibility usability require a real iPhone. See README’s physical acceptance checklist.
- Scope: one manually reviewed same-floor entrance-to-room trace. Mesh data is retained but is not used to certify clearance or detect hazards. No building-wide graph extraction or new external dependencies.

---

The following entries are historical validation records; the current update above supersedes the earlier separate-scan/routing limitation.

# Indoorbility navigation redesign status

Validation date: November 14, 2026.

## Implemented

- Camera-first SwiftUI interface: Camera/Map switch, compact destination panel, standard system typography, blue controls, full-row tap targets, and direct labels. Removed promotional headings and large feature cards. Building metrics remain available.
- Inline navigation camera with shutter, photo import, recognized-text preview and explicit review. Authorized cameras start on supported devices; first use offers Enable camera. Simulator offers a real OCR sample. Camera sessions stop when leaving the surface, opening navigation modals or backgrounding. Directions switches to the map.
- Camera starting-point flow: OCR matches complete known checkpoint labels, then requires confirmation. Search/select a destination and start directions afterward. Ambiguous lift names without a floor do not match.
- Scan tab with live VisionKit text scanning, photo import and Apple Vision OCR. The sample generates an image and sends it through the same Vision recognizer. OCR evidence is shown before explicit report confirmation; ambiguous text does not select a connection automatically.
- ARKit LiDAR capture on supported physical hardware. Saves actual world-transformed mesh geometry, camera trace, named landmarks and an ARWorldMap locally. Atomic directory creation prevents an incomplete scan from appearing as saved.
- Relocalization in saved scans using initialWorldMap. Live position is shown only while ARCamera tracking is normal; tracking loss clears position, and gaps are excluded from recorded travel distance. Background/interruption pauses the session.
- Saved scan list, trace, geometry counts, landmark distance and explicit deletion. These are spatial drafts, not surveyed accessible routing graphs.
- Original deterministic router, strict stair avoidance, confirmed reports, rerouting, report history/persistence, speech and haptics retained.

## Spoken accessibility update

- Added a persistent narration toggle directly on Navigate and preview/repeat/stop controls in Settings. Reuses the existing speech preference without changing saved-state format.
- Narrates inline camera availability/readiness/errors, stable text availability, captured sign text and explicit review cancellation. Live OCR announces availability once per scan instead of speaking every frame.
- Narrates confirmed starting points, route readiness, guidance start/pause, recalculation, no route, lost position and confirmed arrival. Unrelated preference changes do not replay stale route messages.
- VoiceOver receives accessibility announcements instead of overlapping synthesized speech. Backgrounding or enabling VoiceOver stops the app synthesizer; the system manages speech audio interruptions.
- The subsequent voice/face update below implements optional facial controls. No external code, models, assets or prose were imported. This release does not describe arbitrary camera scenes or detect hazards.
- New core tests passed: **22 total, zero failures**, `/tmp/indoorbility-narration-core.log`. Physical-iOS compilation passed: `/tmp/indoorbility-narration-device.log`.
- UI validation: all five existing flows passed in `/tmp/indoorbility-narration-ui.xcresult`; the new narration test passed after fixing its retained-scroll-position assumption in `/tmp/indoorbility-narration-ui-retry.xcresult`. This checks sign review/cancellation narration text, preview, preference persistence and disabling narration, not audible output quality. Screenshot: `docs/screenshots/11-narration-settings.png`.
- Physical listening tests remain required: VoiceOver on/off, speech interruptions, headphones, silent mode, backgrounding, real sign reading and usability with blind/low-vision participants.

## Validation

- Core tests: 20 passed, zero failures (`/tmp/indoorbility-v3-core.log`). Includes routing, persistence, conservative OCR interpretation, scan serialization, invalid coordinates and tracking-gap distance.
- Simulator app build succeeded. The final source also built successfully for generic physical iOS hardware without signing (`/tmp/indoorbility-v4-device-final.log`). Camera, VisionKit, Vision and ARKit source compile against both SDK targets.
- The four existing native UI regression flows passed in `/tmp/indoorbility-v4-ui.xcresult`, including guidance, cancellation, Lift A → Lift B → no route, persistence, real Vision sample-image OCR → explicit confirmation → reroute, the simulator LiDAR-unavailable state, and scanning an entrance sign → confirming start → searching Room 204 → routing.
- Home, inline camera, captured-sign review, route, Building, Scan, OCR and starting-sign screenshots were visually reviewed. Passing-run screenshots are retained in `docs/screenshots/` for home, routing, Building, Scan, recognized text and hardware-unavailable screens.
- The new inline-camera test initially exposed an inherited accessibility identifier hiding child controls. The parent identifier was removed; the targeted test passed in `/tmp/indoorbility-v4-camera-final.xcresult`. It verifies Camera/Map switching, sample-image OCR, cancel without changing position, confirmed starting point and switching to the route map.

## Physical-device checks still required

Simulator OCR and UI tests cannot validate camera quality, LiDAR geometry accuracy or real-space relocalization. Before treating this as a device-tested feature:

1. On a LiDAR-capable iPhone/iPad, test camera permission grant/deny, then scan a textured, well-lit space. Confirm mesh count increases and saving remains disabled until a map is available.
2. Add landmarks, save, relaunch and locate in that same space. Compare the trace and landmark distances to the environment. Changing rooms must not produce a confidently displayed position while relocalizing.
3. Cover/move the camera rapidly and background the app. Confirm the dot disappears with limited tracking and sessions pause. Reopen to retry.
4. Read a real closure sign, check recognized text and the selected connection, cancel once, then confirm. Verify cancellation leaves routes unchanged.
5. Check a non-LiDAR device, denied camera access, low storage, dark mode, VoiceOver, large accessibility text, speech and haptics.

No map alignment exists between physical scans and the fictional demo graph. The app does not automatically turn a mesh into an accessible route, detect obstacles, or provide certified mobility/emergency guidance. No cloud service or remote model is connected.

## Apple APIs

- [VisionKit live scanning](https://developer.apple.com/documentation/visionkit/scanning-data-with-the-camera)
- [Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images)
- [Saving and loading AR world data](https://developer.apple.com/documentation/arkit/saving-and-loading-world-data)
- [AR session lifecycle and tracking quality](https://developer.apple.com/documentation/arkit/managing-session-life-cycle-and-tracking-quality)

## Reproduce

Open `Indoorbility.xcodeproj`, choose Indoorbility and an installed iPhone simulator, then Run. Use a physical device and your signing team for hardware testing. `make project` regenerates the project, `make test` runs core tests, and `make uitest SIMULATOR_ID=<UUID>` runs the native UI flows. UI tests reset demo reports and preferences. They do not erase saved spatial scans.

## Voice and optional facial controls (0.3.0)

- Added a shared command panel on Navigate, in Settings and in captured-sign review. All proposed route/settings/start-point changes require a single-use Yes/No question expiring after 30 seconds. Unknown and combined phrases cannot execute actions. Open Settings and Pause also use explicit confirmation.
- Added native Apple Speech push-to-talk, final-result-only parsing with a minimum word-confidence check, eight-second recording limit, completion timeout, cancellation, permission handling and on-device-support gating. Microphone and speech purpose strings are included in the generated project. No server fallback or audio persistence.
- Added optional ARKit front-camera controls with two-second neutral calibration, adjustable head movement, mandatory three-gesture practice, 0.8-second hold and 0.5-second neutral rearm. Tracking loss, ambiguous gestures and frame gaps disarm recognition. Head tilt means Yes, sideways turn means No, smile means Next. Gestures control only the explicitly opened panel, not arbitrary system apps.
- Face mode pauses sign scanning; permissions/callbacks are scoped to the current input session. Closing and backgrounding discard the current question. No face identity, frames or calibration are persisted.
- Core tests: **26 passed**, `/tmp/indoorbility-controls-core.log`. Simulator compilation passed in `/tmp/indoorbility-controls-build.log`; physical-iOS compilation passed in `/tmp/indoorbility-controls-release-build.log`.
- Hardware acceptance still required: grant/deny microphone, speech and camera permission; unavailable speech locale/model; headphones/audio interruptions; cancel during permission prompts; background while listening; genuine speech finalization; false-positive gesture checks, face lost/recovered, neutral rearm, all three practice gestures, sensitivity adjustment, VoiceOver timing and usability with intended users. No physical speech/face validation is claimed.

- UI verification: all eight flows passed across `/tmp/indoorbility-controls-ui.xcresult` (seven passing flows) and `/tmp/indoorbility-controls-ui-final.xcresult` (both new command flows passing). The first run caught SwiftUI Form grouping the Yes/No row into a shared action; explicit independent button styling fixed it. Retest verifies No leaves preferences unchanged, Yes applies once, the unsupported-face-device state, and confirmed OCR starting points. Screenshot: `docs/screenshots/12-accessible-controls.png`.
- The final physical-iOS build additionally includes guarded audio-interruption handling and spoken face-tracking-loss feedback. These hardware behaviors remain on the device acceptance checklist above.
