// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "JumpFolder",
    platforms: [.macOS(.v26)],
    targets: [
        // Pure logic (recent-folder lists, dialog geometry, path checks), kept free of
        // AppKit and Accessibility so it can be tested without a real dialog.
        .target(name: "JumpFolderKit"),
        .executableTarget(name: "JumpFolder", dependencies: ["JumpFolderKit"]),
        .testTarget(name: "JumpFolderKitTests", dependencies: ["JumpFolderKit"]),
    ]
)
