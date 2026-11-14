# Demo data and routing contract

## Existing fixture

Use demo_building.json schema_version 1 from the user-supplied package. There are 11 nodes, 12 undirected edges, two floors, two lift connectors, and one stair connector. The x/y values are diagram coordinates. The distance field is a synthetic routing cost; display “demo cost units,” not metres or minutes. No physical scale or lift wait-time calibration is supplied.

The fixture's verified=true is a simulation flag, not a site inspection. Show “Demo verification” and never claim a real building is accessible. Missing verification dates must display “Not recorded,” not today's date. The proposed demo_barrier_report is an example input and must not be auto-confirmed on load.

## Input validation

Require supported schema version, unique node/edge/floor IDs, valid floor references, finite node coordinates, valid edge endpoints, finite positive edge costs, known edge kinds, and Boolean verified/blocked values. Reject unknown schema versions and malformed graph data with an actionable error. Do not silently route over partial imported data. All v1 edges are bidirectional. Future one-way edges require explicit schema evolution.

For this demo, eligible edges must be verified, unblocked in the base map, not covered by an active confirmed report, and not stairs when avoidStairs=true. Dijkstra uses edge costs directly; diagram distance is not a valid routing heuristic. Unknown start/destination is a separate error. Start equals destination returns an arrived result of zero cost. No eligible path returns noRoute, never a stair fallback.

## Expected results

| Scenario from Entrance to Room 204 | Connector | Cost |
| --- | --- | --- |
| Avoid stairs, no reports | lift_a | 39 |
| Avoid stairs, Lift A confirmed blocked | lift_b | 47 |
| Avoid stairs, both lifts confirmed blocked | none | no route |
| Stairs permitted, no reports | stair_connector | 33 |
| Lift A report proposed or cancelled | lift_a | 39 |

The Lift B alternative costs 8 extra demo units. Expected node path for Lift A is entrance, lobby, junction_1, lift_a_1, lift_a_2, junction_2, room_204. Lift B replaces the two lift_a nodes with lift_b nodes. Never convert these cost differences into walking time.

## Local report record

Persist id, targetEdgeID, proposedStatus, source (manual/photo/demo), recognizedText if retained, createdAt, confirmedAt, resolvedAt, and lifecycle (proposed/confirmed/resolved). Use injected clock/ID generation for tests. Keep photos transient unless the user explicitly saves them. Reports are scoped to this device and this building. Do not upload movement or photos by default.

## Building data view

| Display | Derivation |
| --- | --- |
| Floors and checkpoints | Distinct validated floors and node count |
| Available lifts | Elevator edges remaining after baseline and report filters |
| Active reports | Confirmed, unresolved report count; separate from blocked-edge count |
| Current route | Connector name and summed edge cost, or no route |
| Route change | Difference between last valid route and recomputed route from the same origin |
| Map verification | Demo flag plus recorded date or Not recorded |
| Report history | Source, target, lifecycle, and actual event timestamps |

Do not show a route-cost delta when the origin changed; show “New starting point” instead. Do not represent no route as zero cost. Empty report history says “No reports yet.” Scan statistics, if implemented, remain separate from fixture counts. No invented coverage, accuracy, users helped, or time-saved metrics.
