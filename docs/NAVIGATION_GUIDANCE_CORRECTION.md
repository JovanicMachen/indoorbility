# Navigation guidance correction — November 14, 2026

Implemented locally. Physical walking validation is pending; these results do not establish positioning accuracy or safe clearance.

## Root causes reproduced

1. `HallwayFollower` chased a point three metres ahead using the **camera's heading**. `LiveGuidance` let those “Bear left/right” messages override the route's geometry-derived maneuver. A stationary-phone rotation test on a straight route produced five distinct instruction IDs: straight, left, right, reverse, and check heading.
2. Outdoor guidance could repeat the leg's starting maneuver when GPS course alignment changed. Course is movement evidence, not phone orientation, and neither should rewrite the planned maneuver.
3. An active spoken direction finished before a newly queued direction played. Safety interruptions could also leave an obsolete direction available for replay.
4. Indoor availability checks rebuilt `route.building`, including full path length and level-change scans, repeatedly on the main actor. This was outside the existing follower-only benchmark.

No reversed left/right sign or rigid-transform sign error was reproduced. Saved X/Z turns and live-to-saved yaw use consistent conventions. Existing tests cover the rigid transform and reversed routes. This does not verify a particular physical map's alignment.

## Changes

- Indoor maneuver selection uses cached metre-scale route bends and reliable along-route progress. Camera orientation is diagnostic only. Repeated rotations cannot create steering instructions.
- Retained local projection bounds, jump rejection, tracking stability, map alignment, closure/accessibility checks, arrival dwell, and room confirmation. Sustained measured retreat pauses guidance and requires landmark recovery. No extrapolated positions were added.
- A vertical camera with normal tracking no longer invalidates an otherwise valid map position solely because horizontal heading is unavailable. Camera arrows still require usable heading, posture, alignment, and tracking. Camera sensing warnings remain separate.
- Geometry U-turns are expressed as “Turn around,” instead of selecting an arbitrary side. Nearby parallel-route and small trace-wobble regressions remain in the suite.
- Repeat and agent context use the same planned instruction as the screen.
- New directions replace stale directions in synthesis; safety messages retain priority and discard pre-warning queued directions. Outdoor confirmed leg transitions bypass the routine three-second speech cooldown.
- Route geometry is cached in the follower and rebuilt when the route changes. Current closure and stair-preference checks still run; availability is evaluated once per pose callback instead of repeatedly.
- Map opens first. Outdoor map is north-up with pan/zoom. Indoor map has fixed saved-map orientation and bounds, live position, and next maneuver. An ARWorldMap does not provide a verified geographic north reference, so the app does not label indoor orientation “north.”
- Developer overlay shows the selected segment, next maneuver, camera orientation, and measured movement direction over the recorded route. Unaligned live positions are hidden.
- Avoided publishing unchanged AR tracking/mapping diagnostic strings. This removes redundant notifications, not sensor observations.

Route files contain recorded geometry, not independently surveyed junction identities or door-side metadata. Turns are derived from that accepted geometry; the app does not invent a destination's left/right side. Badly recorded geometry still needs a corrected map.

## Measured software results

All performance numbers below are local synthetic macOS test measurements, not iPhone GPS/AR measurements. Debug test execution; no absolute performance threshold is asserted.

| Measurement | Before | After |
|---|---:|---:|
| Distinct guidance IDs while stationary and rotating phone on a straight route | 5 | 1 |
| 1,000 availability checks, synthetic 5,000-point route | 2,579.866 ms rebuilding geometry | 8.822 ms reusing immutable graph |
| 1,000 follower + guidance updates, synthetic 5,000-point route | 7.645 ms | 7.618 ms |

The availability comparison runs the original and cached operations side by side. Initial cache construction is outside the timed reused-graph loop. The follower-only difference is too small to claim an improvement. The graph result is not a claim that the entire application is hundreds of times faster.

Logs: `/tmp/indoorbility-guidance-before.log`, `/tmp/indoorbility-guidance-after.log`.

## Pipeline comparison and instrumentation

