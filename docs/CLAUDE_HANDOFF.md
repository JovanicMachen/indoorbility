# Indoorbility development handoff — November 14, 2026

Start here when continuing this repository in Claude. The README and older build
reports contain historical milestones; inspect current code before relying on
their feature or verification claims.

Latest speech changes are described in [Calm, responsive speech](CALM_RESPONSIVE_SPEECH.md).

## November 15 update — 3D models, spoken names, route choice, start-here

- Routes has a cube button (top right) opening `ScanModelGalleryView`: every saved scan
  as a rotatable SceneKit model on a night-sky backdrop, with the walked path drawn as a
  cyan tube (green start, gold end stop). Code is in `App/VolunteerReviewView.swift`.
- `SpokenPlaceMatch` (core) repairs misheard names ("louis rm strng" → "Louis Armstrong")
  against saved rooms/buildings only; digits must match exactly and close ties are not
  guessed. Saved names are also passed to speech recognition as contextual strings.
  When outdoor search finds nothing, the app tries a saved-name fix, then the new
  backend `mode: "place"` spelling agent (tool-free), and searches once more.
- Navigation agent prompt now repairs speech spelling, retries via
  getNearbyMappedDestinations, and allows six device calls (app loop raised to 7).
  The phone still only accepts a destination that matches its saved catalog.
- `RouteChoice.ranked` picks, among recordings to the same room, the one whose
  recorded start pin is nearest your GPS fix (ties within GPS error keep saved order).
- "I'm at the start" now uses `HallwayFollower.followFromStart`: forgiving GPS-style
  following toward the recorded end stop, re-finding your place after detours.
- Validation: 231 core tests, 43 backend tests, simulator build, gallery checked in the
  simulator. Backend deployed to the existing Railway service as deployment
  `9361aa93-6827-4550-8cdf-4f1978418928` (same `/data` volume, no variable changes):
  `/health` ok, `/ready` ready, unauthenticated `/agent/check` and `place` turns return 401.
  Deploy by running `railway up` from a staging folder that contains `backend/` (the service
  root directory is `/backend`; `--path-as-root` fails). Authenticated production place
  correction and physical iPhone checks are still pending.

## General questions — November 14 update

The existing microphone and Help/Home input now accept general questions and
short follow-ups, including during outdoor, indoor and camera assistance. Answers
are concise. Navigation and safety speech can interrupt a general answer.
This does not enable an always-listening microphone or live web search.

`Sources/IndoorbilityCore/GeneralAssistant.swift` and `backend/general_assistant.py`
share routing fixtures in `Tests/Fixtures/general_assistant_cases.json`. General
conversation uses a separate tool-free agent and typed answer. Its request does
not send live pose, room catalog, closures or route context to OpenAI. Conversation
history retains only three question/answer pairs in app memory; navigating to
device actions clears that host's chat history. It is not stored in UserDefaults,
Keychain or the backend database. Explicit user text/history is still sent to
OpenAI; Responses storage and SDK tracing are disabled. The output filters are
defense in depth, not proof that every generated fact is correct.

The original device-tool coordinator, authentication, ownership and offline
navigation remain separate. General answers cannot execute device tools, and
general failures never fall through into destination parsing. Without a cloud
connection, the app says general questions need AI; local navigation continues.

Validation: 226 core and 40 backend tests passed. Two real authenticated local
HTTP/OpenAI requests answered “What is LiDAR?” in 2,096 ms and “And why is that
useful?” in 757 ms, with zero device calls. These are single samples including
provider/network time, not speech latency benchmarks or physical navigation tests.
The signed iOS build passed and was installed and launched on the existing paired
iPhone after it reconnected, without uninstalling or resetting credentials/data.
Three selected simulator UI regressions
passed: general questions while offline without creating a destination, full-screen
search/Settings swipe-back, and production guidance/mute/tracking recovery. The
new UI test initially typed before the keyboard transition finished; waiting for
keyboard dismissal and reappearance fixed the test timing, with no production
UI workaround. This is not a full UI-suite run.

Production release: existing Railway deployment
`39bc8292-c9b3-4845-a14f-27d84cdb41f4` is SUCCESS. `/health` confirms
`generalQuestions: true`, `/ready` returns ready, and unauthenticated `/agent/check`
returns 401. The same 500 MB `/data` volume remains READY; no environment variables,
service, signing secret or pairing records were replaced. Production authenticated
general Q&A has not been checked on the physical iPhone yet. Backend source is
deployed from the working tree; this update is not yet committed/pushed.

## Current implementation

