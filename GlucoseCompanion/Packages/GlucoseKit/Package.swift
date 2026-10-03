// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GlucoseKit",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [
        .library(name: "GlucoseCore", targets: ["GlucoseCore"]),
        .library(name: "GlucoseHealth", targets: ["GlucoseHealth"]),
        .library(name: "GlucoseStorage", targets: ["GlucoseStorage"]),
        .executable(name: "glucose-report", targets: ["GlucoseReport"]),
    ],
    targets: [
        // Models, units, ranges, analytics, safety copy. Foundation only.
        .target(name: "GlucoseCore"),
        // HealthKit access behind a protocol, plus a demo implementation.
        .target(name: "GlucoseHealth", dependencies: ["GlucoseCore"]),
        // SwiftData mirror of Apple Health and the app's own records.
        .target(name: "GlucoseStorage", dependencies: ["GlucoseCore"]),
        // Command-line demo: prints a report built from sample data.
        .executableTarget(name: "GlucoseReport", dependencies: ["GlucoseCore"]),
        .testTarget(name: "GlucoseCoreTests", dependencies: ["GlucoseCore"]),
    ]
)
