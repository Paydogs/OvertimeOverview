
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: [
            "Logging": .framework,
        ],
        baseSettings: .settings(configurations: [
            .debug(name: "Debug"),
            .release(name: "Release")
        ])
    )

#endif

let package = Package(
    name: "Dependencies",
    dependencies: [
        .package(url: "https://github.com/Apple/swift-log", from: "1.8.0"),
    ],
    targets: [
    ]
)
