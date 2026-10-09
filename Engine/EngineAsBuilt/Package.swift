// swift-tools-version: 6.2
import PackageDescription

// Swift 6.4 features used by this branch that are still gated behind an experimental flag:
//
// * LifetimeDependence — lets a property or method return a `Span` (a `~Escapable` value). With this
//   flag the dependency on `self` is *inferred*, so the common case needs no annotation at all:
//       var bytes: Span<UInt8> { borrow { return storage.span } }
// * Lifetimes — enables the explicit `@_lifetime(...)` spelling, which the compiler still requires for
//   some derived results, e.g. a *method* returning a slice it computed rather than a stored value:
//       @_lifetime(borrow self) func slice(_ r: Range<Int>) -> Span<UInt8>
//   (The prettier `@lifetime(borrow self)` is accepted but warns: "Unsupported use of @lifetime,
//   use @_lifetime" — so we use the spelling the compiler actually supports.)
//
// Both flags are unstable: CI pins the toolchain to Swift 6.4.0 and `Swift64FeatureCanary.swift`
// fails the build if a toolchain renames, re-gates, or removes either one. The parser keeps its hot
// loop on plain index arithmetic, so only a handful of accessors depend on these features.
// See plans/swift-6.4-adoption.md.
let zephyrSwiftSettings: [SwiftSetting] = [
    .enableExperimentalFeature("LifetimeDependence"),
    .enableExperimentalFeature("Lifetimes"),
]

let package = Package(
    name: "Zephyr",
    platforms: [.macOS(.v12), .iOS(.v13)],
    products: [
        .library(name: "ZephyrCore", targets: ["ZephyrCore"]),
        .executable(name: "Zephyr", targets: ["Zephyr"]),
    ],
    dependencies: [
        .package(name: "SwiftSDL", path: "../SwiftSDL"),
        .package(name: "SwiftSDL_image", path: "../SwiftSDL_image"),
        .package(name: "SwiftSDL_ttf", path: "../SwiftSDL_ttf"),
        .package(name: "SwiftImGui", path: "../SwiftImGui"),
        .package(name: "SwiftZLibNG", path: "../SwiftZLibNG"),
    ],
    targets: [
        .target(
            name: "ZephyrCore",
            dependencies: [
                .product(name: "CZLibNG", package: "SwiftZLibNG"),
                .product(name: "CSDL3", package: "SwiftSDL"),
                .product(name: "SwiftSDL", package: "SwiftSDL"),
                .product(name: "SwiftSDL_image", package: "SwiftSDL_image"),
                .product(name: "SwiftSDL_ttf", package: "SwiftSDL_ttf"),
                .product(name: "ImGui", package: "SwiftImGui"),
            ],
            path: "Sources/ZephyrCore",
            resources: [
                .copy("../../Patterns")
            ],
            swiftSettings: zephyrSwiftSettings
        ),
        .executableTarget(
            name: "Zephyr",
            dependencies: [
                "ZephyrCore",
                .product(name: "ImGui", package: "SwiftImGui"),
            ],
            path: "Sources/Zephyr",
            swiftSettings: zephyrSwiftSettings
        ),
        .testTarget(
            name: "ZephyrTests",
            dependencies: ["ZephyrCore"],
            path: "Tests/ZephyrTests",
            swiftSettings: zephyrSwiftSettings
        ),
        // Perf harness (plain executable, not a test): `swift run -c release ZephyrBench ...`.
        // Kept out of the test target because that one needs the libdxfrw C module.
        .executableTarget(
            name: "ZephyrBench",
            dependencies: ["ZephyrCore"],
            path: "Sources/ZephyrBench",
            swiftSettings: zephyrSwiftSettings
        ),
    ]
)
