import SwiftUI
import IndoorbilityCore

struct ReportView: View {
    @ObservedObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    let evidence: SignEvidence?
    @State private var target: String
    init(store: AppStore, evidence: SignEvidence? = nil) {
        self.store = store; self.evidence = evidence
        _target = State(initialValue: evidence.map { BarrierInterpreter.interpret($0.text, in: store.building).targetEdgeID ?? "" } ?? (store.building.edges.contains(where: { $0.id == "lift_a" }) ? "lift_a" : store.building.edges.first?.id ?? ""))
    }
    @State private var acknowledged = false
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Report a closure").font(.headline)
                    Text("Choose the closed lift or path. It will be excluded from your routes.")
                        .foregroundStyle(.secondary)
                    if !store.building.buildingID.hasPrefix("scan-") { DemoBadge() }
                    if let evidence {
                        Text(evidence.text).font(.subheadline.monospaced())
                        Text(BarrierInterpreter.interpret(evidence.text, in: store.building).message)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Section("Affected connection") {
                    Picker("Connection", selection: $target) {
                        Text("Choose connection").tag("")
                        ForEach(store.building.edges.sorted { lhs, rhs in
                            if (lhs.kind == .elevator) != (rhs.kind == .elevator) { return lhs.kind == .elevator }
                            return lhs.id < rhs.id
                        }) { edge in Text(store.building.edgeLabel(edge.id)).tag(edge.id) }
                    }.accessibilityIdentifier("reportTarget")
                    LabeledContent("Status", value: "Unavailable")
                    LabeledContent("Source", value: evidence == nil ? "Manual report" : evidence?.source == .demo ? "Sample image OCR" : "Camera / photo OCR")
                    Button { acknowledged.toggle() } label: {
                        HStack(alignment: .center, spacing: 12) {
                            Image(systemName: acknowledged ? "checkmark.square.fill" : "square")
                                .font(.title2).foregroundStyle(Color.indoorTeal)
                            Text("I confirm this connection is unavailable").foregroundStyle(.primary)
                        }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .accessibilityValue(acknowledged ? "Confirmed" : "Not confirmed")
                        .accessibilityIdentifier("acknowledgeReport")
                }
                Section {
                    PrimaryButton(title: "Confirm report", systemImage: "checkmark.shield") {
                        let report = BarrierReport(targetEdgeID: target, source: evidence?.source ?? .manual, recognizedText: evidence?.text)
                        store.change { try $0.confirmReport(report) }
                        if store.session.saved.reports.contains(where: { $0.id == report.id }) { dismiss() }
                    }.disabled(!acknowledged || target.isEmpty).accessibilityIdentifier("submitReport")
                    Text("You can remove a closure when the connection reopens.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                if let error = store.errorMessage { Text(error).foregroundStyle(.red) }
                if !store.activeReports.isEmpty {
                    Section("Your active reports") {
                        ForEach(store.activeReports) { report in
                            VStack(alignment: .leading, spacing: 8) {
                                Text(store.building.edgeLabel(report.targetEdgeID)).font(.headline)
                                Text("Confirmed locally · \(report.createdAt.formatted(date: .abbreviated, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                                if report.needsReview() {
                                    Text("Review due: this local closure is over a day old. It stays blocked until explicitly resolved.").font(.caption)
                                    Button("I checked — still closed") { store.change { $0.reviewReport(report.id) } }
                                }
                                Button("Resolve this report") { store.change { try $0.resolveReport(report.id) } }
                                    .frame(minHeight: 44)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Report a barrier").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
            .onChange(of: target) { _, _ in acknowledged = false }
            .alert("Report not saved", isPresented: Binding(get: { store.errorMessage != nil }, set: { if !$0 { store.errorMessage = nil } })) {
                Button("OK", role: .cancel) { store.errorMessage = nil }
            } message: { Text(store.errorMessage ?? "") }
        }
    }
}
