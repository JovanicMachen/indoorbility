# Live voice guidance and sensor validation

## Implemented

The existing HallwayFollower remains the source of verified progress, tracking state, closure enforcement and arrival gates. LiveGuidance derives local distance and sharp mapped-turn announcements; GuidanceDelivery suppresses repeated milestone announcements and defers speech while listening or the agent is busy. The live instruction card uses the same message source. Native speech prefers an installed enhanced/premium voice in the current language, with explicit voice and rate choices. Original generated tone cues cover start, turn approach, turn, route change, surface warning and arrival. Independent speech, cue and haptic preferences remain available; mute cancels speech/cues and also gates forced assistant speech. Unmute repeats the current guidance. VoiceOver announcements remain controlled by iOS; this app cannot mute other apps or VoiceOver itself.

The existing agent, destination confirmation, fresh-position route recalculation and ARSession are preserved. Local commands handle mute/unmute and measured remaining distance without needing a model call. No new cloud credentials or frame uploads are introduced.

LiDAR consumes ARFrame timestamp, camera pose, sceneDepth (smoothedSceneDepth fallback), float depthMap and confidenceMap. Central-region sampling runs on the existing bounded worker, with high-confidence-only measurements, fresh normal tracking, three stable observations and an eight-second alert cooldown. A world-height band rejects downward floor samples. Narrow/wide central regions are configurable. A wall is still a surface: alerts intentionally do NOT assert object identity, comprehensive obstacle detection or a clear path. Low objects outside the band may be missed. Diagnostics expose actual confidence counts, central distance, freshness, processing time, skipped work, tracking state, verified route progress and last speech/cue. No device numbers have been invented.

## Try the simulation

1. Run Indoorbility from Xcode on the phone (or simulator for visual/state tests).
2. Settings → AI connection → enable **Show agent timeline**, then open **Test navigation** directly below it. The same developer entry is also available in Settings.
3. Tap Start Test. The production follower receives synthetic stable entrance poses and the production speech/cue coordinators receive “Continue straight for 100 meters.”
4. Tap Advance position eight times to reach the 20-meter left-turn approach. Continue one-meter advances for the turn, then the right turn and room.
5. Exercise simulated tracking loss, simulated landmark recovery, surface event, and destination change buttons. Invalid route-change/recovery requests report errors. These buttons are deterministic test events, not model invocations.
6. Toggle Mute all app sound. Instructions continue visibly. Turn mute off and use Repeat instruction. Replay individual cues; listen for clarity on the physical speaker/headphones.
7. At the room, advance again to supply dwell frames, then confirm the simulated room label. Arrival uses the actual follower gate.

The test is intentionally separate from saved maps. Its usesLiDAR/world-map metadata is synthetic fixture input, NOT sensor evidence. No fixture is saved to the real map library. Real model rerouting is tested only in live mapped navigation via the existing agent timeline, not by pretending the simulation invokes OpenAI.

## Physical hallway procedure (still required)

Xcode reported the physical iPhone unavailable during this implementation. A simulator cannot provide LiDAR evidence.

1. Connect/unlock the LiDAR iPhone, select it in Xcode and Run. Enable measured surface alerts in Accessibility. Enable developer diagnostics as above.
2. Use Settings → Remember a route. Capture one continuous hallway at a consistent phone height, mark the actual entrance and rooms while physically at them, review the same-floor path, and enter the floor label from signage. Room numbers alone are NOT floor evidence. There is no automatic building schematic source configured by this change.
3. Start a saved room route. Relocalize and confirm the known entrance. Open More → Sensor diagnostics: verify depth size is nonzero, frame age stays fresh, confidence counts change, and route alignment is valid. Record processing latency and skipped frames while stationary and walking normally. The diagnostic panel itself does not certify acceptable accuracy.
4. Measure independent floor distances with a tape at several checkpoints. Compare displayed remaining distance and turn timing. Record errors; do not enable independent blind navigation based on a visual demo.
5. In a controlled space with a sighted helper, test a stationary surface, side wall, floor-facing camera, low object, glass, moving person, poor light and occlusion. Record both missed and false warnings. The system warns about central surfaces, not classified obstacles; it may miss hazards and does not replace a cane or guide dog.
6. Say “Actually Room 105 instead” from a verified position on the saved route and confirm. Verify actual tool results in the agent timeline, unchanged AR session identity, cancelled old speech and revised guidance. Try an unknown room, a closed route and tracking loss; none may produce guessed guidance.
7. Test mute/unmute, microphone permission denial, headphones, music, VoiceOver, interruptions and background/resume. Confirm the live camera survives assistant interaction. Audio session coexistence requires device listening tests.
8. At the room, verify arrival only follows fresh tracking, dwell and sign/explicit label confirmation. Test a nearby wrong door.

## Limitations to validate

Turn extraction announces substantial sharp bends in the reviewed trace. Curved or noisy traces may retain general hallway guidance; this is not a semantic floorplan turn detector. Depth is not a full obstacle model. Physical walking accuracy, speaker output, camera/microphone coexistence, and sensor performance remain unverified until the procedure above yields device evidence. No automated result should be interpreted as such evidence.

## Automated validation — 2026-11-14

- All 72 Swift core tests passed.
- All 11 backend offline tests passed; these use scripted model responses, not real OpenAI inference.
- Full UI suite: 15/16 passed initially. The new production guidance simulation/mute case passed.
- The remaining Help unknown-room/shopping case passed on a focused rerun after fixing keyboard/dock crowding and making the test explicitly offline. All 16 distinct UI cases passed across these runs; this was not a clean single-run result.
- Initial developer-entry test attempts also required correcting the switch hit target.
- Final iPhone SDK build uses CODE_SIGNING_ALLOWED=NO; compilation does not install or validate physical sensors.
- Real walking accuracy, audible playback, camera/microphone coexistence and sensor performance: NOT VERIFIED. Xcode listed the physical iPhone unavailable; the user requested device-testing instructions.

Help now hides its large microphone dock while typing, restores it afterward, and dismisses the keyboard on Ask. This fixes a real input-accessibility issue exposed by the regression test.
