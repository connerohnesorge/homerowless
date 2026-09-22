// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "homerowless",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "App", targets: ["App"]),
        .executable(name: "axprobe", targets: ["axprobe"]),
    ],
    targets: [
        .target(name: "Geometry"),
        .target(name: "AXCore", dependencies: ["Geometry"]),
        .target(name: "Discovery", dependencies: ["AXCore", "Geometry"]),
        .target(name: "Routing", dependencies: ["Discovery", "Geometry"]),
        .target(name: "Hints", dependencies: ["Geometry"]),
        .target(name: "Overlay", dependencies: ["Geometry", "Hints"]),
        .target(name: "Input", dependencies: ["Geometry", "AXCore"]),
        .target(name: "Modes", dependencies: ["Input", "Overlay", "Hints", "Discovery", "Routing", "AXCore", "Geometry"]),
        .executableTarget(name: "App", dependencies: ["Modes", "Input", "Overlay", "Hints", "Discovery", "Routing", "AXCore", "Geometry"]),
        .executableTarget(name: "axprobe", dependencies: ["AXCore", "Geometry", "Discovery"]),
        .testTarget(name: "GeometryTests", dependencies: ["Geometry"]),
        .testTarget(name: "HintsTests", dependencies: ["Hints"]),
        .testTarget(name: "ClassifierTests", dependencies: ["Discovery"]),
        .testTarget(name: "SourceQualityTests", dependencies: ["Routing"]),
        .testTarget(name: "ModeMachineTests", dependencies: ["Modes"]),
    ],
    swiftLanguageModes: [.v6]
)
