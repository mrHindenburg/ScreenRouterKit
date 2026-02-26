// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ScreenRouterKit",
    platforms: [
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "ScreenRouterKit",
            targets: ["ScreenRouterKit"]
        ),
    ],
    targets: [
        .target(
            name: "ScreenRouterKit",
            dependencies: [],
            path: "Sources/ScreenRouterKit"
        ),
    ]
)
