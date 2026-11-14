// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Indoorbility",
    platforms: [.iOS(.v17), .macOS(.v13)],
    products: [.library(name: "IndoorbilityCore", targets: ["IndoorbilityCore"]),
               .executable(name: "IndoorbilityAgentProbe", targets: ["IndoorbilityAgentProbe"])],
    targets: [
        .target(name: "IndoorbilityCore", resources: [.process("Resources")]),
        .executableTarget(name: "IndoorbilityAgentProbe", dependencies: ["IndoorbilityCore"]),
        .testTarget(name: "IndoorbilityCoreTests", dependencies: ["IndoorbilityCore"])
    ]
)
