import SwiftUI
import Vision
import VisionKit
import PhotosUI
import AVFoundation
import ImageIO
import IndoorbilityCore

enum SignScanPurpose { case closure, startingPoint }

struct SignEvidence: Identifiable {
    let id = UUID()
    let text: String
    let source: BarrierReport.Source
}

enum SignRecognition {
    static func read(_ data: Data) async throws -> String {
        try await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw MapError.invalid("That image couldn’t be opened. Try a different photo.")
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            let raw = properties?[kCGImagePropertyOrientation] as? UInt32 ?? 1
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            try VNImageRequestHandler(cgImage: image, orientation: CGImagePropertyOrientation(rawValue: raw) ?? .up).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
        }.value
    }
    @MainActor static func sampleImage(startingPoint: Bool = false) -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 1000, height: 650)).image { context in
            UIColor.white.setFill(); context.fill(CGRect(x: 0, y: 0, width: 1000, height: 650))
            let style = NSMutableParagraphStyle(); style.alignment = .center
            ((startingPoint ? "ENTRANCE" : "LIFT A") as NSString).draw(in: CGRect(x: 60, y: 110, width: 880, height: 130), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 100), .foregroundColor: UIColor.black, .paragraphStyle: style])
            ((startingPoint ? "LEARNING CENTER" : "OUT OF SERVICE") as NSString).draw(in: CGRect(x: 30, y: 290, width: 940, height: 150), withAttributes: [.font: UIFont.boldSystemFont(ofSize: 88), .foregroundColor: UIColor.black, .paragraphStyle: style])
        }
    }
}

struct LiveSignCamera: UIViewControllerRepresentable {
    @Binding var text: String
    @Binding var error: String?
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(recognizedDataTypes: [.text()], qualityLevel: .accurate,
            recognizesMultipleItems: true, isHighFrameRateTrackingEnabled: false, isPinchToZoomEnabled: true,
            isGuidanceEnabled: true, isHighlightingEnabled: true)
        controller.delegate = context.coordinator
        context.coordinator.task = Task { @MainActor [weak controller] in
            guard let controller else { return }
            do {
                try controller.startScanning()
                for await items in controller.recognizedItems {
                    if Task.isCancelled { break }
                    text = items.compactMap { if case .text(let item) = $0 { return item.transcript }; return nil }.joined(separator: "\n")
                }
            } catch { self.error = "Camera scanning stopped: \(error.localizedDescription)" }
        }
        return controller
    }
    func updateUIViewController(_ controller: DataScannerViewController, context: Context) { context.coordinator.parent = self }
    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        coordinator.task?.cancel(); controller.stopScanning()
    }
    @MainActor final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var parent: LiveSignCamera
        var task: Task<Void, Never>?
        init(_ parent: LiveSignCamera) { self.parent = parent }
        func dataScanner(_ dataScanner: DataScannerViewController, becameUnavailableWithError error: DataScannerViewController.ScanningUnavailable) {
            dataScanner.stopScanning(); task?.cancel()
            parent.error = "Camera scanning is unavailable. Choose a photo or try again."
        }
    }
}

