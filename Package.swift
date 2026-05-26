// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "apple-mcp",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "apple-mcp", targets: ["AppleMCP"])
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.12.1")
    ],
    targets: [
        .executableTarget(
            name: "AppleMCP",
            dependencies: [
                .product(name: "MCP", package: "swift-sdk")
            ],
            path: "Sources/AppleMCP",
            linkerSettings: [
                .linkedFramework("EventKit"),
                .linkedFramework("Contacts"),
                .linkedFramework("Foundation"),
                .linkedFramework("AppKit")
            ]
        )
    ]
)
