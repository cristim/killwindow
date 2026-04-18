// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "killwindow",
    platforms: [.macOS(.v11)],
    targets: [
        .executableTarget(
            name: "killwindow",
            path: "Sources/killwindow"
        )
    ]
)
