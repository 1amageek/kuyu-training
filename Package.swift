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
        .library(
            name: "KuyuTrainingContracts",
            targets: ["KuyuTrainingContracts"]
        ),
        .library(
            name: "KuyuEvolution",
            targets: ["KuyuEvolution"]
        ),
        .library(
            name: "KuyuReinforcement",
            targets: ["KuyuReinforcement"]
        ),
        .library(
            name: "KuyuTrainingRuntime",
            targets: ["KuyuTrainingRuntime"]
        ),
        .library(
            name: "KuyuTrainingValidation",
            targets: ["KuyuTrainingValidation"]
        ),
    ],
    dependencies: [
        .package(path: "../kuyu-core"),
        .package(path: "../kuyu-physics"),
        .package(path: "../kuyu-scenarios"),
    ],
    targets: [
        .target(
            name: "KuyuTrainingContracts"
        ),
        .target(
            name: "KuyuEvolution",
            dependencies: [
                "KuyuTrainingContracts",
            ]
        ),
        .target(
            name: "KuyuReinforcement",
            dependencies: [
                "KuyuTrainingContracts",
            ]
        ),
        .target(
            name: "KuyuTrainingValidation",
            dependencies: [
                "KuyuTrainingContracts",
                "KuyuEvolution",
                "KuyuReinforcement",
                .product(name: "KuyuCore", package: "kuyu-core"),
                .product(name: "KuyuPhysics", package: "kuyu-physics"),
                .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
            ]
        ),
        .target(
            name: "KuyuTrainingRuntime",
            dependencies: [
                "KuyuTrainingContracts",
                "KuyuEvolution",
                "KuyuReinforcement",
                "KuyuTrainingValidation",
                .product(name: "KuyuCore", package: "kuyu-core"),
                .product(name: "KuyuPhysics", package: "kuyu-physics"),
                .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
            ]
        ),
        .target(
            name: "KuyuTraining",
            dependencies: [
                "KuyuTrainingContracts",
                "KuyuEvolution",
                "KuyuReinforcement",
                "KuyuTrainingRuntime",
                "KuyuTrainingValidation",
            ]
        ),
        .testTarget(
            name: "KuyuTrainingTests",
            dependencies: [
                "KuyuTraining",
                "KuyuTrainingRuntime",
                .product(name: "KuyuPhysics", package: "kuyu-physics"),
                .product(name: "KuyuScenarios", package: "kuyu-scenarios"),
            ]
        ),
    ]
)
