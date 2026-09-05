// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacGamingUncle",
    defaultLocalization: "en",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "IndieCore", targets: ["IndieCore"]),
        .library(name: "IndieRuntime", targets: ["IndieRuntime"]),
        .library(name: "IndieCatalog", targets: ["IndieCatalog"]),
        .executable(name: "macgamingunclectl", targets: ["MacGamingUncleCLI"]),
        .executable(name: "MacGamingUncleApp", targets: ["MacGamingUncleApp"]),
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite"
        ),
        .target(name: "IndieCore", dependencies: ["CSQLite"], resources: [.process("Resources")]),
        .target(name: "IndieRuntime", dependencies: ["IndieCore"]),
        .target(name: "IndieCatalog", dependencies: ["IndieCore"], resources: [.process("Resources")]),
        .executableTarget(
            name: "MacGamingUncleCLI",
            dependencies: ["IndieCore", "IndieRuntime", "IndieCatalog"]
        ),
        .executableTarget(
            name: "MacGamingUncleApp",
            dependencies: ["IndieCore", "IndieRuntime", "IndieCatalog"],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "IndieCoreTests", dependencies: ["IndieCore"]),
        .testTarget(name: "IndieRuntimeTests", dependencies: ["IndieRuntime", "IndieCore"]),
        .testTarget(name: "IndieCatalogTests", dependencies: ["IndieCatalog", "IndieCore"]),
    ]
)