- **Outdoor:** Core Location supplies asynchronous fixes; desired accuracy remains BestForNavigation, no distance filter, no automatic pause. Three qualifying fixes and existing accuracy gates remain. MapKit calculates route geometry asynchronously. GPS course is speed/accuracy gated; CLHeading is separate phone orientation. Map position now uses the same accepted fix as navigation rather than a separate `UserAnnotation` update stream.
- **Indoor:** ARKit camera timestamps drive poses; navigation processes at most 20 Hz. Existing two-second stable-tracking and freshness/jump checks remain. LiDAR depth is sampled at most 10 Hz with single-flight background processing and stale-result rejection; OCR/object processing is also bounded. These confidence and workload limits were not reduced to create an apparent speed gain.
- **Developer timing:** bounded windows of 300 samples, mean/p95/count, on-device only. GPS interval, reported horizontal uncertainty, capture-to-callback, capture-to-SwiftUI-update, outdoor processing, indoor processing, capture-to-next-display opportunity, main display callback interval, speech request-to-synthesis start, and capture-to-synthesis start. Body evaluation counters identify UI churn.
- Existing sensor snapshots include delivered AR frame rate, capture-to-delegate delay, delegate processing, depth processing/freshness, mesh-copy timing, tracking interruptions and session resets.

Important measurement limits:

- Core Location's horizontal accuracy is **reported uncertainty**, not measured landmark error.
- A display-link callback is a **display scheduling opportunity**, not proof that a new map pixel was rendered. Actual visible-map latency still requires synchronized screen/sensor observation or Instruments.
- Synthesis-start callbacks are not acoustic onset, and exclude VoiceOver announcement timing.
- Main display callback gaps can flag a stall but do not identify its CPU cause; use Instruments Time Profiler/Hangs for attribution.
- No physical GPS intervals, landmark error, acoustic latency, camera frame rate, LiDAR latency, or main-thread stall distribution have been collected in this task. Before/after physical results remain unavailable.

## Regression validation

- Core: 144 tests passed. Covers stationary rotations, left/right L routes across headings, geometry U-turns, backward movement, parallel corridors, trace wobble, loss/recovery, arrival confirmation, destination replacement, rigid alignment, outdoor course changes, and speech priority/replacement.
- Backend: 24 tests passed; backend and agent protocol unchanged.
- Focused simulator UI: 2 passed, 0 failures (58.336 seconds): production guidance/mute and known-room building-directions launch.
- iPhone Release build: BUILD SUCCEEDED with the existing development signing configuration. Simulator Debug build also succeeded. No upload, deployment, device installation, or Git push.

Build/test logs: `/tmp/indoorbility-guidance-iphone.log`, `/tmp/indoorbility-guidance-ui.log`, `/tmp/indoorbility-guidance-backend.log`.

## Physical test to complete later

1. At Friend Center, use the actual saved main-entrance → Room 006 route. Measure the path and turn locations independently; do not derive reference distances from the same AR trace. Test Room 008 separately if its route is mapped.
2. Enable developer mode in AI connection (Show agent timeline). Confirm the starting landmark and export a sensor snapshot. Record the app build and route used. Keep diagnostics private: route snapshots can include user-confirmed landmark information.
3. Stand still and rotate/tilt the phone repeatedly. The maneuver sequence must remain unchanged. Walk at normal speed, stopping at measured turn locations to record announced turn timing and landmark residuals. Export at the destination.
4. Briefly cover the camera while stationary. Directional guidance must pause; uncovering alone must not bypass map recovery. Confirm a known landmark, then resume.
5. Test a short backward walk and nearby parallel corridors with assistance. Check for a recovery prompt rather than contradictory steering or a jump to a later segment.
6. Change destinations by voice and compare session-reset counts. Verify room confirmation still gates arrival. Test Repeat/Stop and a downloaded route offline.
7. Outdoors, export timing separately with cellular GPS and repeat the same measured route under comparable conditions. Record actual turn locations and screen/audio onset; GPS alone cannot resolve closely spaced indoor corridors.

Do not mark physical validation passed until these observations and residuals are recorded. The user elected to perform the physical walk later.


## Follow-up audit and full regression run

The follow-up found and corrected three further issues:

- Local `deliverGuidance` used `agent.busy` as a speech gate. A network request could therefore suppress an otherwise reliable turn. Only active microphone listening gates local guidance now. Directions also preempt routine speech (including a cloud response), while safety speech retains priority.
- Full-route nearest-point recovery could select the wrong branch at a crossing. Recovery now rejects similarly fitting, separated segments and asks for a different landmark. An added crossing-route regression checks normal segment progression, rejection of ambiguous recovery, and route/destination preservation.
- The 20 Hz presentation throttle could silently discard a backwards timestamp. Only monotonic timestamps are throttled now; invalid timing reaches the existing confidence checks.