struct SignScanView: View {
    @ObservedObject var store: AppStore
    var purpose: SignScanPurpose = .closure
    var confirmStartingPoint: ((String) -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @State private var cameraActive = false
    @State private var recognizedText = ""
    @State private var error: String?
    @State private var busy = false
    @State private var photo: PhotosPickerItem?
    @State private var preview: UIImage?
    @State private var source: BarrierReport.Source = .photo
    @State private var evidence: SignEvidence?
    @State private var accessDenied = false
    private var suggestion: BarrierSuggestion { BarrierInterpreter.interpret(recognizedText, in: store.building) }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text(purpose == .startingPoint ? "Point at a room number or entrance sign. Confirm the matching place below." : "Point at a closure sign. Check the text before adding a report.").font(.subheadline).foregroundStyle(.secondary)
                    ZStack {
                        RoundedRectangle(cornerRadius: 16).fill(Color.black)
                        if cameraActive {
                            LiveSignCamera(text: $recognizedText, error: $error).clipShape(RoundedRectangle(cornerRadius: 16))
                        } else if let preview {
                            Image(uiImage: preview).resizable().scaledToFit().padding(24)
                        } else {
                            VStack(spacing: 18) {
                                Image(systemName: "viewfinder").font(.system(size: 64, weight: .ultraLight)).foregroundStyle(Color.indoorLime)
                                Text(purpose == .startingPoint ? "Scan your starting point" : "Scan a closure sign").font(.subheadline).foregroundStyle(.white)
                                Text(DataScannerViewController.isSupported ? "Tap Open camera to start" : "Use a photo or sample on this device")
                                    .font(.caption).foregroundStyle(.white.opacity(0.65))
                            }.padding()
                        }
                        if busy { ProgressView("Reading sign…").padding(18).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14)) }
                    }.frame(height: 260)
                    HStack(spacing: 12) {
                        Button { Task { await startCamera() } } label: {
                            Label(cameraActive ? "Restart camera" : "Open camera", systemImage: "camera").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.bordered).disabled(!DataScannerViewController.isSupported || busy)
                            .accessibilityIdentifier("openSignCamera")
                        PhotosPicker(selection: $photo, matching: .images) {
                            Label("Choose photo", systemImage: "photo").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 48)
                        }.buttonStyle(.bordered).disabled(busy).accessibilityIdentifier("chooseSignPhoto")
                    }
                    if let error {
                        Label(error, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.orange)
                        if accessDenied {
                            Button("Open camera settings") {
                                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                            }.frame(minHeight: 44)
                        }
                    }
                    if !recognizedText.isEmpty {
                        Panel {
                            HStack { Eyebrow(text: "Recognized text"); Spacer(); SmallTag(text: source == .demo ? "Sample image" : "On device", symbol: "text.viewfinder") }
                            Text(recognizedText).font(.title3.weight(.medium)).textSelection(.enabled).accessibilityIdentifier("recognizedSignText")
                            if purpose == .startingPoint {
                                let matches = SignLocationMatcher.candidates(in: recognizedText, building: store.building)
                                if matches.isEmpty {
                                    Text("No matching place in this demo building. Try another sign or select your start on the map.").font(.subheadline).foregroundStyle(.secondary)
                                } else {
                                    Text("Matches in the demo building").font(.caption).foregroundStyle(.secondary)
                                    ForEach(matches) { node in
                                        Button {
                                            confirmStartingPoint?(node.id)
                                            dismiss()
                                        } label: {
                                            Label("Use \(node.label) as start", systemImage: "location.circle")
                                                .frame(maxWidth: .infinity, minHeight: 48)
                                        }.buttonStyle(.borderedProminent).accessibilityIdentifier("confirmScannedStart_\(node.id)")
                                    }
                                }
                            } else {
                            Text(suggestion.message).font(.subheadline).foregroundStyle(.secondary)
                            PrimaryButton(title: "Review barrier report", systemImage: "arrow.right") {
                                cameraActive = false
                                evidence = SignEvidence(text: recognizedText, source: source)
                            }.accessibilityIdentifier("reviewScannedReport")
                            }
                        }
                    }
                    Button {
                        let image = SignRecognition.sampleImage(startingPoint: purpose == .startingPoint)
                        if let data = image.pngData() { Task { await read(data, source: .demo) } }
                    } label: {
                        HStack {
                            IconTile(symbol: "text.below.photo")
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Try a sample sign").font(.subheadline.weight(.semibold))
                                Text("Example image for this demo").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(); Image(systemName: "arrow.up.right").font(.caption)
                        }.padding(14).background(Color.indoorCard, in: RoundedRectangle(cornerRadius: 20))
                    }.buttonStyle(.plain).disabled(busy).accessibilityIdentifier("sampleSign")
                    Text(purpose == .startingPoint ? "This demo map is fictional. Scanning a label does not establish your real-world position." : "Photos stay on this device. Confirmed reports save the recognized text.").font(.caption).foregroundStyle(.secondary)
                }.padding(20)
            }.background(Color.indoorBackground).navigationTitle(purpose == .startingPoint ? "Find starting point" : "Read a sign").navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
                .sheet(item: $evidence) { ReportView(store: store, evidence: $0) }
                .task {
                    if DataScannerViewController.isSupported { await startCamera() }
                }
                .onChange(of: photo) { _, item in
                    guard let item else { return }
                    Task {
                        do {
                            guard let data = try await item.loadTransferable(type: Data.self) else { throw MapError.invalid("The photo could not be loaded.") }
                            await read(data, source: .photo)
                        } catch { self.error = error.localizedDescription }
                    }
                }
                .onChange(of: phase) { _, value in if value != .active { cameraActive = false } }
                .onChange(of: error) { _, value in if value != nil { cameraActive = false } }
                .onDisappear { cameraActive = false }
        }
    }
    private func startCamera() async {
        error = nil; accessDenied = false; preview = nil; recognizedText = ""; cameraActive = false
        let authorized = await AVCaptureDevice.requestAccess(for: .video)
        guard authorized else { accessDenied = true; error = "Camera access is off. You can still choose a photo."; return }
        guard DataScannerViewController.isSupported && DataScannerViewController.isAvailable else {
            error = "Live text scanning is not available on this device. Choose a photo instead."; return
        }
        source = .photo; cameraActive = true
    }
    private func read(_ data: Data, source: BarrierReport.Source) async {
        cameraActive = false; busy = true; error = nil; recognizedText = ""; self.source = source
        preview = UIImage(data: data)
        defer { busy = false }
        do {
            recognizedText = try await SignRecognition.read(data)
            if recognizedText.isEmpty { error = "No readable text found. Try a closer, well-lit photo." }
        } catch { self.error = "Couldn’t read this image. \(error.localizedDescription)" }
    }
}
