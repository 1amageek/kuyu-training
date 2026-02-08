// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "kuyu-training",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        .library(
            name: "KuyuTraining",
            targets: ["KuyuTraining"]
        ),
    ],
    dependencies: [
        .package(path: "../kuyu-core"),
        .package(path: "../kuyu-physics"),
        .package(path: "../kuyu-scenarios"),
    ],
    targets: [
        .target(
            name: "KuyuTraining",
            dependencies: [
                .product(name: "KuyuCore", package: "kuyu-core"),
                .product(name: "KuyuPhysics", package: "kuyu-physics"),
                .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
            ]
        ),
        .testTarget(
            name: "KuyuTrainingTests",
            dependencies: ["KuyuTraining"]
        ),
    ]
)
