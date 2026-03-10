// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NotesBridge",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "NotesBridge",
            targets: ["NotesBridge"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/scinfu/SwiftSoup.git", exact: "2.9.6"),
    ],
    targets: [
        .executableTarget(
            name: "NotesBridge",
            dependencies: [
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
        .testTarget(
            name: "NotesBridgeTests",
            dependencies: ["NotesBridge"],
            swiftSettings: [
                .unsafeFlags([
                    "-F/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-I/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                    "-Xlinker",
                    "-rpath",
                    "-Xlinker",
                    "/Library/Developer/CommandLineTools/Library/Developer/Frameworks",
                ]),
            ]
        ),
    ]
)