Pose callbacks now precede scheduling depth, object recognition, floor processing, and OCR. Those workers retain their single-flight/background limits and freshness checks. ARKit's delegate remains on the main actor; this change is not a claim of complete isolation from all main-thread stalls. Physical Instruments profiling is still required to attribute any remaining stall.

Latest controlled software measurements (synthetic 5,000-point route): rebuilding the graph for 1,000 availability checks took **2,754.990 ms**, versus **8.820 ms** reusing it. Follower/guidance processing took **7.722 ms / 1,000 updates**; compared with the original 7.645 ms result, there is no meaningful follower speed improvement. These measurements include neither hardware sensor acquisition nor UI rendering nor acoustic output.

### Exact navigation-related files changed across this correction

| Files | Purpose |
|---|---|
| `Sources/IndoorbilityCore/HallwayNavigation.swift` | Camera-independent progression, graph cache, movement diagnostics, retreat detection, ambiguous recovery rejection |
| `Sources/IndoorbilityCore/LiveGuidance.swift` | Geometry maneuvers, U-turn wording, removal of reactive steering overrides |
| `Sources/IndoorbilityCore/OutdoorProgress.swift` | Stable leg instruction independent of course fluctuation |
| `Sources/IndoorbilityCore/NavigationFeedback.swift` | Speech priority/replacement and timing provenance |
| `App/HallwayNavigationView.swift` | Pose processing, availability reuse, cloud-independent guidance, aligned map/debug view, shared agent/Repeat instruction |
| `App/OutdoorNavigation.swift` | Authoritative GPS map position, north-up view, timing, immediate confirmed-leg speech |
| `App/SpatialScanning.swift` | Pose-first callback order, unchanged-string publication suppression, fixed trace bounds/debug vectors |
| `App/NavigationAudioCoordinator.swift` | Synthesis replacement, synthesis-start and display scheduling measurements |
| `App/AppStore.swift` | Pass position timestamp into speech |
| `App/SceneAwarenessService.swift` | Include timing in existing diagnostic export |
| `Tests/IndoorbilityCoreTests/HallwayNavigationTests.swift` | Rotation, backward walk, vertical camera, crossing/recovery tests |
| `Tests/IndoorbilityCoreTests/LiveGuidanceTests.swift` | Stable straight/L/U guidance and speech interruption tests |
| `Tests/IndoorbilityCoreTests/NavigationFeedbackTests.swift` | Reject replay of pre-warning directions |
| `Tests/IndoorbilityCoreTests/NavigationReliabilityTests.swift` | Original-vs-cached graph benchmark and closure check |
| `Tests/IndoorbilityCoreTests/OutdoorProgressTests.swift`, `StairRouteTests.swift` | Course-independent outdoor instructions |
| `docs/NAVIGATION_GUIDANCE_CORRECTION.md` | Findings, measurements, limitations, and physical test procedure |

Unrelated pre-existing working-tree changes (scan-gallery styling, audio asset, recording UI, gesture handling, and project resource registration) were preserved, not introduced by this follow-up.

Latest core suite: **145 passed**. Backend: **24 passed**. Final signed iPhone Release build: **BUILD SUCCEEDED**.

The complete UI run executed all **24 cases**: **23 passed**, and `testSampleOCRRequiresReviewAndReroutes` failed because it tried to tap `readSign` inside the collapsed existing **Map tools** disclosure. Updated `UITests/IndoorbilityUITests.swift` to expand that section before both closure-sign reading and starting a spatial scan. All OCR, report-review, rerouting, and unsupported-device assertions remain. No product UI was changed to accommodate the test. The focused rerun **passed both cases**: guidance/mute (34.257 seconds) and the corrected OCR/review/rerouting test (44.311 seconds). Thus every one of the 24 UI cases has passed across the full run and targeted rerun; the original full-run failure is retained in its log.

Logs: `/tmp/indoorbility-priority-core.log`, `/tmp/indoorbility-priority-backend.log`, `/tmp/indoorbility-priority-ui.log`, `/tmp/indoorbility-priority-ui-recheck.log`, `/tmp/indoorbility-priority-iphone.log`.

No service deployment, device installation, or Git push is part of this task.
