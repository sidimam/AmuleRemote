// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AmuleRemote",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "AmuleRemote",
            path: "Sources/AmuleRemote"
        )
    ]
)
