// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Indie",
    defaultLocalization: "zh-Hans",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "IndieCore", targets: ["IndieCore"]),
        .library(name: "IndieRuntime", targets: ["IndieRuntime"]),
        .library(name: "IndieCatalog", targets: ["IndieCatalog"]),
        .executable(name: "indiectl", targets: ["IndieCLI"]),
        .executable(name: "IndieApp", targets: ["IndieApp"]),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .target(name: "IndieCore", dependencies: ["CSQLite"]),
        .target(name: "IndieRuntime", dependencies: ["IndieCore"]),
        .target(name: "IndieCatalog", dependencies: ["IndieCore"], resources: [.process("Resources")]),
        .executableTarget(
            name: "IndieCLI",
            dependencies: ["IndieCore", "IndieRuntime", "IndieCatalog"]
        ),
        .executableTarget(
            name: "IndieApp",
            dependencies: ["IndieCore", "IndieRuntime", "IndieCatalog"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "IndieCoreTests", dependencies: ["IndieCore"]),
        .testTarget(name: "IndieRuntimeTests", dependencies: ["IndieRuntime", "IndieCore"]),
        .testTarget(name: "IndieCatalogTests", dependencies: ["IndieCatalog", "IndieCore"]),
    ]
)
