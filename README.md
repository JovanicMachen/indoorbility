# indoorbility

# Indoorbility

Native SwiftUI navigation with remembered indoor destinations, ARKit/LiDAR mapping, Google building discovery, native outdoor maps, accessibility controls, and a local planning assistant. Existing routing, OCR, reports, voice/face controls and demo data remain intact.

## Fresh checkout

Run `make project` before opening Xcode: this refreshes project resources without the ignored, machine-local Google Places configuration. Optional Google Places setup uses `Configuration/MapsConfig.example.plist`; never commit real keys. Apple/local navigation and the agent source remain included. See [repository and Railway setup](docs/GITHUB_SETUP.md).

## Run

Open `Indoorbility.xcodeproj`, select Indoorbility and your iPhone, then Run. The existing signing team is retained. Minimum iOS: 17. Mapping requires a physical device supporting LiDAR mesh reconstruction; the simulator cannot prove navigation accuracy.

```sh
make test
make build
make uitest SIMULATOR_ID=YOUR_SIMULATOR_UUID
```

Use `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` if required. `make project` regenerates source membership, preserves the existing app signing team and includes local Maps configuration when present.

## Everyday flow

**Navigate → search or choose a room → Go with camera.** The home screen shows destinations rather than scan folders. The most recently selected destination moves to the top; confirmed visits are remembered locally.

For an unmapped hallway, choose **Remember a new route**:

1. Enter the building, room, and a recognizable entrance name/sign.
2. Start mapping and confirm the entrance while standing there.
3. Walk the known same-floor hallway to the room. A five-second blue wireframe briefly shows the actual LiDAR surfaces; Show mapped area briefly replays it.
4. Confirm that you walked a clear, step-free path, then confirm the room. The app saves the scan and constructs its measured hallway route automatically. A trace preview confirms what was saved.

LiDAR measures observed surfaces; it does not discover unseen room locations, certify accessibility, or invent a building graph. First-time mapping therefore still needs truthful landmark/path confirmations. Interrupted or geometrically invalid walks do not become usable routes. Raw capture tools remain under Scan for inspection and recovery.

On return, the camera relocalizes against the saved world map. Stable mapped entrance position plus fresh exact OCR of its distinctive sign can automatically start guidance. Generic labels such as “Entrance” alone cannot establish identity. If recognition fails, manual entrance confirmation or two-landmark recovery remains available. Progress and heading-relative instructions update continuously; uncertainty, frame gaps, jumps and off-route movement suspend guidance.

Arrival needs the existing near-room dwell plus either fresh matching room-label recognition or manual label confirmation. A confirmed visit is remembered. Saved arrival history is never treated as a current position.

## Outdoor journey and Google API

The supplied credential is configured locally in ignored `LocalConfig/MapsConfig.plist`; its value is not in source or documentation. Xcode copies this configuration into the app for Google Places requests. For another checkout, copy `Configuration/MapsConfig.example.plist` to that local path, fill in a valid Places API (New) key, and regenerate the project. A client Maps credential should be restricted to the relevant iOS app/API before distribution; no AI-model/server credential is embedded.

Google discovery uses Places API (New) Text Search with explicit field masks, an iOS bundle identifier header, HTTPS, timeouts, and an ephemeral URL session. Search is user-initiated; responses are not imported into the indoor graph or persisted. A live one-result request using the supplied key succeeded during implementation. Billing/API availability still belongs to the Google project.

**Discover buildings with Google** displays attributed Google results separately. Its outdoor-directions action searches the user's original words independently with Apple. Google place coordinates are not transferred to MapKit. Main outdoor maps and directions stay in the app using Apple MapKit/Core Location; optional Google detail links are not required for navigation.

If a fresh accurate GPS fix is available when the user confirms a mapped entrance, its location is stored locally. The room's destination sheet then offers **Directions to the entrance**. Approaching within 50 m with suitable GPS accuracy prepares the camera automatically. GPS only prepares localization: actual indoor guidance still requires saved-map alignment and entrance evidence. Failed recognition offers landmark recovery. All camera/location use is foreground-only.

MapKit walking routes do not establish wheelchair/step-free access. With Avoid stairs enabled, the app shows only the outdoor destination and explicitly withholds an unverified outdoor route. Reviewed indoor paths continue respecting the hard constraint. With that preference disabled, Apple walking-route previews and instruction lists are available. This is not a full background turn-by-turn outdoor navigation SDK.

