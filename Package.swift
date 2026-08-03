// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "NetDiagnose",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "NetDiagnose",
            path: "Sources/NetDiagnose"
        ),
        .testTarget(
            name: "NetDiagnoseTests",
            dependencies: ["NetDiagnose"],
            path: "Tests/NetDiagnoseTests",
            resources: []
        )
    ]
)
