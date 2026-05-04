// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "GentleLight",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "gentle-light", targets: ["GentleLight"])
    ],
    targets: [
        .executableTarget(
            name: "GentleLight",
            path: "Sources/GentleLight"
        )
    ]
)