## Assistant and shopping

Assistant is a **deterministic local fallback**, not a connected cloud LLM. It resolves exact known room labels/building qualifiers, uses structured verified route calculations, and explains unknown/ambiguous locations. It can strengthen but never silently weaken a saved no-stairs constraint. No LLM provider credential was supplied; the Maps key is not used as an AI-model key.

Try “Take me to Room 204 in [your mapped building]” or “Buy milk, cereal, shampoo and paper towels”. Unknown rooms are not fabricated. A closed sole hallway produces no route.

Shopping uses a clearly labeled fictional Corner Market graph and sample product catalog. Its exact small-stop optimizer uses existing Router distances, hard stair exclusion and closure exclusions, with checkout last. Add/paste/type items (system keyboard dictation is available), collect/skip/remove items and simulate an aisle closure; the remaining trip recalculates from the current simulated location. Unknown products remain explicitly unlocated. The demo trip is saved locally. No retailer inventory/aisle integration is claimed.

## Reports and accessibility

Existing voice/face command controls, spoken narration, haptics, VoiceOver, Dynamic Type and reduced-information settings are preserved. Live hallway guidance respects narration/haptic preferences. Voice/face commands remain scoped to the existing command panel/demo, not continuous facial control while walking.

Live guidance's More menu includes sign reading, manual closure reporting, recovery, pause and a user-operated share sheet for requesting help. Vision OCR and conservative local interpretation suggest known lift/hallway closures; the user must confirm before routes change. Reports are timestamped local observations, not official verification. Reports over 24 hours old request review and remain blocked until explicitly resolved. An expired review never silently reopens a path.

## Data and permissions

- Camera: mapping, saved-world-map localization, OCR and optional face controls.
- Location When In Use: outdoor maps and a manually confirmed entrance fix. GPS never supplies indoor position.
- Microphone/Speech: existing explicit push-to-talk only.
- Local files: demo state, per-scan mesh/world map/landmarks, `hallway.json`, per-route report state, optional `entrance-location.json`, and `destinations.json`. Shopping simulation uses app preferences storage.
- Network: user-requested Google search; Apple search/directions/maps. No camera images, raw scans or facial data are sent to either provider by this implementation.
- No backend, account, Supabase dependency, cloud synchronization or LLM credential added.

Public app distribution still needs the app's own published privacy/terms pages and provider configuration review; this local build includes provider attribution/links, not a claim that release requirements are finished.

## Validation and remaining physical checks

See `BUILD_STATUS.md` for exact automated results. Core tests cover alignment, graph validity, tracking loss, off-route progress, fresh entrance/arrival evidence, GPS-only false transitions, destination serialization, agent validation, hard accessibility constraints, optimized shopping/rerouting and closure review.

Physical iPhone acceptance remains mandatory:

- Map a measured real hallway; compare trace/landmark positions with ground truth. Verify blue mesh outlines match actual surfaces and fade after five seconds.
- Revisit after relaunch. Test entrance sign matching, low light, changed furniture, generic/duplicate/wrong signs, portrait/landscape, and saved-map failure. Wrong sign or GPS-only proximity must not start guidance.
- Walk turns/backtrack; cover the camera, point it vertically, background the app, interrupt capture during saving, and test stale frames. Guidance must suspend; no stale pose may confirm arrival.
- At the room, check dwell plus fresh matching label, unreadable label/manual fallback, walking away, wrong room/floor and tracking loss. Verify visits persist but current position does not.
- Test outdoor GPS accuracy/denial, automatic camera preparation, failed handoff recovery, foreground resume and no-stairs behavior. Location permission is optional for indoor mapping.
- Test VoiceOver, large text, narration/haptics and accessibility usability with intended users. Existing optional facial controls are seated interactions.

Initial thresholds (0.8 m arrival, 1.5 m off-route, two-second stabilization/dwell) require field calibration. This implementation remains one reviewed hallway per scan. Multi-floor real-building mapping, mesh-derived clearance certification, obstacle avoidance, shared maps, live retailer feeds, remote AI and continuously guided outdoor routing remain outside the verified slice.

## Demonstrations

See `docs/DEMO.md` for the two-minute campus/retail demonstration. Demo geometry and products are explicitly fictional. No reference-project code, assets or prose were imported.
