# Indoorbility development handoff — November 14, 2026

Start here when continuing this repository in Claude. The README and older build
reports contain historical milestones; inspect current code before relying on
their feature or verification claims.

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
  `https://indoorbility-production.up.railway.app`. This handoff does not verify
  its current deployed revision or perform a new production deployment.
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

## Verification at this checkpoint

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
