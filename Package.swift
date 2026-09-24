// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LectureScribe",
    platforms: [.macOS("27.0")],
    products: [
        .executable(name: "lecturescribe", targets: ["LectureScribe"])
    ],
    targets: [
        .executableTarget(
            name: "LectureScribe",
            path: "Sources/LectureScribe",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "LectureScribeTests",
            dependencies: ["LectureScribe"],
            path: "Tests/LectureScribeTests",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
