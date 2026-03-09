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
    targets: [
        .executableTarget(
            name: "NotesBridge"
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
