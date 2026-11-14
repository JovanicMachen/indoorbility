# Live hallway voice controls

Implemented first slice: a floating Repeat / microphone / Map dock in real hallway navigation. Microphone starts one permissioned, on-device English utterance; tap again to finish. Partial transcriptions never execute commands. Failed or uncertain recognition leaves the route unchanged. The existing iOS 17-compatible SFSpeechRecognizer is retained. Apple's iOS 26 SpeechAnalyzer/SpeechTranscriber were investigated but are not integrated in this slice.

Supported: repeat directions, where am I, avoid stairs, find another way (explains no alternative mapped), and a uniquely labeled destination on the same reviewed scan trace. No retailer lookup, cloud model or open-ended camera scene descriptions were added.

Destination replacement does not call SpatialSession.start/stop or load another world map. It keeps the rigid alignment and measured position, projects onto a subset of the original reviewed hallway, and supports returning toward a landmark behind the user. Named landmarks must be within 25 cm of an existing trace vertex; routes still pass the existing continuous same-floor validation. Separate scans and unseen branches cannot be joined. Duplicate labels require a unique label; the current route remains active until that is supplied. Closure state and accessibility settings are retained. A changed destination resets arrival dwell and OCR evidence. Alternate destinations do not overwrite the original remembered-route entry.

Narration is stopped before listening and canceled before command responses. Position updates continue while recording. Tracking loss, off-route state or closure interrupts listening and announces the guidance status. The camera/map switch does not pause AR tracking. Backgrounding cancels listening and pauses navigation. Permission prompts may temporarily interrupt ARKit; confidence checks remain authoritative.

## Two-minute physical demonstration

1. Capture one continuous, reviewed hallway with a distinctive entrance, Room 105 marked along the path, and Room 106 at the end. Stand at each mark with the same phone height. Save the reviewed entrance-to-106 route.
2. Launch that route, relocalize and confirm the entrance. Walk partway along the mapped path.
3. Tap the microphone, say “Actually, take me to Room 105 instead”, then tap to finish. The destination changes while camera tracking continues. Repeat directions and switch map/camera.
4. Say “Take me to Room 999”. Verify the unknown-room response and unchanged destination.
5. Cover the camera to induce tracking loss. Verify paused guidance and landmark recovery. At Room 105, verify fresh tracking and label/explicit confirmation before arrival.

This is a device test procedure, not a claim of a successful physical demonstration. Validate microphone permission denial, first-run permission interruptions, recognition assets, audio routing, VoiceOver, headphones, background/resume, reverse travel, closures, duplicate labels, and simultaneous speech/camera/LiDAR on a physical iPhone. Unit tests cannot prove ARSession continuity or speech cancellation on hardware.
