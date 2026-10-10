// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "HitmozDownloader",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "HitmozDownloader",
            targets: ["HitmozDownloader"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.7.0")
    ],
    targets: [
        .executableTarget(
            name: "HitmozDownloader",
            dependencies: ["SwiftSoup"],
            path: "Sources/HitmozDownloader"
        )
    ]
)