@preconcurrency import ProjectDescription
import Foundation

let devMarketingVersion = "1.1.0"
let releaseMarketingVersion = "1.0.0"

// Build number: App Store Connect rejects a reused (version, build) pair, so the counter
// in Support/buildNumber must rise per archive — the commit count only rises per commit.
// At archive time the scheme's pre-action bumps it (Support/bumpBuildNumber.sh) and both
// targets stamp it (Support/stampBuildNumber.sh). Commit the file after archiving:
// a fresh clone must not show a stale counter.
func readBuildNumber() -> String {
    // #filePath in the manifest is this Project.swift's path; fall back to the commit
    // count when the counter file is missing (e.g. a fresh clone before it is committed).
    let filePath = String(#filePath)
        .replacingOccurrences(of: "Project.swift", with: "Support/buildNumber")
    if let content = try? String(contentsOfFile: filePath, encoding: .utf8),
       let number = Int(content.trimmingCharacters(in: .whitespacesAndNewlines)) {
        return "\(number)"
    }
    return gitCommitCount()
}

let buildNumber = readBuildNumber()

enum BuildScripts {
    // Shared by app and widget; both stamp the pre-bumped counter so the plists match.
    static let stampBuildNumber = TargetScript.post(
        path: "Support/stampBuildNumber.sh",
        name: "Stamp Build Number",
        basedOnDependencyAnalysis: false
    )
}

// Signing identity, shared by the app and both test bundles: a test target without a team fails
// to sign for a device, which is what `make build` (build-for-testing on a generic iOS device)
// does. The AutomatedTests scripts used to paper over it by passing DEVELOPMENT_TEAM on the
// xcodebuild command line; declaring it here is what makes that unnecessary.
let developmentTeam = "64GU57DP44"
let signingSettings: SettingsDictionary = [
    "DEVELOPMENT_TEAM": .string(developmentTeam),
    "CODE_SIGN_STYLE": "Automatic"
]

// 1. The Main App Target
let defaultApp = Target.target(
    name: "OvertimeOverview",
    destinations: [.iPhone],
    product: .app,
    bundleId: "hu.paydogs.overtime",
    deploymentTargets: .iOS("17.0"),
    infoPlist: .extendingDefault(
        with: [
            "CFBundleShortVersionString": "$(MARKETING_VERSION)",
            "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
            // Spaced app name shows on the home screen; the product name has none.
            "CFBundleDisplayName": .string("Overtime Overview"),
            // Export-compliance declaration (as in Analog):
            // the app ships only App Store–exempt encryption (system APIs).
            "ITSAppUsesNonExemptEncryption": false,
            "DEVELOPMENT_TEAM": .string(developmentTeam),
            "CODE_SIGN_STYLE": "Automatic",
            "UILaunchScreen": [
                "UIColorName": "",
                "UIImageName": "",
            ],
            // Custom fonts (Resources/Fonts); consumers fall back to SF Pro if unregistered.
            "UIAppFonts": ["BricolageGrotesque.ttf", "CourierPrime-Bold.ttf"],
        ]
    ),
    sources: [
        // The widget's @main must not leak into the app target, hence the second exclusion.
        .glob("Application/**/*.swift", excluding: ["Application/Tests/**", "Application/WorktimeWidget/**"])
    ],
    resources: ["Application/Resources/**"],
    entitlements: .file(path: "Support/OvertimeOverview.entitlements"),
    scripts: [BuildScripts.stampBuildNumber],
    dependencies: [
        .external(name: "Logging"),
        .target(name: "WorktimeWidget")
    ],
    settings: .settings(
        // Target level on purpose: Tuist injects its own target-level
        // "AppIcon" default that a project-level value would lose to.
        base: ["ASSETCATALOG_COMPILER_APPICON_NAME": .string("OvertimeOverviewLogo")]
    )
)

// 2. The Widget Extension Target
let worktimeWidget = Target.target(
    name: "WorktimeWidget",
    destinations: [.iPhone],
    product: .appExtension,
    bundleId: "hu.paydogs.overtime.WorktimeWidget",
    deploymentTargets: .iOS("17.0"),
    infoPlist: .extendingDefault(
        with: [
            "NSExtension": ["NSExtensionPointIdentifier": "com.apple.widgetkit-extension"],
            // App extensions must show their own display name on install/archive.
            "CFBundleDisplayName": .string("Overtime Overview"),
            // Same exempt-encryption declaration for the extension.
            "ITSAppUsesNonExemptEncryption": false,
            "CFBundleShortVersionString": "$(MARKETING_VERSION)",
            "CFBundleVersion": "$(CURRENT_PROJECT_VERSION)",
            "DEVELOPMENT_TEAM": .string(developmentTeam),
            "CODE_SIGN_STYLE": "Automatic",
            "UIAppFonts": ["BricolageGrotesque.ttf", "CourierPrime-Bold.ttf"]
        ]
    ),
    sources: [
        .glob(
            "Application/WorktimeWidget/**/*.swift",
            excluding: ["Application/WorktimeWidget/Resources/**", "Application/WorktimeWidget/Support/**"]
        ),
        // Domain and Localization are compiled into the widget as well: the intents and the
        // timeline use WorktimeStore/WorktimeSettings/Formatters, which need the Keys.tr strings.
        .glob("Application/Domain/**/*.swift"),
        .glob("Application/System/Localization/**/*.swift")
    ],
    resources: ["Application/WorktimeWidget/Resources/**"],
    entitlements: .file(path: "Application/WorktimeWidget/Support/WorktimeWidget.entitlements"),
    scripts: [BuildScripts.stampBuildNumber]
)

// 3. The Unit Test Target (XCTest / Swift Testing)
let unitTests = Target.target(
    name: "OvertimeOverviewTests",
    destinations: [.iPhone],
    product: .unitTests,
    bundleId: "hu.paydogs.overtimeTests",
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
    bundleId: "hu.paydogs.overtimeUITests",
    deploymentTargets: .iOS("17.0"),
    infoPlist: .default,
    sources: ["Application/Tests/UITests/**"],
    dependencies: [
        .target(name: "OvertimeOverview")
    ]
)

// Explicit scheme so the archive action can bump the counter in a PRE-action (runs before
// any target builds): the two stamp post-actions can then rely on one final value, no
// matter which target builds first. Replaces Tuist's autogenerated scheme.
let scheme = Scheme.scheme(
    name: "OvertimeOverview",
    shared: true,
    buildAction: .buildAction(targets: [.target("OvertimeOverview")]),
    testAction: .targets(
        [
            .testableTarget(target: "OvertimeOverviewTests"),
            .testableTarget(target: "OvertimeOverviewUITests"),
        ]
    ),
    runAction: .runAction(configuration: .debug, executable: .target("OvertimeOverview")),
    archiveAction: .archiveAction(
        configuration: .release,
        preActions: [
            .executionAction(
                title: "Bump Build Number",
                scriptText: "\"$SRCROOT/Support/bumpBuildNumber.sh\"",
                target: .target("OvertimeOverview")
            )
        ]
    )
)

let project = Project(
    name: "OvertimeOverview",
    // MARKETING_VERSION / CURRENT_PROJECT_VERSION must be set at project level so every
    // target (app, appex, test bundles) inherits them: iOS refuses to install an extension
    // whose CFBundleVersion resolves to an empty string.
    settings: .settings(
        base: SettingsDictionary()
            .automaticCodeSigning(devTeam: "\(developmentTeam)")
            .marketingVersion(devMarketingVersion)
            .currentProjectVersion(buildNumber)
    ),
    targets: [defaultApp, worktimeWidget, unitTests, uiTests],
    schemes: [scheme],
    resourceSynthesizers: [
        .assets(),
        .strings()
    ]
)

func gitCommitCount() -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = ["rev-list", "--count", "HEAD"]
    let pipe = Pipe()
    process.standardOutput = pipe
    do {
        try process.run()
    } catch {
        // git unavailable (e.g. a bare export with no repo) — fall back to a constant so
        // generation never fails.
        return "1"
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let count = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return (count?.isEmpty == false) ? count! : "1"
}