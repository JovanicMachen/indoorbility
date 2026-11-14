# Reference architecture review

Reviewed repository: [uva-gwc-ghh-2026](https://github.com/sachin-khanal/uva-gwc-ghh-2026/tree/8778e967a080d195d88b2726da57e0e9fab483f9), commit 8778e967a080d195d88b2726da57e0e9fab483f9. Review date: 2026-11-14. This is a targeted source review, not an independent verification of the entire app.

## How the reference is organized

The [README](https://github.com/sachin-khanal/uva-gwc-ghh-2026/blob/8778e967a080d195d88b2726da57e0e9fab483f9/README.md) describes a native iOS app backed by a pure Swift package. The repository tree separates capture, relocalization, navigation, guidance, vision, sync, and UI services. It also contains a web viewer, cloud migrations, versioned map fixtures, and build scripts. The README reports automated test counts but also flags device-dependent behavior as unverified in parts; those counts were not rerun here.

The [map model](https://github.com/sachin-khanal/uva-gwc-ghh-2026/blob/8778e967a080d195d88b2726da57e0e9fab483f9/Package/WaypointCore/Sources/WaypointCore/Model/BuildingMap.swift) stores a versioned graph and optional mesh/keyframe information. It includes migration and merging behavior. CarePath should retain the general separation between graph data and optional capture assets, with a smaller independently written schema.

The [router](https://github.com/sachin-khanal/uva-gwc-ghh-2026/blob/8778e967a080d195d88b2726da57e0e9fab483f9/Package/WaypointCore/Sources/WaypointCore/Routing/Router.swift) implements A* and adds a large stair penalty when stairs are disallowed at that low-level API. That can still produce a stair path when alternatives disappear. This observation concerns that function, not an audited claim about every higher-level screen. CarePath's hard exclusion and no-route state provide the behavior required by our demo.

The [live scan service](https://github.com/sachin-khanal/uva-gwc-ghh-2026/blob/8778e967a080d195d88b2726da57e0e9fab483f9/Waypoint/Services/LiveScanService.swift) bridges a capture controller into observable UI snapshots, including tracking state, counts, pause/resume, and save outcomes. CarePath can use the general service-boundary idea while implementing its own smaller draft scan workflow.

## What to retain and improve

| Architectural idea | CarePath decision |
| --- | --- |
| Pure routing core separate from sensors | Retain this separation in original code |
| Native capture and guidance services | Add incrementally after simulator milestone |
| Labelled map graph | Use user-supplied fictional fixture and explicit provenance |
| Many capture and navigation screens | Focus initial UI on destination, route, and report |
| Route feedback | Use readable checkpoint guidance, speech, and optional haptics |
| Broad cloud and 3D toolset | Defer; expose useful local graph/report data first |
| Simulation support | Keep a persistent Demo building label |

## Originality

No LICENSE or COPYING file appeared in the recursively inspected repository tree at the reviewed commit. No reference code, assets, screenshots, map fixtures, or prose were copied into this package. The user-supplied CarePath material is preserved separately. Similar architecture and Apple framework choices do not require importing the reference implementation. If code reuse is authorized later, review the permission/license and retain required attribution rather than stripping provenance.
