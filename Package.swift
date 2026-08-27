// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Shift",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "Shift",
            targets: ["Shift"]
        ),
        .executable(
            name: "ShiftApp",
            targets: ["ShiftAppTarget"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "Shift",
            dependencies: [],
            path: "Sources/Shift"
        ),
        .executableTarget(
            name: "ShiftAppTarget",
            dependencies: ["Shift"],
            path: "Sources/ShiftAppTarget"
        ),
        .testTarget(
            name: "ShiftTests",
            dependencies: ["Shift"],
            path: "Tests/ShiftTests"
        )
    ]
)
