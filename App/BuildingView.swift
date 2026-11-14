import SwiftUI
import Charts
import IndoorbilityCore

struct BuildingView: View {
    @ObservedObject var store: AppStore
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack { Text("Learning Center").font(.title2.weight(.semibold)); Spacer(); DemoBadge() }
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    metric("Floors", value: store.building.floors.count, symbol: "square.3.layers.3d")
                    metric("Checkpoints", value: store.building.nodes.count, symbol: "mappin.and.ellipse")
                    metric("Connections", value: store.building.edges.count, symbol: "point.topleft.down.to.point.bottomright.curvepath")
                    metric("Active reports", value: store.activeReports.count, symbol: "flag")
                }
                Panel {
                    Text("Lift availability").font(.headline)
                    ForEach(store.building.edges.filter { $0.kind == .elevator }) { edge in
                        let unavailable = store.blockedEdges.contains(edge.id)
                        HStack(alignment: .top) {
                            Image(systemName: unavailable ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(unavailable ? Color.orange : .indoorTeal)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(store.building.edgeLabel(edge.id)).font(.headline)
                                Text(unavailable ? "Excluded from routes" : "Available in demo map")
                                    .font(.subheadline).foregroundStyle(.secondary)
                            }
                        }.accessibilityElement(children: .combine)
                    }
                }
                Panel {
                    Text("Your current route").font(.headline)
                    if let route = store.session.route {
                        LabeledContent("Connection", value: store.connector)
                        LabeledContent("Demo cost units", value: route.cost.formatted())
                        if let delta = store.session.routeDelta, delta != 0 {
                            Chart {
                                BarMark(x: .value("Route", "Before"), y: .value("Demo cost", route.cost - delta))
                                    .foregroundStyle(Color.secondary.opacity(0.5))
                                BarMark(x: .value("Route", "Now"), y: .value("Demo cost", route.cost))
                                    .foregroundStyle(Color.indoorTeal)
                            }.frame(height: 150).accessibilityHidden(true)
                            Text("Before: \((route.cost - delta).formatted()). Now: \(route.cost.formatted()) demo cost units, from the same starting point.")
                                .font(.subheadline)
                        }
                    } else {
                        Text(store.session.destinationID == nil ? "Plan a route to see its details." : store.session.needsPosition ? "Confirm your starting point to calculate a route." : "No route meets the current preferences and closures.")
                            .foregroundStyle(.secondary)
                    }
                    Text("Costs are synthetic demo values, not metres or minutes.").font(.caption).foregroundStyle(.secondary)
                }
                Panel {
                    Text("Report history").font(.headline)
                    if store.session.saved.reports.isEmpty {
                        Label("No reports yet", systemImage: "checkmark.bubble").foregroundStyle(.secondary)
                    }
                    ForEach(store.session.saved.reports.reversed()) { report in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(store.building.edgeLabel(report.targetEdgeID)).font(.headline)
                            Text("\(report.lifecycle.rawValue.capitalized) · \(report.source.rawValue.capitalized) · This device")
                                .font(.subheadline).foregroundStyle(.secondary)
                            Text(report.createdAt.formatted(date: .abbreviated, time: .shortened))
                                .font(.caption).foregroundStyle(.secondary)
                            if let text = report.recognizedText {
                                DisclosureGroup("Recognized sign text") { Text(text).font(.caption.monospaced()) }
                            }
                            if let date = report.resolvedAt {
                                Text("Resolved \(date.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            if report.isActive {
                                Button("Resolve this report") { store.change { try $0.resolveReport(report.id) } }
                                    .frame(minHeight: 44)
                            }
                        }
                        Divider()
                    }
                }
                Panel {
                    Text("About this map").font(.headline)
                    LabeledContent("Map source", value: "Bundled fictional building")
                    LabeledContent("Verification", value: "Demo verification")
                    LabeledContent("Last site inspection", value: "Not recorded")
                    Text("No real building has been surveyed. Reports stay on this device. The diagram does not establish real-world clearance or accessibility.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }.padding(20)
        }.background(Color.indoorBackground)
            .navigationTitle("Building").navigationBarTitleDisplayMode(.inline)
    }
    private func metric(_ title: String, value: Int, symbol: String) -> some View {
        Panel {
            Image(systemName: symbol).foregroundStyle(Color.indoorTeal)
            Text(value.formatted()).font(.title2.weight(.semibold))
            Text(title).font(.caption).foregroundStyle(.secondary)
        }
    }

}
