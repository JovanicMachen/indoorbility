# Independent iPhone verification — November 14, 2026

## Verified service and phone setup

- Existing Railway service `indoorbility` remains in the same project; no new service or deployment was created during this verification.
- Active GitHub deployment: `0c610e60-14d6-4151-8196-a80405765986`, status SUCCESS, commit `7546edba2bce098eb7c317c35a1baa699c1d6f66`.
- Automatic source: `JovanicMachen/indoorbility`, branch `main`, root `/backend`, Dockerfile builder, path `Dockerfile`.
- Historical failure: commit `54e4e7d` contained only README.md. Railpack at the repository root reported that it could not determine how to build the app. This was repaired in the previous configuration task. Reconnecting the source unexpectedly triggered the successful deployment above; that side effect was disclosed at the time.
- Runtime SHA-256 hashes of app.py, device_auth.py, map_sharing.py and requirements.lock.txt match the local backend. Local backend is unchanged from GitHub.
- Existing HTTPS domain: https://indoorbility-production.up.railway.app. This is also `AgentConfiguration.productionBaseURL`. Existing custom overrides remain supported; Settings displays the effective URL. Old development tunnel settings migrate once.
- Existing volume `8e3fa391-27af-462f-ba2d-c4daf133706a` remains mounted at `/data`. Runtime paths: maps `/data/maps`, authentication `/data/device-auth.sqlite`; database exists. No service restart or volume replacement was performed. Backups remain unverified.
- User confirmed the physical iPhone paired and reported Connected and authenticated. User also reported local navigation, Repeat, and Stop worked with Airplane Mode on and Wi-Fi off; this is user-reported physical evidence, not an instrumented walk. A fresh signed development build was installed without deleting app data.
- Temporary SSH key was explicitly authorized, then revoked after verification. Local private key and used phone pairing instructions were removed. No production credential was printed or committed.

## Tests and limits

- Swift core: 126 tests passed.
- Backend: 24 tests passed.
- Signed physical-iPhone build: succeeded; installation succeeded.
- Live HTTPS readiness 200; unauthenticated agent access 401.
- One-use pairing and credential renewal passed. A synthetic map uploaded/downloaded with matching SHA-256 and retained ownership after renewal. The test map was deleted and the test device revoked. The physical phone's pairing was retained.
- Real OpenAI calls executed the existing Swift tool bridge: Room 106 → Room 105 with synthetic position preserved; camera description correctly reported unavailable evidence. This is a computer-driven protocol test, not a physical ARKit or cellular test.
- Simulator UI suite: 21 tests passed, zero failures, in 603.921 seconds; xcodebuild exited 0 with TEST SUCCEEDED. Result bundle: `/tmp/indoorbility-independent-ui.xcresult`. After completion, Xcode reported a diagnostic-collection warning because a subprocess could not find simctl under the default command-line-tools selection. This did not fail the tests. Cloud assistant is disabled for deterministic local navigation tests. This demonstrates local workflows without a cloud dependency, not actual radio loss during a physical walk.

## Changes in this verification

Restored standalone Camera help under Settings after removal of the Help tab had made it unreachable. Updated UI tests to use current controls, optional floor fields, and current spoken instructions. Removed dependence on the deleted chat tab and home Map button in favor of the current search and shopping demo workflows. Added a regression check for dismissing the search keyboard by tapping empty space. No LiDAR, routing, tracking, or arrival algorithms changed.

The subsequent UI update shortens AI connection and search messages and opens GPS directly for the published Friend Center building location. Returning from a room card within GPS resumes the existing screen. The signed iPhone build and installation succeeded; the focused AI settings test and two building-directions/recording tests passed. The full 21-test result above predates these follow-up changes. The backend remains unchanged; a GitHub push may trigger its configured automatic deployment.

## Physical test still required

After computer-based tests finish:

1. On the iPhone, check AI connection again. Enable Show agent timeline for this test. Download/retain a real saved route before disconnecting anything.
2. Turn Wi-Fi off in iPhone Settings, confirm cellular data is enabled for Indoorbility, disconnect the cable, and fully power off the Mac.
3. At a known starting landmark, relocalize against a saved map. Say a destination that actually exists in that map. Verify the agent timeline reports requested/executed tools and the destination changes. A connection-check button alone does not prove a real OpenAI turn.
4. Change to another genuinely mapped destination by voice. Record whether tracking continues and the ARSession reset count stays unchanged. Do not use the synthetic Room 105/106 test labels unless they exist in your own map.
5. Enable Airplane Mode and ensure Wi-Fi is also off. On the already downloaded route, verify local turn prompts, speech, haptics, Stop and Repeat continue while position remains reliable. Cloud requests should show unavailability; new online place searches and map downloads are not expected to work offline.
6. Briefly cover the camera while stationary. Indoor guidance must still pause for lost position; loss of internet must not bypass positioning checks. Recover at a known landmark, then verify correct-room arrival confirmation.
7. Restore cellular, repeat an agent command, and record the result. If practical, repeat after 15 minutes to test credential renewal. Send only outcomes/errors, never pairing codes or tokens.

User-reported offline navigation passed. Cellular-with-Mac-off, measured physical route accuracy, live obstacle detection, and instrumented mid-walk internet-loss behavior remain unverified.

## Distribution to other iPhones

The installed build is development-signed for one provisioned device, bundle ID `com.indoorbility.app`, version 0.3.0 (1). Its current provisioning profile expires November 21, 2026 at 02:41 EST. This is not a TestFlight build or a permanent distribution method.

