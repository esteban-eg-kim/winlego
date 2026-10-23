// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "winlego",
    platforms: [.macOS(.v13)],
    targets: [
        // Pure logic: layouts, zones, rules, the enforcement state machine. No AppKit, fully testable.
        .target(name: "WinlegoCore"),
        .executableTarget(
            name: "winlego",
            dependencies: ["WinlegoCore"]
        ),
        .testTarget(
            name: "WinlegoCoreTests",
            dependencies: ["WinlegoCore"]
        ),
    ]
)
