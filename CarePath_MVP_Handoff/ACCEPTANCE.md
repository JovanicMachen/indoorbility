# MVP acceptance checks

## Simulator release gate

- Clean project builds for an available iOS Simulator with no API keys or cloud setup. Record actual Xcode version and simulator destination.
- Graph loader rejects duplicate IDs, dangling references, unknown versions, nonfinite/nonpositive costs, and invalid floors.
- Router tests cover the five DATA_CONTRACT scenarios, reverse direction, same start/end, unknown start/end, disconnected graph, baseline blocked edges, unverified edges, and deterministic tie handling.
- No candidate/proposed/cancelled report changes routing. Confirmed closure replans from the current checkpoint. Two active reports on one edge require resolving both before reopening.
- Both lifts unavailable produces noRoute with Avoid stairs enabled. Unchecking Avoid stairs allows a stair path explicitly identified as using stairs.
- Relaunch preserves confirmed closures and preferences. A failed persistence write is visible; the UI does not claim saved status.
- On reroute, stale guidance is removed, the new route/list agree, and no false location movement occurs.
- Building counts, cost comparisons, source labels, and dates match stored data. Unknown dates and absent routes remain unknown/absent.
- VoiceOver can perform destination selection, route review, barrier reporting, and no-route recovery without using the visual map. Large accessibility text sizes do not clip actions. Reduced Motion is respected.
- Demo reset is deliberate. No source-project branding, credentials, copied assets, or hidden telemetry appear in the app.

## Later device gates

- Camera denial, missing images, unreadable text, unknown lift names, and cancelled OCR proposals all recover through manual selection.
- OCR reads actual supplied images and always requires target/status confirmation.
- Speech and haptics work on a physical device and can be disabled.
- AR capture checks capability and permission; unsupported devices retain the demo. Lost tracking is visible, and untracked points are not committed as valid landmarks.
- Saved scans reopen as drafts; no automatic claim that an unreviewed scan is a usable route graph.

## Two minute demonstration

At launch show Demo building. Select Entrance and Room 204, keep Avoid stairs on, and preview Lift A. Confirm an outage report for Lift A. Explain the switch to Lift B and show the extra 8 demo cost units in Building details. Confirm Lift B unavailable to demonstrate no route. Resolve the second report and confirm Lift B becomes available again. Show the last confirmed checkpoint and accessible text instructions.

## Evidence to deliver with the app

README with setup/run commands; actual unit/UI/build results; screenshots of normal route, reroute, no-route and Building details; device checks listed separately; known limitations; provenance note. A passing fixture validator alone does not satisfy the app release gate.
