// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "WiFiAnalyzerKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "WiFiModel", targets: ["WiFiModel"]),
        .library(name: "IEParser", targets: ["IEParser"]),
        .library(name: "WdutilBridge", targets: ["WdutilBridge"]),
        .library(name: "OUIResolver", targets: ["OUIResolver"]),
        .library(name: "Telemetry", targets: ["Telemetry"]),
        .library(name: "WiFiCore", targets: ["WiFiCore"]),
    ],
    targets: [
        // Pure value types shared across every module (spec §7 data model).
        .target(name: "WiFiModel"),

        // The crown jewel: a pure-Swift 802.11 Information Element decoder.
        .target(name: "IEParser", dependencies: ["WiFiModel"]),

        // Runs and parses `wdutil info`; the parser is pure and unit-tested.
        .target(name: "WdutilBridge", dependencies: ["WiFiModel"]),

        // Offline OUI -> vendor resolution from a bundled database.
        .target(
            name: "OUIResolver",
            dependencies: ["WiFiModel"],
            resources: [.copy("Resources/oui.csv")]
        ),

        // Time-series ring buffers + CSV/JSON export.
        .target(name: "Telemetry", dependencies: ["WiFiModel"]),

        // CoreWLAN + CoreLocation wrapper. macOS frameworks; runtime needs an app context.
        .target(
            name: "WiFiCore",
            dependencies: ["WiFiModel", "IEParser", "WdutilBridge", "OUIResolver"]
        ),

        .testTarget(name: "IEParserTests", dependencies: ["IEParser", "WiFiModel"]),
        .testTarget(name: "WdutilBridgeTests", dependencies: ["WdutilBridge", "WiFiModel"]),
        .testTarget(name: "OUIResolverTests", dependencies: ["OUIResolver", "WiFiModel"]),
        .testTarget(name: "TelemetryTests", dependencies: ["Telemetry", "WiFiModel"]),
    ]
)
