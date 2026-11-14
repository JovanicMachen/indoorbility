# Friend Center LL — source review and physical test

2026-11-14. This replaces Frist as the Stage 2 pilot. No successful physical navigation trial is claimed.

## Installed now

The app has a separate Friend Center identity catalog, exact signed floor labels, Rooms 006/008 and source links. Home search shows these as room information, explicitly unavailable for indoor routing. No fake nodes, coordinates, distances or ARWorldMap were created. Existing locally reviewed routes still take precedence when available. A number alone is an ambiguous building identity, not permission to navigate.

Settings → Your maps → Friend Center exposes the catalog. Enable Settings → AI connection → Show agent timeline to reveal its field-test controls. The room-sign check uses the existing VisionKit live camera text scanner; it does not establish position. Capture uses the existing ARKit/LiDAR pipeline, not the VisionKit camera simultaneously. Existing live navigation uses OCR from its active ARFrame and keeps its ARSession during agent interactions.

## Evidence and gaps

- Building identity/access guide: https://www.accessableusa.com/princeton-university/access-guides/friend-center
- Room 006: https://www.accessableusa.com/princeton-university/access-guides/friend-center-006
- Room 008: https://www.accessableusa.com/princeton-university/access-guides/friend-center-008
- University classroom directory: https://classroominfo.princeton.edu/
- Official campus maps: https://facilities.princeton.edu/maps

The room guides verify LL and distinguish primary/alternate doors. They provide no metric hallway centerline or surveyed camera anchor. Do not convert “left/right of elevator” into an assumed route length or orientation. Review current door signs, public access and closures onsite. Classroom directory searches did not yield an authorized metric LL plan in this investigation. Publicly viewable campus mapping is not evidence of indoor geometry or redistribution rights.

AccessAble's website conditions reserve content rights and do not supply an implied license: https://www.accessableusa.com/pages/website-conditions. No photos, floor-plan images or GIS datasets are bundled. Small factual summaries are attributed; redistribution permission for source imagery/datasets remains unresolved. Do not scrape the guide or bypass authenticated campus resources. No cloud upload was added.

## Required mapper evidence before a route can run

1. Obtain an authorized LL floor plan or permission to use a posted plan. Photograph the entire sign legibly, including legend, orientation, scale and title; do not assume an image's proportions are metrically correct.
2. Identify the LL elevator exit and the specific doors for 006 and 008. Record which are main/alternate entrances; do not conflate their positions.
3. Establish metric scale with approved plan dimensions or independently measured reference distances. Record bends, door approaches, barriers, clearance and access restrictions. A phone travel trace alone does not verify accessible clearance.
4. Use the existing developer capture workflow to mark physical landmarks with stable AR tracking and consistent phone height, save the ARWorldMap and measured capture, and review each route. Keep a record of the source and measurement method. This is mapper preparation, not a visitor requirement.
5. Register the plan to the same measured coordinate frame. Existing two-landmark recovery requires two distinct marks at least 2 m apart and validates rigid alignment; it does not independently certify surveyed accuracy. A preloaded plan needs a prepared relocalization map or surveyed visual anchor before first-visitor camera guidance is available.

The new catalog does NOT yet bind those reviewed scans to a preloaded metric Friend Center package. That adapter, the actual measured geometry and a distributable localization asset remain implementation/input gaps. Do not treat selecting a floor or recognizing “006” as completing them.

## Physical iPhone procedure

1. Open Indoorbility.xcodeproj, select your unlocked physical LiDAR-capable iPhone and Run. Grant camera and speech permissions as requested. Keep the development backend and tunnel running for real AI commands; the Google key is not model authorization.
2. Search “Friend Center 006”. Verify LL and the explicit unavailable-route message. Search 008 and an unknown room. Unknown rooms must never acquire fabricated indoor directions.
3. Enable the testing option above. Stand by an actual room sign, open Check room sign with camera, and verify exact text 006/008. Capture failures and ambiguous text; recognition alone must not announce arrival.
4. Before walking guidance, complete the mapper evidence and reviewed measured-route setup. If no verified route exists, STOP this part of the test and record “blocked: geometry/localization asset missing”. Do not walk using catalog prose as turn-by-turn instructions.
5. On a reviewed route, start camera guidance at the known landmark. Wait for verified localization. Open sensor diagnostics and record tracking state, source depth availability, processed frame count, depth confidence histogram, age, processing latency and route status. Unsupported hardware must report unavailable depth.
6. Walk at normal speed with a sighted observer on a clear corridor. At independently measured points, record actual versus estimated distance and heading. Repeat in both directions. Predefine acceptable error relative to hallway clearance; do not derive ground truth from the same AR trace.
7. Only when both destinations exist in the same registered, reviewed route geometry: say “Actually, Room 008 instead.” Record real model/tool events, destination/state change, canceled old narration and continuity of the ARSession. If the existing single-route model cannot reach the second branch, record that limitation instead of a simulated success.
8. Test tracking loss while stationary, resume at a known landmark and verify instructions/AR arrows remain paused until recovery. Test the wrong door: no arrival. At the correct mapped door, verify proximity plus independent label confirmation gates arrival.
9. With the observer, test a stationary broad surface from a safe distance. Record possible-surface alerts, missed/false alerts and latency. Do not test by walking into obstacles. Glass, low objects and drop-offs are not certified detectable.
10. Repeat with VoiceOver, large text, mute/haptics and backend unavailable. Preserve text guidance and deterministic fallback; record failure, not AI success, when no real call occurs.

## Record for each trial

Device/iOS, timestamp, map revision and measurement source; starting anchor; destination; permission/access status; lighting; tracking interruptions; depth count/age/confidence; independently measured position and heading errors; instruction timing; route deviation; correct/wrong-door arrival outcome; agent tool events and AR-session continuity; false/missed surface alerts. Keep results locally and omit credentials or bystander imagery. Mark every case pass/fail/blocked/not tested.

Physical walking accuracy, plan alignment, reliable relocalization, real-agent rerouting to these rooms and obstacle awareness remain unverified.

## Build verification for this update

The full Swift core suite passed (75 tests), including three new catalog/search/OCR-token tests. The unsigned iPhone SDK build succeeded. These are automated software checks, not physical device accuracy evidence. Logs: /tmp/indoorbility-friend-tests.log and /tmp/indoorbility-friend-build.log.

The public ArcGIS REST item metadata request succeeded for item 366d5b2cddfb4aa990eb75f04aec8ade: title Interactive Campus Map, type Web Experience, access public, licenseInfo/accessInformation absent. This verifies a public application metadata endpoint, not permission to redistribute underlying layers and not an indoor floor-plan API. No underlying datasets were imported.
