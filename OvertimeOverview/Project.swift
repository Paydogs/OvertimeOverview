@preconcurrency import ProjectDescription

// 1. The Main App Target
let defaultApp = Target.target(
    name: "OvertimeOverview",
    destinations: [.iPhone],
    product: .app,
    bundleId: "hu.paydogs.overtimeoverview",
    deploymentTargets: .iOS("17.0"),
    infoPlist: .extendingDefault(
        with: [
            "UILaunchScreen": [
                "UIColorName": "",
                "UIImageName": "",
            ],
        ]
    ),
    sources: [
        .glob("Application/**/*.swift", excluding: ["Application/Tests/**"]),
        .glob("Domain/**/*.swift")
    ],
    resources: ["Application/Resources/**"],
    entitlements: .file(path: "Support/OvertimeOverview.entitlements"),
    dependencies: [
        .external(name: "Alamofire"),
        .external(name: "Lottie"),
        .external(name: "Swinject"),
        .external(name: "Logging"),
        .target(name: "WorktimeWidget")
    ]
)

// 2. The Widget Extension Target
let worktimeWidget = Target.target(
    name: "WorktimeWidget",
    destinations: [.iPhone],
    product: .appExtension,
    bundleId: "hu.paydogs.overtimeoverview.WorktimeWidget",
    deploymentTargets: .iOS("17.0"),
    infoPlist: .extendingDefault(
        with: [
            "NSExtension": ["NSExtensionPointIdentifier": "com.apple.widgetkit-extension"]
        ]
    ),
    sources: [
        .glob("WorktimeWidget/**/*.swift", excluding: ["WorktimeWidget/Resources/**", "WorktimeWidget/Support/**"]),
        .glob("Domain/**/*.swift"),
        // Localization backs the generated Keys.tr, which Formatters (via Domain) needs.
        .glob("Application/System/Localization/**/*.swift")
    ],
    resources: ["WorktimeWidget/Resources/**"],
    entitlements: .file(path: "WorktimeWidget/Support/WorktimeWidget.entitlements")
)

// 3. The Unit Test Target (XCTest / Swift Testing)
let unitTests = Target.target(
    name: "OvertimeOverviewTests",
    destinations: [.iPhone],
    product: .unitTests,
    bundleId: "hu.paydogs.overtimeoverviewTests",
    deploymentTargets: .iOS("17.0"),
    infoPlist: .default,
    sources: ["Application/Tests/UnitTests/**"],
    dependencies: [
        .target(name: "OvertimeOverview") // Access app code via @testable import
    ]
)

// 3. The UI Test Target
let uiTests = Target.target(
    name: "OvertimeOverviewUITests",
    destinations: [.iPhone],
    product: .uiTests,
    bundleId: "hu.paydogs.overtimeoverviewUITests",
    deploymentTargets: .iOS("17.0"),
    infoPlist: .default,
    sources: ["Application/Tests/UITests/**"],
    dependencies: [
        .target(name: "OvertimeOverview")
    ]
)

let project = Project(
    name: "OvertimeOverview",
    settings: .settings(base: SettingsDictionary().automaticCodeSigning(devTeam: "64GU57DP44")),
    targets: [defaultApp, worktimeWidget, unitTests, uiTests],
    resourceSynthesizers: [
        .assets(),
        .strings()
    ]
)