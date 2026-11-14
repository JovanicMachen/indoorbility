# CarePath AI — Codex build brief

## Product definition

Create a **new**, original iPhone application called **CarePath AI**. Its promise: "Find your way inside, even when the usual route changes." Support different navigation needs without presuming they are identical. A user can select a destination, specify constraints such as step-free routing or text-only instructions, and see a route updated when an obstruction is reported. Start with a validated sample building and an ARKit mapping mode that users can try on a compatible iPhone Pro.

The original, differentiated functionality is **barrier-aware navigation with an explainable agent workflow**, not basic indoor navigation alone.

## Environment

- Swift 5.10+/SwiftUI; iOS 17+ native iPhone app; target current Xcode toolchain.
- Core: Foundation, SwiftUI, ARKit, RealityKit/SceneKit where appropriate, Vision for sign OCR, AVFoundation for speech, CoreHaptics/UIFeedbackGenerator for cues.
- Offline-first bundled map JSON. No Supabase/backend required for first demo.
- Optional AI LLM tool caller behind `NavigationAgentProtocol` (mock supported by default). Never hard-code keys in app or repository. If remote model integration cannot be secured in time, ship local command parsing and tool calls that actually work.
- Build with normal `.xcodeproj` or XcodeGen, whichever is reliable; provide reproducible run instructions.

## Originality and reference constraints

- Do not copy or transform source files, asset names, layouts, branding, map fixtures, or code from `sachin-khanal/uva-gwc-ghh-2026` without an explicit license or permission. The repository was found to have no declared license; use only high-level architectural ideas.
- CarePath should not use the Waypoint name, logos, UI styles, demo script, or destination labels except generic examples (e.g., Room 204).
- When using Apple APIs, follow Apple documentation. Label simulation vs real-time AR data accurately.
- Credit external inspiration in documentation when appropriate; do not disguise copied work.

## Core experience and screens

### A. Welcome / preferences

Clean, friendly, high-contrast design (warm off-white, deep teal, vibrant blue for routes, coral for blocked elements), large tap targets, clear status labels, Dynamic Type and VoiceOver accessibility labels. User sets independent toggles rather than rigid disability labels:
- Avoid stairs (default ON for demo)
- Prefer elevators / step-free routes
- Voice instructions ON/OFF
- Large text ON/OFF
- Reduced information mode: one instruction at a time
- Haptic cues ON/OFF

### B. Building map

Show `Demo Learning Center` from bundled `demo_building.json`. Visual top-down map with floor selection (Level 1 / Level 2), landmarks, corridor lines, and a clearly contrasted active path. Search destination (`Room 204`). Choose a current checkpoint (`Entrance`), rather than asserting precise position based on GPS. Show last confirmed position and warning if position is unknown.

### C. Navigation

A* or Dijkstra implementation over nodes/edges with `distance`, `type`, `accessibility_verified`, `blocked`, `last_verified_at`. Route strictly excludes `stairs` if avoidStairs; also excludes any blocked edges. Elevator edges are supported across floors. If no valid route, show *no verified route found*, provide a Help / Contact staff option, never fabricate a route. UI shows current step, floor, next checkpoint, and accessible route explanation. Use offline voice synthesis and optional haptic feedback for transitions.

### D. Barrier reporting

Report a barrier from a prominent action button. Present camera/photo selection; Apple's Vision `VNRecognizeTextRequest` extracts text such as `ELEVATOR OUT OF SERVICE`. A pure parser can propose `Elevator A unavailable` from label match. **User must confirm the feature and status** before map data changes. Show report provenance: photo/manual report, timestamp, `pending/unverified` badge. For MVP, local confirmed report may block the route for this device, while shared/global blocking requires separate verification (defer cloud sync). When blocked, route recomputes and explains what changed.

### E. AI navigation agent

The agent's job is to **use tools and take steps**, not chat. Define protocol-style callable tools:
1. `resolveDestination(query) -> nodeId | needsClarification`
2. `readPreferences() -> constraints`
3. `planRoute(startId, destinationId, constraints) -> route | noRoute`
4. `interpretBarrier(text) -> proposedFeatureId + proposedStatus + confidence`
5. `submitConfirmedBarrier(featureId, status, reporterAcknowledged) -> updatedLocalMap`
6. `replanAndExplain() -> route + simple user-facing explanation`
7. `getCurrentCheckpoint() -> nodeId | unknown`

