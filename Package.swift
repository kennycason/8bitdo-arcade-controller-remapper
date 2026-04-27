// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "8bitdo-arcade-controller-remapper",
    products: [
        .executable(name: "8bitdo-arcade-controller-remapper", targets: ["remapper"]),
    ],
    targets: [
        .executableTarget(name: "remapper", path: "Sources"),
    ]
)
