> Pilot update — 2026-11-14: **Friend Center for Engineering Education, LL, Rooms 006 and 008** supersedes Frist. Identity/access metadata is preloaded separately from routable geometry. No authorized metric LL plan or surveyed localization asset has yet been established. See [Friend Center field test](FRIEND_CENTER_FIELD_TEST.md) for sources, implementation gaps and physical validation gates. Visitors must not be required to scan; mapper preparation stays optional/developer-only.

# Stage 2 — verified building maps with live iPhone guidance

Updated 2026-11-14. This is an implementation plan, not a claim that Stage 2 has been built or physically validated. It supersedes scan-first onboarding and makes the optional saved-mesh viewer secondary to the first real navigation demonstration.

## Product scope

Two cooperating inputs power one destination-first experience:

1. Pre-existing, verified building data supplies entrances, floor identities, rooms, doors, elevators, stairs, accessible connections and route geometry.
2. The iPhone camera, ARKit tracking, supported LiDAR depth and recognizable landmarks establish and maintain a verified pose against that data. Local guidance provides speech, visual instructions and cautious surface alerts; the existing OpenAI agent operates through validated tools.

A visitor searches or speaks a destination, confirms an ambiguous match if needed, and opens camera guidance. The visitor does not create a scan, draw a route, label rooms or open a 3D viewer. If localization is not ready, show one concrete instruction such as “Point toward the entrance sign,” with an accessible recovery option. Do not silently treat a selected entrance, GPS fix or OCR string as a verified camera pose.

Manual capture remains available under developer/testing tools. No community mapping, shared publishing, Supabase, crowdsourcing or automatic uploads. Map assets and localization evidence remain on-device. Preserve the existing explicitly opted-in agent data boundary; do not transmit full maps, meshes or camera streams to the model.

## Current architecture and evidence

| Existing component | Reuse | Gap for Stage 2 |
| --- | --- | --- |
| `Building.swift`, `Router.swift` | Floors, checkpoints, explicit connections, closures and stair exclusion | Diagram coordinates lack metric frames, provenance, door geometry and localization anchors. Stair exclusion alone is not proof of wheelchair accessibility. |
| `HallwayNavigation.swift` | Rigid alignment, measured progress, tracking-loss/off-route gates, arrival evidence | Currently follows a reviewed same-floor scan trace. Needs an adapter for verified route polylines from building packages, without pretending they came from a scan. |
| `SpatialScanning.swift` | Existing ARSession, LiDAR reconstruction/depth, bounded processing and local save | `ScanLibrary` already saves `world.arworldmap`, measured `mesh.json`, and separate reviewed hallway data. Rendering currently uses SceneKit; a saved RealityKit viewer is not implemented. |
| `HallwayNavigationView.swift`, `EntranceRecognition.swift` | Live coordinator, OCR evidence, landmark recovery and validated agent actions | Associate evidence with authoritative building/floor/landmark IDs; use map revision and pose freshness when applying changes. |
| `LiveGuidance.swift`, speech/audio coordinators | Measured instructions, cues, mute, accessibility and arrival gating | Consume the imported verified route geometry and preserve current testing/diagnostics. |
| Home, Help, agent tools | Destination confirmation, voice input, tool execution and offline fallback | Search a unified verified building catalog instead of requiring a saved personal scan. |

The bundled demo building explicitly identifies itself as fictional and its coordinates as diagram positions. It cannot be used as physical-demo evidence. No authoritative real floor-plan asset was found in the inspected project. Existing simulated test results do not establish walking accuracy, sensor performance or real model execution against a physical building.

## Local building package

Add a versioned package and loader alongside existing scan storage; do not break old maps or replace the tested router.

- **Manifest:** stable building ID, revision, source authority/file or URL, source date, import/review date, reviewer, usage permission, asset hashes and supported coverage. Store verification evidence, not merely a blanket `verified=true` flag.
- **Floor frames:** explicit floor ID/label, metric units, coordinate origin and axis conventions, scale calibration evidence and uncertainty. Floor elevation may be unknown; never synthesize it from the floor number.
- **Graph:** stable room, door, entrance, landmark and connector IDs. Separate room identity from its navigable doorway/arrival area. Each edge has a metric polyline, source-supported length, floor association, traversal direction, closure state and verified access attributes. Preserve unknown width, slope, step-free status or elevator availability as unknown.
- **Localization anchors:** known floor-frame position plus evidence type, identity, physical dimensions/orientation where available, observation rules and calibration provenance. Persist floor-plan-to-AR alignment explicitly, including the map revision and confidence checks.
- **Optional localization assets:** a previously prepared, reviewed ARWorldMap and its rigid transform to the floor plan, or surveyed visual reference anchors. These are prepared before the visitor arrives; neither is a synthetic world map generated from a drawing.
- **Optional measured mesh:** a separately versioned, explicitly captured mesh with its coordinate transform and coverage metadata. Mesh absence never prevents routing on an otherwise verified building map.

