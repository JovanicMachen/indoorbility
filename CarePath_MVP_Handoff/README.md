# CarePath native iPhone MVP handoff

CarePath helps someone choose a destination inside a building and adapt their route when a lift or corridor becomes unavailable. This package is a build-ready specification and validated demo dataset, not a compiled iPhone application.

The requested direction is an original native Apple app with a simpler interface and visible, understandable map data. CarePath is the working name inherited from the supplied ZIP; naming is still editable. The first release is an offline demonstration with manual position confirmation.

## Start here

Open this extracted folder as the project workspace and use `CODEX_START_PROMPT.md` as the next build request. Read `MVP_SPEC.md`, `REFERENCE_REVIEW.md`, `DATA_CONTRACT.md`, and `ACCEPTANCE.md`. The original supplied files remain intact under `prior_context/` for context. The new root specifications resolve ambiguities in those earlier files.

Run `python3 validate_demo.py` to verify the bundled graph and expected route scenarios. This validates the dataset; it does not validate an iOS implementation.

## What the first app should demonstrate

1. Select Entrance and Room 204 with Avoid stairs enabled.
2. Preview the route through Lift A.
3. Report Lift A unavailable and explicitly confirm the report.
4. See the route switch to Lift B, with a plain-language explanation.
5. Open Building details to inspect route cost, lift status, report provenance, and the map's demo status.
6. Block Lift B too and see a clear no-route state without a stair fallback.

## Delivery boundary

Required first: native SwiftUI simulator app, deterministic routing, local reports, accessible guidance, data screen, persistence, tests, and reproducible build instructions. Next: on-device sign recognition and a LiDAR draft scanner. Deferred: cloud collaboration, automatic indoor positioning, obstacle avoidance, spatial audio, 3D reconstruction viewer, remote AI, Apple Watch, and Live Activities.

No third-party repository source, branding, assets, or writing is included. The reference review retains source links for engineering provenance.
