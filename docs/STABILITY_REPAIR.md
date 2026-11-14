# Voice, scan saving, and navigation recovery — November 14, 2026

## Findings and changes

- Home rendered two conditional microphone controls. Starting recognition changed the layout, removed the active control, and ran its cancellation handler. One persistent microphone now stays mounted during layout changes and keyboard use.
- Voice input allowed eight seconds and finalized after 1.5 seconds without a changed transcript. It now permits 20 seconds and a 2.5-second pause. A completed/terminated recognition session with nonempty text submits once instead of discarding it when finalization times out. Cancellation still invalidates late callbacks; partial results never execute while recording continues.
- Cloud clarification-only responses were assigned to a response property without invoking the host speaker. All hosts now speak the local clarification text.
- Home handles Stop/Repeat locally, waits for the recognized query to commit before resolving it, and asks for confirmation when the reported “Friend Circle” transcription may mean Friend Center. It does not silently assign a building.
- Search navigation rejects outdated suggestion selections after leaving. Back clears the transcript and pending correction. A visible Close search control provides an alternative to swiping. Swipe recognition accepts SwiftUI child hosting controllers on the same screen, excluding separate sheets and interactive scan previews.
- Capture export encoded mesh JSON, archived ARWorldMap, and wrote files on the main actor. These operations now run in a background task through the same atomic staging/move implementation. Saved geometry, maps, and labels are unchanged. Existing synchronous building-assembly persistence is unchanged.
- Phone-position coaching fell back to the safety-warning callback and imposed a six-second directional-speech delay. Indoor navigation now treats posture separately from hazards. Actual hazard and tracking-confidence checks remain.
- The navigation screen no longer repeats a large paused badge; destination/building labels are separated, debug vectors are only shown on the map, and the recovery instructions are shorter. Pose/OCR callbacks survive view reappearance instead of being permanently cleared on disappearance.
- A matched saved world map can recover at any user-confirmed nearby saved landmark. This requires stable tracking, matching horizontal and vertical position, an unambiguous route projection, and the existing relocalization evidence. It does not reinterpret a room name as a position. Drift recovery without a trusted saved-map match still requires two landmarks.

## Waypoint comparison

Inspected the public [Waypoint route follower](https://github.com/sachin-khanal/uva-gwc-ghh-2026/blob/main/Package/WaypointCore/Sources/WaypointCore/Routing/RouteFollower.swift). It uses bounded along-route projection and heading-based lookahead steering. No code was copied: Indoorbility retains route-geometry maneuvers to avoid reintroducing phone-rotation-driven instructions. A surface mesh alone does not supply room identity, traversability, or a live-to-map transform; the existing recorded path, landmarks, and ARWorldMap remain required.

## Validation and limits

- 147 Swift tests passed, including new matched-map recovery rejection/acceptance and casual walking request tests.
- 24 backend tests passed; backend code and deployment are unchanged.
- Signed iPhone Release build passed.
- Initial focused simulator run: all four tests passed (keyboard dismissal, editing layout, swipe-back, building GPS handoff).
- Final swipe-back and building GPS handoff passed again. The new close/reopen test initially failed because its selector expected a compound result card to have only the title as its accessibility label. The selector now locates the card by its contained title; targeted rerun passed. All five distinct focused UI cases passed across these runs.

Logs: `/tmp/indoorbility-stability-core.log`, `/tmp/indoorbility-stability-backend.log`, `/tmp/indoorbility-stability-final-build.log`, `/tmp/indoorbility-stability-ui.log`, `/tmp/indoorbility-stability-final-ui.log`, `/tmp/indoorbility-stability-close-ui.log`.

The physical iPhone was reported unavailable by devicectl. No device crash report or live microphone/ARKit recording was obtained, so these findings are not a diagnosis of an OS crash or a claim that crashes cannot recur. No measured physical accuracy improvement is claimed. The changes have not been installed on the iPhone or pushed.

## Device verification

1. Install this build, then speak a normal request from idle Home, pause briefly, and finish. Check for one response; cancel mid-speech and confirm no late command executes.
2. Search, swipe back, search again, and close search. Repeat with slow connectivity; old results must not open another screen.
3. Record and save a real route. Check UI responsiveness during saving, reopen its 3D preview, and verify the saved route still exists after restarting the app.
4. Start the saved route near an identifiable landmark. Once the saved map matches, confirm that landmark. A wrong floor or distant landmark must be rejected. Walk the independently measured route and record turn timing/position residuals.
5. Lower the phone while tracking remains normal: posture tips must not suppress valid map guidance. Cover the camera while stationary: tracking loss must still pause guidance.
6. If the app exits or freezes, collect the matching device crash/hang report before claiming the issue resolved.