Validate assets before atomic installation: finite coordinates, unique IDs, valid references, supported units/versions, positive edge lengths, consistent scale, correctly paired floor connectors, evidence for accessible edges, connected doorway positions and matching localization revisions. An invalid update must leave the last valid package usable. Restrict imported paths to the package and cap file sizes/counts. No partial imports become routable.

## Implementation sequence and acceptance gates

### 1. Select and prepare one real building

Obtain an official or otherwise attributable floor plan and building metadata. Select one known entrance, two labeled rooms on the same floor, and an independently checked accessible hallway connecting them. Record elevators/stairs and other floors only where the source supports them; the first demonstration does not need to traverse them.

For a raster/PDF plan, a developer traces and reviews the graph offline. OCR/vector extraction may propose labels and geometry, but cannot approve them. Establish metric scale using authoritative dimensions or surveyed control distances. Explicitly mark unsupported regions and resolve source discrepancies before enabling routes.

**Gate:** a reviewed real package with source, scale, landmarks, room labels and current route/access verification. Missing source or survey data blocks only that real package—not schema, validation and integration work. Use clearly labeled synthetic fixtures for automated tests; never relabel them as the real building.

### 2. Import graph and expose destination discovery

Implement the local package repository, schema validation and a catalog adapter for existing destination resolution/agent tools. Reuse Router for eligible graph edges. Add supplemental geometry/access metadata rather than changing the meaning of existing diagram fields. Unknown required accessibility evidence excludes a connection from the accessible route; report no verified route if necessary.

Home stays search/voice-first. Resolve room + building + explicit floor metadata, ask only for missing/ambiguous information, and retain user preferences and closures. Never infer a floor from a room number. Move manual map creation/scan management into a clearly labeled developer mapping area without removing existing data or tools.

**Gate:** exact/ambiguous/unknown destination behavior, invalid-package rejection, closure enforcement and accessible route selection pass automated tests. No personal scan is needed to discover a room.

### 3. Register the live camera to the preloaded map

Choose one concrete localization method for the physical demo:

- Relocalize against a developer-prepared ARWorldMap whose transform to the verified floor frame has been checked; or
- Observe a surveyed, recognizable visual anchor with known size/orientation to determine pose, with OCR as supporting identity evidence. If orientation cannot be established, require independent surveyed landmarks and checks before beginning guidance.

A floor-plan image alone does not determine AR camera pose. OCR text alone does not determine camera position, distance or heading. GPS may narrow the building search, but cannot verify indoor floor or room. Reject duplicate signs, wrong-building evidence, wrong-floor anchors, stale frames and ambiguous matches.

Maintain a clear state flow: destination selected → locating → verified guidance → recovery required → verified arrival. Require consistent evidence and stable tracking; show no world-anchored direction until alignment is trusted. Avoid ongoing scans as a prerequisite: bounded landmark observations are localization, not visitor map creation.

**Gate:** physical evidence demonstrates alignment at the entrance and an independent checkpoint. Unit tests cover transforms, units, handedness, heading, mismatched revisions, ambiguous anchors and recovery. Record alignment residuals; do not invent measured performance values.

### 4. Route following and agent integration

Build a verified-route geometry adapter from the selected graph edges to the live follower. Keep the existing scan-based route type and tests working; do not manufacture a ScanDraft/ARWorldMap to satisfy its validation. Generalize only the shared progress logic needed by both sources.

Preserve one ARSession across voice interactions, map toggles and same-map reroutes. Destination changes must use a fresh verified pose and current closures/preferences, cancel stale speech, update the real route state and announce the new instruction. Do not cache a previous pose as current during tracking loss. Unknown/unreachable destinations leave the active safe state unchanged.

Floor transitions require an explicit verified connector, transition state and fresh evidence on the destination floor. An elevator trip, room number, barometer reading or AR vertical displacement alone does not establish floor identity. Until physically tested, cross-floor guidance remains outside the first demo's verified coverage.

**Gate:** walk entrance → first room; change to second room through the real agent while tracking continues; demonstrate closure handling, recovery and evidence-gated arrival. Routine directions and surface warnings stay local. An unmapped alternative produces a truthful no-route result.

