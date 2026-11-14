> Update November 14, 2026: real OpenAI tool execution is now verified with synthetic pose (Room 106 → Room 105). See REAL_AGENT_VERIFICATION.json and IPHONE_AGENT_TEST.md. Physical ARKit/speech/camera remain unverified. Current backend suite: 11 passing tests. Earlier credential-blocked notes below are historical.

# Agent implementation evidence

## Changed files

- `backend/app.py`: authenticated FastAPI endpoint, OpenAI Agents SDK coordinator, strict schemas, bounded pending-tool loop, safe finals and failure paths.
- `backend/issue_token.py`, `.env.example`, `requirements.lock.txt`, `README.md`: server-only credentials, expiring development provisioning, reproducible dependency versions and setup.
- `backend/test_backend.py`: offline scripted-model tests, including calls into the real Swift routing probe.
- `backend/evaluate_live.py`: explicit real-inference probe; requires an actual credential; not run yet.
- `Sources/IndoorbilityCore/AgentBridge.swift`: typed tool contracts, revision/idempotency ledger, shopping task memory.
- `Sources/IndoorbilityAgentProbe/main.swift`, `Package.swift`: synthetic-position fixture that executes the actual core routing engine.
- `Tests/IndoorbilityCoreTests/AgentBridgeTests.swift`: stale revision/session, replay, unknown tool and task-memory tests.
- `App/NavigationAgent.swift`: cancellable HTTPS client, Keychain token storage, cloud opt-in, grounded result presentation and redacted developer timeline.
- `App/HallwayNavigationView.swift`: actual tool owner, fresh-pose checks, same-session route changes, intent-scoped destination/observation permissions, persistent unknown-location shopping list and no-alternative handling.
- `App/AgentSceneObservation.swift`, `App/SpatialScanning.swift`: requested local OCR/sceneDepth sampling on the existing AR session; no cloud camera stream.
- `App/ShoppingAgentHost.swift`, `App/AssistantView.swift`: adapter to the existing fictional-store state and optimizer; current local Assistant retained.
- `App/AppStore.swift`: speech-generation counter for reroute diagnostics.
- `App/SettingsView.swift`: AI configuration entry.
- `Indoorbility.xcodeproj/project.pbxproj`: new Swift source membership; signing preserved.
- `.gitignore`: local environment, virtualenv and Python cache exclusions.

## Evidence boundaries

The backend-to-Swift test uses scripted SDK model responses and synthetic positions. It verifies actual resolution, route calculation and route mutation with preserved position, then passes actual Swift results back into SDK continuation. It is **not** a real model invocation, an ARKit test or a production metric for tool-selection accuracy.

Real model testing remains blocked by the intentionally absent OpenAI credential. No real-model run IDs or model accuracy rates exist yet. Configure the key and run `backend/evaluate_live.py`, then perform the physical phone test in the backend README. The live phone timeline reports actual call status/revision, ARSession object preservation, position preservation and speech generation when a route changes.

The current real map is one reviewed hallway. A closure can correctly produce no available route; it cannot demonstrate an alternative corridor that has never been mapped. The existing campus demonstration's alternate-lift graph and fictional shopping graph remain explicitly simulated. No retailer inventory or aisle API was added. No speculative object descriptions are generated: the camera tool reports measured central surface depth, OCR text and unknown semantic identity separately.

The backend is a single-worker development service with expiring in-memory runs and manual one-hour token provisioning. Existing local navigation data and shopping task state persist on-device. Production identity provisioning, distributed rate limits, durable server jobs, deployment and a demonstration video remain outstanding.

## Executed validation (2026-11-14)

- `swift test`: **59 tests passed**, `/tmp/indoorbility-agent-core-final.log`.
- `python -m unittest -v` in backend: **10 tests passed**, `/tmp/indoorbility-agent-backend-final.log`. Includes scripted SDK → actual Swift routing → SDK-result round trip, preserving the synthetic 4 m position and ending 2 m from Room 105.
- Existing UI regression suite: **10 passed**, `/tmp/indoorbility-agent-ui.xcresult`.
- New AI-connection and shopping-agent fallback UI tests: **2 passed on rerun**, `/tmp/indoorbility-agent-extra-final-ui.xcresult`. First run's AI-connection test tapped a row under the navigation bar; the test scroll helper was fixed based on the accessibility snapshot. Shopping passed both runs.
- Simulator build: passed; final app also compiled as part of the new UI test run.
- Unsigned iPhone build: **passed**, `/tmp/indoorbility-agent-device-final.log`.
- Actual loopback Uvicorn process: `/health` returned 200 with `modelConfigured: false`; authenticated `/agent/turn` returned 503 without a model key, as intended. Process stopped after the check.
- Xcode emitted a simulator diagnostic-collection `simctl` path warning after successful tests; test suites themselves passed.
- Physical device execution: **not tested**. Real model invocation: **not run; key absent**. No real-model success rates or run IDs are claimed.

AI connection screen was visually inspected: `docs/screenshots/17-agent-connection.png`.
