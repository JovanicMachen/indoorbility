# CarePath — acceptance checklist

## Required functionality
- [ ] Launches into an original, legible SwiftUI interface with `Demo Learning Center` sample building.
- [ ] A user can choose step-free vs shortest route, voice vs text, and larger guidance.
- [ ] A user can ask for `Room 204` and select `Entrance` as a last-confirmed starting checkpoint.
- [ ] A step-free route is computed by a real graph algorithm and initially uses `Lift A`.
- [ ] A separate shortest route may use stairs only if the user's restrictions explicitly permit them.
- [ ] User can report `Lift A out of service` manually; camera/OCR is implemented if feasible.
- [ ] The app requires confirmation before updating a map edge from an OCR suggestion.
- [ ] After confirmation, it recalculates using `Lift B` and explains why.
- [ ] If Lift A and Lift B are blocked in step-free mode, it returns **no verified route available**, never stairs.
- [ ] A user can see report source/time and that reports are local/unverified.
- [ ] Speech or large-text guidance is offered; VoiceOver labels and Dynamic Type are included.
- [ ] The navigation agent calls real tools; it does not fabricate route data.

## Native mapping
- [ ] Scan screen displays honest ARKit tracking state on supported hardware.
- [ ] User can manually add a Room, Door, Junction, Stairs or Elevator POI to a local draft.
- [ ] Scanned map drafts are distinct from a validated/navigable map.
- [ ] Unsupported hardware has an understandable fallback.

## Engineering checks
- [ ] Unit tests: blocked edges are excluded.
- [ ] Unit tests: stairs are excluded with step-free requirement.
- [ ] Unit tests: Lift A selected initially; Lift B after outage.
- [ ] Unit tests: no path when both elevators blocked for step-free user.
- [ ] Unit tests: missing landmark or ambiguous OCR cannot change map without user confirmation.
- [ ] Demo succeeds without network connectivity or AI API key.
- [ ] App contains no copied Waypoint code or assets.
- [ ] README documents what has and has not been tested on a physical device.

## Hackathon delivery
- [ ] Public repository created during permitted contest interval.
- [ ] Short demo video (optional) and two-minute spoken pitch prepared.
- [ ] Main track selected based on actual submission rules; Amazon special track selected only with working AI behaviors.
