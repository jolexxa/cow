// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CowMLX",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "CowMLX", type: .dynamic, targets: ["CowMLX"]),
    ],
    dependencies: [
        .package(
            url: "https://github.com/ml-explore/mlx-swift-lm",
            branch: "main"
        ),
    ],
    targets: [
        .target(
            name: "CowMLX",
            dependencies: [
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ],
            path: "Sources/CowMLX",
            publicHeadersPath: "include",
            linkerSettings: [
                .linkedFramework("Metal"),
                .linkedFramework("Accelerate"),
            ]
        ),
    ]
)
