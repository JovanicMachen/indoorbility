# CarePath MVP specification

## Product and design

The primary question is “Where do you want to go?” The primary action is “Show my route.” Start with one fictional building, two floors, and one complete accessible-route demonstration. Offer preferences by function rather than asking people to disclose a disability.

Use a warm neutral background, deep teal primary controls, blue route lines, and orange blocked-route indicators paired with icons and text. Use system typography, semantic colors in dark mode, generous spacing, Dynamic Type, and at least 44-point controls. Avoid custom tiny map controls. Keep technical statistics outside active guidance. Every map action must have an equivalent accessible list action.

## Screens and behavior

| Screen | Content | Main action |
| --- | --- | --- |
| Navigate | Demo building badge, destination search, current checkpoint, Avoid stairs toggle | Show my route |
| Route preview | Floor selector, schematic path, ordered checkpoint list, lift used, Why this route | Start guidance |
| Guidance | One next checkpoint, last confirmed position and time, repeat instruction, progress | Confirm I am here |
| Report sheet | Select affected lift/corridor, unavailable status, optional OCR text, source | Confirm report |
| Route changed | Lift A excluded, Lift B used, additional demo cost, updated preview | Continue |
| No route | Explanation, last confirmed checkpoint, review reports, assistance information | Review barriers |
| Building | Lift status, graph counts, active reports, route comparison and data origin | Inspect report |
| Settings | Avoid stairs, speech, haptics, reduced information, reset demo | Save preferences |

Navigate is available immediately without sign-in or camera permission. Start at Entrance only after user selection or confirmation. Never animate a moving location marker unless explicitly running a labelled demo. Confirming a checkpoint updates the routing origin; advancing the displayed instruction alone must not pretend the user moved. Unknown position pauses guidance and offers checkpoint selection.

Search matches case-insensitive room labels and known aliases. Ambiguous results require choosing a destination; unmatched text never produces a guessed path. Local phrase parsing may accept “Room 204, no stairs.” Label this local command support, not a connected generative model. Speech output and VoiceOver should not compete; users can stop or repeat speech.

## Report lifecycle

A proposed report has no routing effect. Cancel discards the proposal. Confirmation stores a local report and excludes its target edge in both directions. Recompute from the last confirmed checkpoint, preserve preferences, reset stale route steps, and announce the change once. A report is user-confirmed and locally applied, not independently verified.

Persist confirmed reports and settings across relaunch. Undo resolves the specific report; it must not remove other reports or a baseline map closure. An edge stays blocked while any active confirmed report targets it. Reset demo asks for confirmation and clears only this app's demo reports/settings. A missing/corrupt local file produces a recoverable error and must not silently erase barrier records.

OCR suggests a target and unavailable status; users review both. Unknown lift labels and low-confidence or contradictory text require manual selection. Never mark a lift operational based on OCR alone. Permission denial leaves manual reporting usable. An assistance button displays supplied building help information; the fictional fixture has no actual staff number, so offer “Ask building staff” guidance without inventing a contact.

## Native Apple scope

SwiftUI supplies the app shell, system controls, and accessible text/list representations. Foundation contains the graph, deterministic planner, reports, and JSON storage. A separate adapter handles AVSpeechSynthesizer and optional UIKit haptic feedback. Swift Charts can show route comparisons with an equivalent text summary. Vision processes selected sign images on-device. ARKit is a separate draft-mapping workflow.

Apple references: [text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images), [Swift Charts](https://developer.apple.com/documentation/charts), [scene reconstruction capability](https://developer.apple.com/documentation/arkit/arworldtrackingconfiguration/supportsscenereconstruction(_:)).

Gate LiDAR mesh capture with supportsSceneReconstruction(.mesh), not a hardcoded phone-model list. Show tracking quality and measured node/mesh counts only when supplied by the session. Store local coordinate frames, timestamps, and labelled checkpoints. Draft scans require explicit review before becoming routing graphs; a mesh alone does not establish traversability. Unavailable hardware offers the demo. Live relocalization and reliable turn-by-turn heading are deferred.

No health data or HealthKit is needed. No Apple Intelligence dependency is needed. The prototype supports route planning and manual checkpoint guidance; it is not a certified mobility or emergency navigation aid.

## Architecture and sequence

Create CarePathCore for Codable models, graph validation, Dijkstra, report reduction, and destination resolution. Create a main-actor app store that owns preferences, checkpoint, selected destination, reports, and derived route. Views read that store; routing and data screens derive from the same graph revision. Keep camera, speech, persistence, and AR sessions behind narrow services.

Milestone 1: graph validation and routing tests, then native navigation/report/data screens and local persistence. Milestone 2: photo OCR with confirmation and permission handling. Milestone 3: hardware-tested draft scan creation and save/load. Do not delay a working first milestone for later features.

For future AI, accept only typed intents and validated graph IDs. Planning remains deterministic. A language model may explain a computed route, but cannot create edges, verify access, or change a barrier without confirmation.
