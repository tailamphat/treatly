// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Treatly",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Treatly", targets: ["Treatly"]),
    ],
    targets: [
        // Pure logic: tasks, escalation, pet behaviour, pet packs. No AppKit.
        .target(name: "TreatlyCore"),
        // The macOS app: overlay window, rendering, menu bar, task sources.
        .executableTarget(name: "Treatly", dependencies: ["TreatlyCore"]),
        // Assertion runner for TreatlyCore. Command Line Tools ship without a
        // working XCTest/Swift Testing, so `swift run TreatlyChecks` stands in.
        .executableTarget(name: "TreatlyChecks", dependencies: ["TreatlyCore"]),
    ]
)
