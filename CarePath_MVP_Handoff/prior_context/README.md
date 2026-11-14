# CarePath AI — native iOS hackathon MVP

**Goal:** An original SwiftUI iPhone app for accessible indoor wayfinding that can re-route when a reported barrier closes a path. Built for HackPrinceton Fall 2026.

## Start here

1. Open this folder in your local Codex workspace on a Mac with Xcode.
2. Read `CODEX_BUILD_BRIEF.md` and `ACCEPTANCE_CHECKLIST.md`.
3. Copy `CODEX_START_PROMPT.md` into Codex and ask it to implement the app.
4. Import `demo_building.json` as the bundled demo map fixture.
5. Run in iOS Simulator for routing/UI, then test ARKit/LiDAR mapping on a compatible physical iPhone Pro.

**MVP flow:** A person requests a step-free route from Entrance to Room 204. The app finds a route using Lift A. A user photographs an 'OUT OF SERVICE' sign and confirms that Lift A is unavailable. The app re-routes via Lift B and updates instructions, without ever proposing stairs to a user who selected step-free routes.

**Not included in the MVP:** universal indoor positioning, guaranteed obstacle detection, automatic safety certification, autonomous mobility guidance, cloud synchronization, live building status integrations, or an AI assertion that an unverified route is safe.

## Project identity and reuse

A prior public project, `sachin-khanal/uva-gwc-ghh-2026` (Waypoint), was reviewed **as architectural inspiration only**. As inspected on Nov 14, 2026, the GitHub API reported no declared license and no license file was found in its tree. Public visibility does not grant permission to copy/relicense source code. Implement CarePath from scratch using Apple frameworks and your own UI/assets. Preserve proper attribution and license notices if you later get permission to incorporate third-party code. Do not present another team's work as originally written by this team.

## Target hackathon categories

Main: Healthcare (accessible built-environment access; confirm eligibility with organizers). Special: Amazon Best Practical AI Innovation. Additional: Best Overall consideration. CoStar is **not** claimed unless two of its supplied data layers are genuinely integrated.

## Minimum demonstrable result

- One functional demo building, with two elevators and a staircase.
- A deterministic, tested constrained route planner.
- A native navigation screen showing map + next instruction.
- A barrier report with a photo/OCR-based suggestion and explicit confirmation before affecting routes.
- An AI tool-calling experience for destination requests, with a fully working deterministic fallback.
- An original mapping-mode scaffold that labels and displays LiDAR/ARKit tracking state only when hardware supports it.
