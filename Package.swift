// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "FileWheel",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .library(name: "FileWheelKit", targets: ["FileWheelKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/weichsel/ZIPFoundation.git", from: "0.9.19"),
    ],
    targets: [
        .target(
            name: "FileWheelKit",
            dependencies: ["ZIPFoundation"],
            path: "FileWheel",
            exclude: [
                "App",
                "Drag",
                "Wheel",
                "Support",
                "Settings/AppSettings.swift",
                "Tools/ToolWheel.swift",
            ]
        ),
        .testTarget(
            name: "FileWheelKitTests",
            dependencies: ["FileWheelKit"],
            path: "Tests/FileWheelKitTests"
        ),
    ]
)