Remaining: verify paid Apple Developer enrollment and App Store Connect access; finish app icon/privacy-manifest and permissions/privacy disclosures; archive a Release build with distribution signing and an unused build number; validate it; obtain user approval before upload or distribution. Configure beta information and reviewer access, then invite testers through TestFlight. The first external beta requires Apple's review. Each phone must pair separately and receive its own downloaded maps. The current ten-minute pairing code is unsuitable as a static review credential; arrange reviewer access without embedding server secrets.

References: [TestFlight](https://developer.apple.com/testflight/), [provide beta test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information).

## Routes and walking regression update — November 14

- Added a Routes bottom tab, one-tap recording entry, saved building selection, named From/To endpoints, saved-route directions, and collapsed map tools. Recording labels are trimmed and blank or identical endpoints cannot start recording. Each route retains its scan ID, world map, physical landmark IDs and measured path. Building-name equality never creates a geometric connection.
- Compared Waypoint's [route follower](https://github.com/sachin-khanal/uva-gwc-ghh-2026/blob/main/Package/WaypointCore/Sources/WaypointCore/Routing/RouteFollower.swift) and [feedback planner](https://github.com/sachin-khanal/uva-gwc-ghh-2026/blob/main/Package/WaypointCore/Sources/WaypointCore/Guidance/FeedbackPlanner.swift) with the existing local follower and guidance delivery. Both use bounded progress projection, lookahead, stabilized headings and prioritized feedback. No Waypoint implementation or README was copied. This is a targeted comparison, not a complete feature-parity or physical-accuracy certification.
- New synthetic tests reproduced missing rounded-corner cues and a level-change warning being replaced with ordinary forward guidance. Fixed both in the existing local presentation layer, preserving tracking, arrival confirmation and the OpenAI tool bridge.
- Walking scenarios: 0.8 / 1.4 / 1.8 metres per second, forward/reverse, sideways motion, heading wobble, a nearby parallel return corridor, rounded turns and unknown-floor elevation changes. All measurements are synthetic. No actual building geometry or physical accuracy was generated.
- Swift baseline: 126 passing tests; after changes: 131 passing. Backend: 24 passing. The existing 5,000-vertex/1,000-update desktop benchmark was 7.429 ms before and 7.657 ms after; this small single-run variation is not evidence of an improvement or regression in iPhone frame rate. Physical sensor latency and accuracy remain unmeasured.

Physical acceptance: name and record a real starting landmark and destination in Friend Center; save and publish; start a new session and follow the recorded walk with a companion. Check turn cues against actual corners, then test a destination change, stationary camera occlusion/recovery, and correct-room arrival confirmation. Repeat with the Mac off over cellular and then with the downloaded route offline. Record failures, landmark residuals and diagnostic snapshots; do not record a pass before performing the walk. Reverse direction also needs a physical walk: passing the synthetic reverse-path test does not certify reverse access through doors or stairs.

### Confirmed walking-test destinations

The user selected **Main entrance → Room 006** and **Main entrance → Room 008**, downstairs in Friend Center. These are two separate recordings; the room numbers do not establish a floor label or route geometry.

1. Open **Routes → Record route**. Select Friend Center, enter **Main entrance** as From and **Room 006** as To. Start at a recognizable entrance landmark, record the actual walk downstairs, and save at the room sign. Repeat separately for Room 008.
2. Return to that same entrance landmark. Start the saved route in a fresh session and establish positioning. Walk normally with a companion; check each corner and level-change cue against the real path.
3. At the destination, confirm the actual room sign. Record any early, missed or incorrect announcement and export start/end diagnostics. Do not mark an uncertain floor or room as verified.
4. Test camera occlusion while stationary, recovery at a known landmark, and the downloaded route offline. Only test a voice destination switch where the saved maps have an established shared coordinate frame; matching building names alone do not align recordings.

Focused UI verification: the Routes recording, prefilled room recording, and production guidance/mute tests passed (3 tests). After the final From/To layout adjustment, both recording tests passed again (2 tests, 51.640 seconds). These results do not substitute for the physical walks above.

Updated generic iPhone Release build: succeeded with existing signing configuration. Existing audio/ARKit deprecation warnings remain. Installation of this update was not performed: Xcode could not discover the previously connected physical iPhone. Reconnect and unlock the phone before installing and walking these routes. These changes are local and have not been pushed or deployed.

### Outdoor distance and approach feedback

- Outdoor guidance now shows estimated feet remaining along all remaining route legs, rounded to five feet. Next-turn distances also use feet. This is route distance, not a measured doorway distance.
- The top arrow has a subtle red glow for getting closer and blue for moving farther along the route. Text accompanies color. Two successive fixes must show displacement larger than the combined GPS accuracy estimates; stale, inaccurate or uncertain positioning removes the trend. The indicator never confirms arrival.
- Added a separate phone-facing compass label with heading-quality/freshness checks and portrait/landscape handling. It does not equate phone orientation with walking direction or gaze. Existing movement-course guidance remains separate.
- Requested Core Location's navigation accuracy mode; this is not a guarantee of improved physical accuracy or delivery frequency. No GPS precision, sensor latency or close-proximity performance measurement was fabricated.
- Travel feedback uses the supplied MP3 at low volume, at least two seconds apart while reliable navigation updates continue. Speech, warnings and mute take precedence. Failed map requests retry with increasing intervals up to 60 seconds and preserve a loaded route.
- Core tests: 136 passed, including noise rejection, repeated approach evidence, stale-position recovery and total remaining route distance. Physical tests must check feet estimates at known outdoor landmarks, compass orientation, absence of false red/blue flicker while stationary, and loss/recovery of GPS. Map-request retries and audible timing still require a device/network test.
