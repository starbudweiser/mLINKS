// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mLINKS",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "mLINKSCore", linkerSettings: [.linkedLibrary("sqlite3")]),
        .executableTarget(name: "mLINKS", dependencies: ["mLINKSCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "mLINKSTests", dependencies: ["mLINKSCore"]),
    ]
)
