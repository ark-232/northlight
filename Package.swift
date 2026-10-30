// swift-tools-version: 6.0
import PackageDescription

// NorthlightKit is the UI-free core: model, feeds, store and parsers, tested on the
// host with `swift test`. NorthlightUI holds the SwiftUI widgets, so the tvOS app and
// the macOS editor draw them alike. NorthlightAgent reads coding agents' transcripts,
// on the Mac only.
let package = Package(
    name: "Northlight",
    platforms: [.tvOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "NorthlightKit", targets: ["NorthlightKit"]),
        .library(name: "NorthlightUI", targets: ["NorthlightUI"]),
        .library(name: "NorthlightAgent", targets: ["NorthlightAgent"]),
    ],
    targets: [
        .target(name: "NorthlightKit"),
        .target(name: "NorthlightUI", dependencies: ["NorthlightKit"]),
        .target(name: "NorthlightAgent", dependencies: ["NorthlightKit"]),
        .testTarget(
            name: "NorthlightKitTests",
            dependencies: ["NorthlightKit", "NorthlightAgent"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
