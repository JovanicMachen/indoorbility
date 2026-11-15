# Calm, responsive speech

## Behavior

- Tracking, route progress and the map continue updating independently of speech.
  Ordinary direction sentences queue instead of cutting one another off. Safety
  warnings can interrupt a direction, but do not repeatedly interrupt each other.
- The queue holds only the latest pending direction, expires old directions after
  five seconds and checks their route/state again before speaking. Indoor speech
  that was lost can retry after 1.5 seconds if the same instruction is still valid.
  Deliberate Stop/Mute never re-arms speech. Different corners have different
  deduplication keys even if both say “Turn left now.”
- Automatic 12-second direction reminders are off by default. They can be enabled
  under the existing Sound & voice settings with **Occasional direction reminders**.
  Turn/distance-band changes, uncertainty, recovery and arrival still announce.
  Repeat remains available on demand, including while another sentence is playing.
- Ambient comments are skipped while the voice is busy. Explicit answers and
  Repeat are queued rather than treated as optional chatter. VoiceOver gets low
  priority announcements for ordinary lines and high priority for safety warnings.
- Tap-to-talk uses a 1.2-second transcript pause and a one-second bounded final
  result wait. Hold-to-talk waits for release instead of ending at an internal
  pause. Partial transcription changes do not execute commands. Final results,
  explicit completion or recognizer termination still pass through the existing
  destination resolution and confirmation checks.
- A cloud request still pending after 650 milliseconds can receive the local
  acknowledgment “Checking that.” Fast answers skip it; cancellation and completed
  responses cancel the pending acknowledgment. It never claims a destination or
  route changed before the validated device result.
- Internal successful lookups (preferences, state, destination resolution and
  route calculation) are not narrated one by one. Errors, completed user actions
  and the final validated answer remain available. Stop, Repeat and “where am I”
  use the local hallway handler without waiting for an AI request. Exact command
  matching avoids treating “take me to the bus stop” as Stop.

## Scope and evidence

This implements speech scheduling ideas observed in Waypoint using Indoorbility's
existing Swift core, speech synthesizer and OpenAI agent. It adds no narrator API,
framework, backend service or credentials. Live turn wording and timing remain
deterministic on the phone; no extra model request sits in front of a turn or
safety warning. Route geometry, position confidence, authentication, stored scans
and the existing travel audio are preserved.

Configured waits changed from 2.5 + 4 seconds to 1.2 + 1 seconds on the tap-to-talk
fallback path. This is a reduction in application timer budgets, not a measured
physical recognition or acoustic latency result. Recognizer final results can
arrive earlier. Speech accuracy, Bluetooth routing and perceived helpfulness need
a physical retest, including casual speech, mid-sentence pauses and hold/release.

Regression coverage includes sentence ordering, safety interruption, expired and
invalidated directions, explicit Repeat, adjacent identical turns, lost-line
retries, optional reminders, silent internal tool steps and exact local commands.
Simulator UI tests exercise production guidance/audio mute/recovery, camera
controls before GPS readiness, and persisted narration controls. These tests do
not establish walking accuracy or VoiceOver acoustics on a physical iPhone.

Validation on November 14, 2026: 218 core tests, 31 backend tests and the three
selected simulator UI regressions passed. A UI regression initially caught a
sign-review cancellation reply being dropped as ambient chatter; the production
speech categories and cancellation handling were corrected, and the test passed
on rerun. The signed iPhone build passed and was installed and launched on the
existing paired phone without an uninstall. Microphone/recognition responsiveness
and VoiceOver output have not been physically measured in this change.

References:

- [Waypoint speech gate](https://github.com/sachin-khanal/uva-gwc-ghh-2026/blob/8778e967a080d195d88b2726da57e0e9fab483f9/Package/WaypointCore/Sources/WaypointCore/Guidance/SpeechGate.swift)
- [Waypoint feedback planner](https://github.com/sachin-khanal/uva-gwc-ghh-2026/blob/8778e967a080d195d88b2726da57e0e9fab483f9/Package/WaypointCore/Sources/WaypointCore/Guidance/FeedbackPlanner.swift)
- [Apple announcement priorities](https://developer.apple.com/documentation/uikit/uiaccessibilitypriority)
