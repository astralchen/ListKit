// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ListKit",
    platforms: [.iOS(.v14)],
    products: [
        .library(name: "ListKit", targets: ["ListKit"])
    ],
    targets: [
        .target(name: "ListKit"),
        .testTarget(name: "ListKitTests", dependencies: ["ListKit"])
    ]
)
