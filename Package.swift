// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "QuickChat",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "QuickChat", targets: ["QuickChat"]),
    ],
    targets: [
        // Everything that doesn't need a UI: models, config import, streaming client, storage.
        .target(name: "QuickChatCore"),
        // The menu-bar app: AppKit shell + SwiftUI views.
        .executableTarget(name: "QuickChat", dependencies: ["QuickChatCore"]),
        // No XCTest/Swift Testing on a Command-Line-Tools-only machine, so tests are a plain
        // executable: `swift run selftest` exits non-zero if any check fails.
        .executableTarget(name: "selftest", dependencies: ["QuickChatCore"], path: "Tests/SelfTest",
                          exclude: ["Fixtures"]),
    ]
)