### 5. Physical demonstration and diagnostics

Build/install on a LiDAR-equipped iPhone and run without a personal scan library. Record app/map versions, device/OS, source evidence, initialization method and environment. Keep diagnostics developer-only.

Expose: active building/floor/map revision, anchor identities, alignment residual and freshness, tracking state, verified pose and heading, graph edge/progress, route state, LiDAR capability, arriving depth frames, confidence distribution, processing latency/skipped frames, last speech/cue, and agent tool execution/results. Measure memory/frame time with the optional mesh viewer closed and opened; do not load a complete mesh into ordinary live navigation.

Run this sequence with a sighted helper and independently measured checkpoints:

1. Cold launch, search for a real verified room, and confirm the building. No scan-creation screen appears.
2. Acquire entrance alignment using the selected real anchor method. Compare pose/heading against independent reference marks, not the same anchors used to fit the transform.
3. Walk at an ordinary pace. Record checkpoint position error, turn timing, tracking interruptions, initialization/recovery time and frame/depth latency. Set documented acceptance tolerances before the trial using corridor width and clearance; do not use a universal assumed accuracy threshold.
4. Say “Actually, [second verified room] instead.” Confirm the destination. Record real model/tool execution, actual route-state change and unchanged ARSession identity. Synthetic tool logs are not evidence.
5. Apply a clearly labeled test closure to a verified edge. Route only through another verified eligible connection, or report no route. Keep test closures separate from permanent building facts.
6. Cover the camera, show a wrong/duplicate sign, and test a stale pose. Directions/path overlays must suspend and offer recovery. Re-establish alignment before continuing.
7. Test a wall, low object, glass, moving person and downward-facing phone in a controlled area. Record missed and false surface warnings. Do not claim object classification or guaranteed obstacle avoidance.
8. Confirm arrival only with fresh near-destination geometry, dwell and corroborating room/door evidence. A nearby wrong door must not pass.
9. Repeat mute, speech, VoiceOver/large text, haptics, microphone denial, headphones, app backgrounding and offline deterministic guidance. Verify agent failure does not interrupt safe local navigation.

**Release gate:** retain raw measured results and distinguish passed, failed, not tested and not applicable per scenario. A successful build, simulator route or scripted backend test never counts as physical validation. If alignment or clearance accuracy fails, keep the route in testing status rather than implying production readiness.

## Earlier 3D-map request: retained, optional and secondary

The latest two-input MVP priority takes precedence. A polished saved-map viewer is not a dependency of destination search, localization or the first physical demonstration.

After the primary demonstration, improve developer capture/review and the optional saved-building **View 3D map** action using supported RealityKit rendering of the actual persisted ARMeshAnchor geometry. Keep ARWorldMap, mesh and graph as separate linked assets with explicit transforms and revisions. The graph records reviewed walkability; a mesh face is never automatically a navigable edge. Imported 2D geometry, if displayed, must be labeled as floor-plan geometry rather than measured reconstruction; never fabricate heights or a complete building model.

Preview captured coverage and quality before committing a scan. Preserve holes/unscanned regions; explain missing mesh, weak mapping, interruptions and insufficient landmark coverage. Validate triangle indices/transforms, stage files atomically and reopen saved assets in tests. Use compact indexed/chunked mesh storage, background decode, bounded rendering/LOD and lazy loading. Keep visitor navigation independent of mesh decoding and never replace the working live session solely to open a viewer. Rotate/zoom/inspect labels are optional; provide an accessible textual room/route alternative.

This follow-on is a developer/local-viewer enhancement, not a third mapping strategy or community publishing pipeline.

## Status and next input

- Existing: native AR/LiDAR capture/depth, local measured mesh and ARWorldMap persistence, reviewed scan-route guidance, routing/closures, agent tools, speech/cues/accessibility and developer diagnostics/simulation.
- Planned: authoritative building package/import, explicit metric graph/anchor metadata, imported-route live adapter, first-visitor localization against that package and real end-to-end demonstration.
- Deferred behind the demonstration: polished RealityKit saved-mesh viewer and broader multi-floor rollout.
- Unverified: real walking accuracy, sensor performance, false/missed surface alerts, pose alignment to an authoritative floor plan and the Stage 2 physical agent-reroute scenario.
- Needed for the physical package: the target building and a floor-plan file or authoritative URL, plus access to verify scale, landmark locations and accessible connections. Do not substitute the bundled fictional map.

Only this plan is changed in this update. No runtime features or physical validation are claimed by the plan itself.
