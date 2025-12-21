// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Victor",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "Victor",
            targets: ["Victor"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/johnxnguyen/Down.git", from: "0.11.0"),
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/LebJe/TOMLKit.git", from: "0.5.0")
    ],
    targets: [
        .executableTarget(
            name: "Victor",
            dependencies: [
                "Down",
                "Yams",
                "TOMLKit"
            ],
            path: "Victor"
        ),
        .testTarget(
            name: "VictorTests",
            dependencies: ["Victor"],
            path: "VictorTests"
        )
    ]
)