- Native SwiftUI app, iOS 17 minimum, bundle ID `com.indoorbility.app`.
- Apple MapKit/Core Location is the default outdoor navigation provider.
  Google Navigation is an explicit retry option after Apple route failure, with
  SDKs pinned to 11.1.1. See `App/OutdoorNavigation.swift`,
  `App/GoogleWalkingNavigation.swift` and `Sources/IndoorbilityCore/OutdoorProgress.swift`.
- Indoor navigation follows measured, reviewed route geometry from a saved
  ARKit/LiDAR recording. GPS coordinates do not establish a local indoor pose.
  Unmatched routes show an explicitly labeled preview; live progress requires
  trustworthy saved-map alignment. Preserve confidence, floor and arrival checks.
- Indoor navigation's view menu contains Camera and Map. Repeat, microphone and
  Stop remain available. Preserve the existing beige/plum design.
- Startup uses bounded derived geometry caches and a mesh-stripped compressed
  world-map cache. Original scans and route coordinates remain unchanged.
- Session activation and audio clip playback use the serialized `AppAudioWorker`
  actor. Cancellation gates prevent stale playback after Stop/Mute; recording
  leases prevent old recording cleanup from deactivating a newer session.
  See `docs/XCODE_WARNING_FIXES.md` for details and limitations.
- Home controls were moved toward the middle, with subtle seasonal decorations
  that respect Reduce Motion and high contrast. The logo is an iOS app icon;
  the website was not changed.
- The existing FastAPI/OpenAI agent backend remains configured at
  `https://indoorbility-production.up.railway.app`. See the general-question release
  above for the latest verified deployment and its limits.
- Device authentication retains Keychain credentials, short-lived access tokens,
  rotating refresh credentials, durable device identity and server revocation.
  Backend changes remove fixed 30-day expiry for new/renewed credentials and
  support idempotent recovery after an interrupted rotation. An existing expired
  or revoked legacy credential is not silently revived. Preserve the existing
  signing secret, persistent auth database and map ownership on Railway.
  Account-based enrollment is a plan, not implemented signup:
  `docs/ACCOUNT_AUTH_PLAN.md`.

## Setup on another checkout

1. Clone the repository and open its folder. Use full Xcode on macOS for the app.
2. Optional Google configuration stays outside Git. Copy
   `Configuration/MapsConfig.example.plist` to `LocalConfig/MapsConfig.plist` and
   configure restricted SDK/Places keys locally only if those services are needed.
   Apple routing needs no Google key.
3. Run `make project`, open `Indoorbility.xcodeproj`, select the existing signing
   team and a LiDAR iPhone, then Run. The generator preserves SDK dependencies,
   app icon and signing team. Do not uninstall the app to update it; that risks
   losing locally stored scans. Device Keychain credentials are not in Git.
4. Backend development: follow `backend/README.md`, install the pinned
   `backend/requirements.lock.txt` in a local virtual environment and configure
   secrets locally. Do not create a second Railway service or replace its
   environment/storage as part of routine development.

## Earlier checkpoint verification

- 198 Swift core tests passed, zero failures.
- 31 backend tests passed, zero failures, including a real localhost process
  restart and interrupted renewal recovery. These are not production Railway tests.
- Two simulator UI regressions passed: production guidance/audio mute/recovery
  and camera route controls before GPS readiness. This is a selected subset,
  not a claim that the full UI suite was rerun.
- Signed iPhone build passed; the warning-fix build was installed and launched on
  the existing paired iPhone. No uninstall or credential reset was performed.
- Reported Google listener, deprecated map initializer/Bluetooth/floor bounds
  warnings were corrected. New audio cancellation and rotated floor-bound tests
  passed. No new measured physical latency or walking-accuracy result was obtained.

Commands:

```sh
make test
make build
make uitest SIMULATOR_ID=YOUR_SIMULATOR_UUID
cd backend
.venv/bin/python -m unittest -v
```

## Next physical checks

Walk one measured outdoor route to a verified entrance, then the previously
reviewed Friend Center main entrance to Room 006 route (or another genuinely
recorded route). Compare remaining distance and turn timing with measured ground
truth. Rotate the stationary phone, walk backward, approach a parallel corridor,
interrupt tracking, relaunch and recover without losing the destination.

Check speaker/Bluetooth audio, travel-loop ducking during speech, Stop/Mute,
on-device recognition and offline saved-route behavior. The user previously
reported offline local navigation, Repeat and Stop working, but the latest
changes do not constitute a new physical retest.

Do not claim accurate real-world guidance from synthetic tests, bypass uncertain
positioning, substitute GPS for unaligned indoor coordinates, expose credentials,
or redesign unrelated UI. No permanent OpenAI/server credential belongs in the app.