User example: "Take me to room 204 without stairs." The agent calls resolver, reads constraints, calls deterministic routing, and displays results. After confirmed outage, calls replan. Never allow the LLM to declare an unknown path accessible, silently alter the map, or send safety-critical directions from uncited free-form text. Ship deterministic fallback even if the model service is unavailable.

### F. Mapping / volunteer mode (hardware-conditional)

Build a **separate scanner screen** inspired only by the general category of LiDAR mapping workflows, with distinct CarePath UI. On a supported iPhone Pro:
- Start `ARSession`, `ARWorldTrackingConfiguration`, and if supported `sceneReconstruction = .mesh`; optionally enable `sceneDepth` when supported.
- Show camera feed and current tracking status (`normal`, `limited`, `unavailable`). Show real counts of newly confirmed landmarks, route checkpoints and approximate scanned distance; do not invent coverage percentages or claim LiDAR precision from a test fixture.
- Add landmark buttons for Entrance, Door, Room, Elevator, Stairs, Junction. User may label a landmark; store position in local AR frame where available.
- Record breadcrumb/waypoint candidates every ~1.5–2m; expose Save Draft Map and Review & Confirm before making it routable. Let user walk back for reverse coverage as guidance, not as a false universal requirement.
- Show unsupported-device message / demo map entry on devices without necessary LiDAR hardware. AR relocalization from a saved scan is a *stretch goal*; use manual checkpoint confirmation for MVP navigation instead.
- Demo can succeed entirely via the bundled JSON, even if scanner hardware fails or is unavailable.

### G. Data and safety

Data models (suggested): `Building`, `Floor`, `MapNode`, `MapEdge`, `BarrierReport`, `NavigationPreferences`, `RouteStep`, `EvidenceSource`. Store demo data locally. Use `Codable` and dependency injection to enable tests. Keep map points and movements local by default, ask permission before sharing, and avoid collecting bystanders' photos unless explicitly necessary. Make clear this prototype is not a certified mobility aid or a substitute for a white cane, guide dog, human assistance, or emergency services.

## Navigation graph for deterministic demo

See `demo_building.json` and the accompanying edges. Route from Entrance to Room 204 avoiding stairs: initially prefer Lift A; after Lift A is blocked, choose Lift B. Tests must verify it never uses stairs in step-free mode, chooses the second elevator on outage, and reports no route when both lifts are unavailable.

## Four-phase implementation plan (Codex should work in this order)

1. **Foundation:** project scaffold, models, JSON loader, constrained shortest-path router with tests, gorgeous but lightweight SwiftUI demo building map, building and preferences screens.
2. **Demonstrable workflow:** destination resolver, route display, barrier reporting with manual selection, local status update + automatic replanning, text + TTS guidance, route explanation.
3. **AI and camera:** OCR of barrier signage, explicit confirmation; tool-calling agent integration with mock and offline fallback; no made-up confidence or verified accessibility claims.
4. **Native LiDAR scanner:** live ARKit session, honest tracking status, POI labeling, saved local scan draft, unsupported-device fallback; build/tests/runbook + short pitch.

Cut scanner enhancements before cutting the working route + barrier + replan demo. Cut live remote LLM before cutting deterministic route tests.

## Definition of done

- Builds in current Xcode for iOS 17+; checks compile with no unconfigured secrets.
- Works in Simulator using demo map and manual barrier report.
- Supports a physical iPhone Pro in mapping mode where ARKit mesh is supported, but does not depend on it for the core demo.
- Navigation requests actually invoke route planning, not canned output.
- Photo-based outage parsing requires confirmation; route replanning triggers automatically after confirmation.
- All route restrictions and report provenance tested.
- Contains a README, permissions notes, known limitations, a two-minute demo script and an attribution/originality note.

## Hackathon demo (2 minutes)

00:00 Start at an unfamiliar campus building. A student requests "Room 204, no stairs".
00:25 CarePath presents verified step-free route via Lift A.
00:45 Photograph 'Lift A out of service' sign; OCR proposes a report, user confirms.
01:05 Agent reroutes through Lift B, explains that the original path is now unavailable.
01:30 Switch navigation to spoken vs large-text directions; show last confirmed checkpoint.
01:50 Explain this is accessibility-aware navigation rather than general GPS; note lack of guaranteed indoor positioning in the prototype.
