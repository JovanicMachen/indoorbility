# Paste this into Codex

Build the original native iPhone application **CarePath AI** specified in `CODEX_BUILD_BRIEF.md` using `demo_building.json` and `ACCEPTANCE_CHECKLIST.md` in this workspace.

Context: This is a HackPrinceton Fall 2026 software-only accessible indoor navigation MVP. It must transform an unfamiliar building map into adaptive navigation for users with different access needs. The standout demo is a working voice/text route request followed by an elevator outage report captured through the camera, *confirmed* by a person, and an automatic accessible re-route. Deliver a modern, highly usable, polished SwiftUI interface and working deterministic graph algorithm. The app must run with the demo map even without hardware or API keys. A live native LiDAR scanner is a separate device-only feature, with honest capability fallback.

**Start implementation immediately. Do not stop after writing a plan or ask for additional requirements.** Make reasonable choices within the brief and create all Swift files and project configuration. Implement in order: (1) JSON data model + router/tests, (2) route UI + access settings, (3) barrier photo/manual report + replanning, (4) optional agent integration with local fallback, (5) ARKit capture mode. After each phase, build/test and fix issues as possible. Prioritize a demonstrable end-to-end simulator app over breadth. Provide setup commands, current test results and precise limitations.

IMPORTANT ORIGINALITY RULE: The reference `https://github.com/sachin-khanal/uva-gwc-ghh-2026` was examined for high-level architectural context, but it appears to have no declared software license. Do **not** copy its source files, assets, UI, test fixtures, branding, screen design or implementation. Author independent original code using public Apple framework APIs. Preserve any third-party attribution if subsequently licensed code is used; do not try to hide provenance.

Acceptance criteria are in `ACCEPTANCE_CHECKLIST.md`. Build a usable app, not a pitch deck.
