import SwiftUI
import UniformTypeIdentifiers
import CryptoKit
import ARKit
import IndoorbilityCore

struct MapParcel: Codable {
    var version = 1
    var name: String
    var scans: [Record]
    var network: BuildingNetwork?
    var meshCellMetres: Float? = nil
    struct Record: Codable {
        var id: UUID
        var files: [String: Data]
        var hashes: [String: String]
    }
    static let allowed: Set<String> = ["scan.json", "hallway.json", "world.arworldmap", "mesh.json", "room-metadata.json"]
    static let limit = 80 * 1024 * 1024
    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    func validate() throws {
        guard version == 1, !name.isEmpty, name.count <= 200, (1...32).contains(scans.count), Set(scans.map(\.id)).count == scans.count else { throw MapError.invalid("Invalid map package.") }
        var total = 0
        for scan in scans {
            guard Set(scan.files.keys).isSubset(of: Self.allowed), Set(scan.files.keys) == Set(scan.hashes.keys),
                  let data = scan.files["scan.json"], scan.files["world.arworldmap"] != nil, scan.files["mesh.json"] != nil else { throw MapError.invalid("Map package is incomplete.") }
            for (key,bytes) in scan.files {
                total += bytes.count
                guard total <= Self.limit, Self.digest(bytes) == scan.hashes[key] else { throw MapError.invalid("Map size or checksum failed.") }
            }
            let draft = try JSONDecoder().decode(ScanDraft.self, from: data); try draft.validate()
            guard draft.id == scan.id, draft.samples.count <= 20000, draft.landmarks.count <= 500 else { throw MapError.invalid("Invalid scan identity or size.") }
            if let bytes = scan.files["hallway.json"] { try JSONDecoder().decode(HallwayRoute.self, from: bytes).validate(for: draft) }
            let meshes = try JSONDecoder().decode([MeshRecord].self, from: scan.files["mesh.json"]!)
            guard meshes.reduce(0, { $0 + $1.vertices.count }) <= 500000, meshes.reduce(0, { $0 + $1.triangles.count }) <= 3000000 else { throw MapError.invalid("Mesh is too large.") }
            for mesh in meshes {
                guard mesh.vertices.allSatisfy(\.isFinite), mesh.triangles.count % 3 == 0, mesh.triangles.count <= 3000000,
                      mesh.triangles.allSatisfy({ Int($0) < mesh.vertices.count }) else { throw MapError.invalid("Invalid mesh geometry.") }
            }
        }
        if let network {
            guard network.segments.count <= 32, network.links.count <= 64 else { throw MapError.invalid("Too many building connections.") }
            let routes = try scans.compactMap { record -> HallwayRoute? in
                guard let bytes = record.files["hallway.json"] else { return nil }
                return try JSONDecoder().decode(HallwayRoute.self, from: bytes)
            }
            guard Set(routes.map(\.id)).count == routes.count, !network.name.isEmpty, !network.floor.isEmpty,
                  let first = network.segments.first, first.alignment == .identity else { throw MapError.invalid("Invalid building origin.") }
            let lookup = Dictionary(uniqueKeysWithValues: routes.map { ($0.id, $0) })
            for segment in network.segments { _ = try network.path(from: first.routeID, to: segment.routeID, routes: lookup) }
            guard network.segments.count <= 32, network.links.count <= 64,
                  Set(network.segments.map(\.scanID)).isSubset(of: Set(scans.map(\.id))) else { throw MapError.invalid("Building connections reference missing scans.") }
        }
    }
}

