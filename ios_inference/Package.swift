// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "RLSInference",
    platforms: [
        .iOS(.v15),
        .macOS(.v12),
    ],
    products: [
        .library(name: "RLSInference", targets: ["RLSInference"]),
        .executable(name: "RLSInferenceSmoke", targets: ["RLSInferenceSmoke"]),
    ],
    targets: [
        .target(name: "RLSInference"),
        .executableTarget(name: "RLSInferenceSmoke", dependencies: ["RLSInference"]),
        .testTarget(name: "RLSInferenceTests", dependencies: ["RLSInference"]),
    ]
)
