# Volunteer preparation → visitor navigation

Use Settings → Volunteer setup · prepare a route. A volunteer prepares one known, permitted, step-free hallway on one signed floor. Normal visitors remain on Home: search/speak a destination, confirm, then use the camera. Do not ask visitors to map unknown buildings.

1. Name the building, signed floor, starting landmark and destination. Use physical signage, not inferred room numbering. Get permission before mapping restricted areas.
2. Begin at the recognizable start. Wait for stable camera tracking, confirm it, and walk the known path at consistent phone height. Brief mesh preview shows measured surfaces; it does not certify clearance. Tracking gaps and invalid geometry remain rejected by the existing route validator.
3. At the actual room, save a draft. A new/edited route is excluded from visitor search until its field review is accepted. ARWorldMap, measured mesh and route remain local. Drafts can be reopened from Manage scans and landmarks → saved scan → Review volunteer route (or Hallway directions → Volunteer review and release).
4. Review the route trace and signs. Independently measure full route length and checkpoint/endpoint positioning error with a tape, laser or authorized dimensioned plan. Record reviewer initials and floor. Confirm actual permitted step-free access, not just the absence of detected obstacles.
5. Return to the start and open Test camera guidance, which starts the existing live ARKit navigation. Test relocalization, turns, tracking recovery and correct-door arrival. Ideally a second person checks position. The pass checkbox is a volunteer attestation, not automatic device evidence. Failed trials must not be approved.
6. Make available on this iPhone only after all checks pass. Review screening rejects nonfinite/negative measurements, length discrepancies exceeding max(0.5 m, 5% of independently measured length), and observed errors above 0.5 m. These are initial screening limits, not universal safe-clearance tolerances or a certification. Narrow areas may need stricter limits and professional review.
7. Withdraw a route for rechecking if the environment changes. Editing its stored route invalidates the previous review through exact route comparison. Closures continue to use existing reporting/routing logic.

Existing saved routes remain usable and are not retroactively certified. New or edited routes from either mapper entry point require review. Raw draft maps remain available to the mapper for testing. Visitors must never treat a surface mesh as proof of walkability.

There is no automatic sharing: maps currently work on the iPhone that captured them. Preparing on one volunteer's phone does NOT deliver maps to other visitors' phones. A separately designed local export/import or authorized preloaded-package workflow is still required. No community/cloud backend was added.

Unverified: physical walking accuracy, actual volunteer workflow on LiDAR hardware, false/missed surface alerts and first-visitor localization in Friend Center. A real marked hallway and independent ground-truth checks are required; neither tests nor checkboxes prove them.

## Destination-led recording (Friend Center pilot)

Type or speak “Friend 006” on Home. The reviewed source catalog identifies Room 006, Friend Center and LL. With no available reviewed recording, the app opens a confirmation card with in-app building directions and an optional Record route action. Saying yes on that card opens setup with building/room/floor prefilled. Confirm the actual sign and identify the real starting landmark before capture. This is deterministic catalog resolution; no model invocation is required and no floor is guessed.

Each new recording has a separate scan/map/route. A second recording does not overwrite the first. Reviewed, unblocked recordings are grouped only when building, signed floor and room labels agree. Unknown-floor recordings remain separate. The recommendation orders valid field review first, confirmed visit count next, then lower independently reported error and newer review. This is an evidence preference, not proof of greatest physical reliability. Different starting landmarks remain explicit; select Other recordings to choose a suitable start. All routes must localize before instructions can run. Reported closures are checked during catalog refresh and again before starting a selected route.

Arrival through the existing verified arrival flow increments the stored successful-visit count. Old catalogs decode without that count. Unknown buildings/rooms still need manual identity verification. This release handles one floor per recording, not automatic floor transitions or a recording spanning elevators/stairs. Recording prepares a path the mapper knows; it cannot navigate an unmapped trip while learning it.

## Full-screen capture guidance

Route setup now opens a full-screen camera with three numbered stages: show/confirm the starting area, walk the known hallway, then confirm the room and save for review. The room landmark is recorded when the mapper taps the arrival button, before the review prompt. The starting action waits for normal tracking and at least one mesh anchor. Save still uses the existing ARWorldMap and continuous-route validation gates.

Generic area capture is also full-screen; optional landmark naming and scan naming open short prompts instead of permanent form fields over the camera. Measured ARMeshAnchor vertex/index buffers render continuously during new capture, using plum wireframes and a translucent peach surface fill. Mesh updates retain the existing per-anchor 4 Hz render throttle. This does not classify all furniture or prove coverage/clearance. Navigation keeps its separate transient preview behavior; no permanent mesh load is added to live guidance.

The iPhone SDK build and 82 core regression tests passed after this UI update. Actual mesh appearance, thermal/rendering performance and capture quality require a LiDAR-capable physical iPhone; the simulator cannot verify them.