@MainActor enum MapExchange {
    nonisolated static func export(_ drafts: [ScanDraft], root: URL, network: BuildingNetwork? = nil) throws -> URL {
        let records = try drafts.map { draft in
            guard !FileManager.default.fileExists(atPath: root.appending(path: draft.id.uuidString).appending(path: "source-routes.json").path) else { throw MapError.invalid("Share the building collection with its original recordings instead of a combined route.") }
            var files = [String:Data]()
            for name in MapParcel.allowed {
                let url = root.appending(path: draft.id.uuidString).appending(path: name)
                if FileManager.default.fileExists(atPath: url.path) {
                    let bytes = try Data(contentsOf: url)
                    if name == "mesh.json" {
                        let meshes = try JSONDecoder().decode([MeshRecord].self, from: bytes)
                        files[name] = try JSONEncoder().encode(meshes.map { mesh in
                            let reduced = try MeshReduction.reduce(vertices: mesh.vertices, triangles: mesh.triangles)
                            return MeshRecord(vertices: reduced.vertices, triangles: reduced.triangles)
                        })
                    } else { files[name] = bytes }
                }
            }
            return MapParcel.Record(id: draft.id, files: files, hashes: files.mapValues(MapParcel.digest))
        }
        let parcel = MapParcel(name: network?.name ?? drafts.first?.name ?? "Building", scans: records, network: network, meshCellMetres: 0.04)
        try parcel.validate()
        let bytes = try JSONEncoder().encode(parcel)
        guard bytes.count <= MapParcel.limit else { throw MapError.invalid("Export exceeds 80 MB. Use shorter scan sections.") }
        let url = FileManager.default.temporaryDirectory.appending(path: "Indoorbility-\(UUID()).indoormap")
        try bytes.write(to: url, options: .atomic); return url
    }
    nonisolated static func readParcel(_ url: URL) throws -> MapParcel {
        let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= MapParcel.limit else { throw MapError.invalid("Map package exceeds 80 MB.") }
        let parcel = try JSONDecoder().decode(MapParcel.self, from: Data(contentsOf: url)); try parcel.validate()
        for record in parcel.scans {
            guard let bytes = record.files["world.arworldmap"], try NSKeyedUnarchiver.unarchivedObject(ofClass: ARWorldMap.self, from: bytes) != nil else { throw MapError.invalid("Invalid spatial archive.") }
        }
        return parcel
    }
    static func importFile(_ url: URL, library: ScanLibrary) async throws {
        let parcel = try await Task.detached(priority: .utility) { try readParcel(url) }.value
        // No overwrite: identical imports can be reused; conflicting UUIDs are rejected.
        for record in parcel.scans where library.scans.contains(where: { $0.id == record.id }) {
            for (name,bytes) in record.files {
                guard (try? Data(contentsOf: library.directory(record.id).appending(path: name))) == bytes else { throw MapError.invalid("This recording already exists with different data. Import on the other phone; your original map was preserved.") }
            }
        }
        var installed: [URL] = []
        do {
            for record in parcel.scans where !library.scans.contains(where: { $0.id == record.id }) {
                let staging = library.root.appending(path: ".import-\(UUID())")
                try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
                defer { try? FileManager.default.removeItem(at: staging) }
                for (name,bytes) in record.files { try bytes.write(to: staging.appending(path: name), options: .atomic) }
                // A sender's assertion is not local field validation.
                try Data("{}".utf8).write(to: staging.appending(path: "volunteer-draft.json"))
                let target = library.directory(record.id)
                try FileManager.default.moveItem(at: staging, to: target); installed.append(target)
            }
            if let network = parcel.network { try BuildingLibrary.saveImported(network) }
        } catch { for url in installed { try? FileManager.default.removeItem(at: url) }; throw error }
        library.reload()
    }
    static func cloud(_ method: String, code: String? = nil, file: URL? = nil) async throws -> Data {
        guard let base = AgentConfiguration.url else { throw MapError.invalid("Configure your backend in AI connection first.") }
        let token = try await AgentConfiguration.accessToken()
        if let code, code.count != 32 || !code.allSatisfy({ $0.isHexDigit }) { throw MapError.invalid("Use the 32-character sharing code.") }
        var request = URLRequest(url: base.appending(path: "maps" + (code.map { "/" + $0 } ?? "")))
        request.httpMethod = method; request.timeoutInterval = 120
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let file {
            request.httpBody = try await Task.detached(priority: .utility) {
                guard (try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= MapParcel.limit else { throw MapError.invalid("Upload exceeds size limit.") }
                return try Data(contentsOf: file)
            }.value
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let data: Data
        let response: URLResponse
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 180
        let session = URLSession(configuration: configuration, delegate: MapDownloadLimit(), delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        if method == "GET" {
            let (url, received) = try await session.download(for: request)
            defer { try? FileManager.default.removeItem(at: url) }
            guard (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) <= MapParcel.limit else { throw MapError.invalid("Download exceeds size limit.") }
            data = try await Task.detached(priority: .utility) { try Data(contentsOf: url) }.value; response = received
        } else {
            (data, response) = try await session.data(for: request)
        }
        guard let response = response as? HTTPURLResponse, response.statusCode == 200 else { throw MapError.invalid("Map transfer failed. Check your token, sharing code and backend storage.") }
        guard data.count <= MapParcel.limit else { throw MapError.invalid("Download exceeds size limit.") }
        if method == "GET" {
            let digest = await Task.detached(priority: .utility) { MapParcel.digest(data) }.value
            guard response.value(forHTTPHeaderField: "X-Content-SHA256") == digest else { throw MapError.invalid("Download checksum failed.") }
        }
        return data
    }
}

struct MapTransferView: View {
    @ObservedObject var library: ScanLibrary
    var drafts: [ScanDraft]
    var network: BuildingNetwork? = nil
    @State private var file: URL?
    @State private var importing = false
    @State private var code = ""
    @State private var message = ""
    @State private var busy = false
    var body: some View {
        Form {
            Section("Offline sharing") {
                if !drafts.isEmpty {
                    Button("Prepare map file") {
                        busy = true
                        let root = library.root, selected = drafts, collection = network
                        Task {
                            defer { busy = false }
                            do { file = try await Task.detached(priority: .utility) { try MapExchange.export(selected, root: root, network: collection) }.value }
                            catch { message = error.localizedDescription }
                        }
                    }
                    if let file { ShareLink("Share with AirDrop or Files", item: file) }
                }
                Button("Import map file") { importing = true }
            }
            Section("Backend sharing") {
                Text("Only upload maps you have permission to share. Anyone with this code and backend access can download this copy.").font(.footnote)
                if let file { Button("Upload this map") { transfer(file: file) } }
                TextField("Sharing code", text: $code).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("Download and import") { transfer(file: nil) }.disabled(code.isEmpty)
                Button("Revoke this upload", role: .destructive) {
                    busy = true
                    Task {
                        defer { busy = false }
                        do { _ = try await MapExchange.cloud("DELETE", code: code.trimmingCharacters(in: .whitespacesAndNewlines)); message = "Upload revoked. Previously downloaded copies remain on their phones." }
                        catch { message = error.localizedDescription }
                    }
                }.disabled(code.isEmpty)
            }
            if busy { ProgressView("Transferring…") }
            if !message.isEmpty { Text(message).textSelection(.enabled) }
            Text("Imported routes need local review before guidance. No automatic uploads.").font(.footnote)
        }.navigationTitle("Share maps").disabled(busy)
            .fileImporter(isPresented: $importing, allowedContentTypes: [.data, .json]) { result in
                busy = true
                Task {
                    defer { busy = false }
                    do { try await MapExchange.importFile(result.get(), library: library); message = "Imported. Review the recording before navigating." }
                    catch { message = error.localizedDescription }
                }
            }
    }
    private func transfer(file: URL?) {
        busy = true
        Task {
            defer { busy = false }
            do {
                let data = try await MapExchange.cloud(file == nil ? "GET" : "POST", code: file == nil ? code.trimmingCharacters(in: .whitespacesAndNewlines) : nil, file: file)
                if file != nil {
                    let result = try JSONDecoder().decode([String:String].self, from: data)
                    code = result["code"] ?? ""; message = "Uploaded. Share the code with the other phone."
                } else {
                    let url = FileManager.default.temporaryDirectory.appending(path: "download-\(UUID()).indoormap")
                    defer { try? FileManager.default.removeItem(at: url) }
                    try data.write(to: url); try await MapExchange.importFile(url, library: library)
                    message = "Imported. Review locally before guidance."
                }
            } catch { message = error.localizedDescription }
        }
    }
}

private final class MapDownloadLimit: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > Int64(MapParcel.limit) || totalBytesExpectedToWrite > Int64(MapParcel.limit) { downloadTask.cancel() }
    }
}
