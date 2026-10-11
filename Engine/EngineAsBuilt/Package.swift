// swift-tools-version: 6.2
import PackageDescription

// Swift 6.4 feature flags used by this branch.
//
// Currently empty on purpose. `LifetimeDependence` + `Lifetimes` were enabled to write `@_lifetime`-
// annotated accessors that vend a `Span`, which turned out to be unusable here for two independent
// reasons: a `borrow` accessor may only return a stored property (SE-0507), and `Array.span` itself
// needs macOS 26 — see Sources/ZephyrCore/Swift64FeatureCanary.swift for the full availability matrix.
// `borrow`/`mutate` accessors and `Span`/`RawSpan` need no flag, so nothing here is gated.
//
// Re-add the flags only if an explicitly annotated lifetime-dependent result becomes necessary again:
//   .enableExperimentalFeature("LifetimeDependence"), .enableExperimentalFeature("Lifetimes"),
let zephyrSwiftSettings: [SwiftSetting] = []

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
