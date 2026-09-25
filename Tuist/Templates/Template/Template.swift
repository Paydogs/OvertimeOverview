import ProjectDescription

let nameAttribute: Template.Attribute = .required("name")
let bundleIdAttribute: Template.Attribute = .required("bundle_id")
let authorAttribute: Template.Attribute = .required("author")

// MARK: - Files
let projectItems: [Template.Item] = [
    .file(path: "\(nameAttribute)/Workspace.swift",        templatePath: "Workspace.stencil"),
    .file(path: "\(nameAttribute)/Project.swift",          templatePath: "Project.stencil"),
]

let appItems: [Template.Item] = [
    .file(path: "\(nameAttribute)/Application/\(nameAttribute)App.swift",                     templatePath: "AppEntry.stencil"),
    .file(path: "\(nameAttribute)/Application/AppDelegate.swift",                             templatePath: "AppDelegate.stencil"),
    .file(path: "\(nameAttribute)/Application/System/Localization/Localization.swift",        templatePath: "System/Localization/Localization.stencil"),
    .file(path: "\(nameAttribute)/Application/UI/ContentView.swift",                          templatePath: "UI/ContentView.stencil"),
]

let testItems: [Template.Item] = [
    .file(path: "\(nameAttribute)/Application/Tests/UITests/\(nameAttribute)UITests.swift",            templatePath: "Tests/UITests/UITests.stencil"),
    .file(path: "\(nameAttribute)/Application/Tests/UITests/\(nameAttribute)UITestsLaunchTests.swift", templatePath: "Tests/UITests/UITestsLaunchTests.stencil"),
    .file(path: "\(nameAttribute)/Application/Tests/UnitTests/\(nameAttribute)Tests.swift",            templatePath: "Tests/UnitTests/UnitTests.stencil"),
]

let resourceItems: [Template.Item] = [
    .file(path: "\(nameAttribute)/Application/Resources/Assets.xcassets/Contents.json",                    templatePath: "Resources/Assets.stencil"),
    .file(path: "\(nameAttribute)/Application/Resources/Assets.xcassets/AppIcon.appiconset/Contents.json", templatePath: "Resources/AppIcon.stencil"),
    .file(path: "\(nameAttribute)/Application/Resources/en.lproj/Localizable.strings",                     templatePath: "Resources/StringsEN.stencil"),
    .file(path: "\(nameAttribute)/Application/Resources/hu.lproj/Localizable.strings",                     templatePath: "Resources/StringsHU.stencil"),
]

// MARK: - Template

let template = Template(
    description: "iOS Skeleton Template",
    attributes: [
        nameAttribute,
        bundleIdAttribute,
        authorAttribute,
        .optional("date", default: "{{ date }}")
    ],
    items: projectItems + appItems + testItems + resourceItems
)
