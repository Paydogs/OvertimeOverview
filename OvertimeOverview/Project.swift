@preconcurrency import ProjectDescription
import Foundation

let devMarketingVersion = "1.1.0"
let releaseMarketingVersion = "1.0.0"

// Auto-incrementing build number (CURRENT_PROJECT_VERSION / CFBundleVersion). App Store
// Connect rejects a (marketing version, build) pair it has already seen, so the number
// must rise per archive — and the commit count only rises per commit, which is why the
// same number kept coming out of repeated archives. The counter lives in a plain file
// (one machine, one number): `tuist generate` reads it for the generate-time value, and
// at archive time (ACTION=install) run-script phases bump/stamp it into both built
// plists before code signing — the same PlistBuddy mechanism Analog uses for its count.
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

// Archive-time plist stamping. A normal (not install-only) post script sits in the
// build-phase order BEFORE code signing, which is what lets a rewritten CFBundleVersion
// land in the signed bundle. Both scripts no-op except on the install action (ACTION=install
// is Xcode's archive signal), so plain build / build-for-testing keep the generate-time
// number. Normal (non-archive) runs between archives always carry the last bumped value.
enum BuildScripts {
    /// Counter source of truth lives in Support/buildNumber; this bumps it once per
    /// archive. It is attached to the WIDGET target because the widget builds first
    /// as the app's dependency — stamping must see the final value.
    static let bumpAndStampBuildNumber = TargetScript.post(
        script: """
        if [ "$ACTION" != "install" ]; then exit 0; fi
        FILE="$SRCROOT/Support/buildNumber"
        NEXT=$(( $(cat "$FILE" 2>/dev/null || echo 0) + 1 ))
        printf '%s\\n' "$NEXT" > "$FILE"
        PLIST="$BUILT_PRODUCTS_DIR/$INFOPLIST_PATH"
        [ -f "$PLIST" ] || exit 0
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT" "$PLIST" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $NEXT" "$PLIST"
        """,
        name: "Bump & Stamp Build Number",
        basedOnDependencyAnalysis: false
    )

    /// Stamps the same value the widget stamped, so app and appex never diverge.
    /// No bump here — the widget target did it when it built first.
    static let stampBuildNumber = TargetScript.post(
        script: """
        if [ "$ACTION" != "install" ]; then exit 0; fi
        FILE="$SRCROOT/Support/buildNumber"
        [ -f "$FILE" ] || exit 0
        NEXT=$(cat "$FILE")
        PLIST="$BUILT_PRODUCTS_DIR/$INFOPLIST_PATH"
        [ -f "$PLIST" ] || exit 0
        /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $NEXT" "$PLIST" 2>/dev/null \
            || /usr/libexec/PlistBuddy -c "Add :CFBundleVersion string $NEXT" "$PLIST"
        """,
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
    // The widget is the app's dependency, so inside an archive this target builds
    // first: its script performs the one bump, the app's stamps the shared value.
    scripts: [BuildScripts.bumpAndStampBuildNumber]
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
        // generation never fails; the archive script can still override via --build-number.
        return "1"
    }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let count = String(data: data, encoding: .utf8)?
        .trimmingCharacters(in: .whitespacesAndNewlines)
    return (count?.isEmpty == false) ? count! : "1"
}