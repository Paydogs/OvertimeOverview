# Worktime Monitor Port Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-implement MagniTools' Worktime monitor as the OvertimeOverview iOS app — Today/History/Settings bottom TabView, SwiftData persistence, JSON backup, haptics, interactive WidgetKit widget.

**Architecture:** A plain `Domain/` folder is compiled into both the app target and the widget-extension target (no package). SwiftData `WorkSessionModel` maps to a `WorkSession` domain struct via `Domain/Mappers/`; all business rules live in pure functions (`WorktimeMath`) that views and the store share. App Group `group.hu.paydogs.overtimeoverview` holds the SwiftData store and UserDefaults so the widget and app see the same data.

**Tech Stack:** Swift 5, SwiftUI + Observation (iOS 17), SwiftData, WidgetKit + App Intents, Core Haptics, Tuist 4.208.

**Spec:** `docs/superpowers/specs/2026-09-25-worktime-port-design.md`

## Global Constraints

- Deployment target **iOS 17.0** on every target (SwiftData, Observation, interactive widgets).
- **No commits by the agent** — the user commits. Each task ends by reporting done + a suggested commit message.
- Build/test through Tuist entry points: `tuist generate --no-open`, `tuist build`, `tuist test`.
- All UI strings localized in **en and hu** via `Application/Resources/{en,hu}.lproj/Localizable.strings`; string keys use **underscore style** (like the skeleton's existing `language_code_en`), which the stencil camelizes into accessors (`tab_today` → `Keys.tabToday`).
- `Toolkit` dependency is removed; Alamofire/Lottie/Swinject/Logging stay linked (unused, out of scope).
- Exact MagniTools semantics (spec §Business rules): `end == nil` ⇔ clocked in; at most one open session; presence = Σ `(end ?? now) − start`; net = `max(0, presence − lunch)`; target = `work + lunch`; overtime shown only when positive or (negative && day ended); signed monthly sums; no midnight split; no `end > start` validation; punches keep real seconds; settings whole minutes; widget clock-out always ends the day.
- Durations internally are `TimeInterval` seconds; backup JSON uses epoch **milliseconds** (MagniTools compatibility).
- Modern Swift only: async/await, actors, @Observable; no Combine, no completion-handler callbacks.
- App Group id: `group.hu.paydogs.overtimeoverview`.

## Review Focus

Five input classes the spec implies but individual tasks might not exercise — each pinned by the named test:

1. **A session crossing midnight** belongs to its start day and keeps accumulating — `WorktimeMathTests.testMidnightCrossingSessionStaysInStartDay` (Task 4).
2. **DST boundary days** (Europe/Budapest, last Sunday of October) must still group by local midnight — `WorktimeMathTests.testDSTDayBoundary` (Task 4).
3. **Locale like `hu_HU`/`hu-HU` must resolve to `.hu`** and missing keys must fall back to the base language — `LocalizationTests.testDetectsHungarianFromLocale` / `testMissingKeyFallsBackToBaseLanguage` (Task 2).
4. **`endedDayStart` from yesterday is not "ended today"** — `WorktimeSettingsTests.testEndedMarkerFromYesterdayIsNotEndedToday` (Task 5).
5. **Merge import appends duplicates without dedup; replace wipes first** — `BackupManagerTests.testMergeAppendsWithoutDedup` / `testReplaceWipesExisting` (Task 6).

---

### Task 1: Project hygiene — iOS 17 bump, remove Toolkit, AppDelegate logging

**Files:**
- Modify: `OvertimeOverview/Project.swift`
- Modify: `Tuist/Package.swift`
- Modify: `OvertimeOverview/Application/AppDelegate.swift`

**Interfaces:**
- Consumes: none.
- Produces: all targets at iOS 17.0; `Toolkit` gone; `AppDelegate` logs via `os.Logger`.

- [ ] **Step 1: Bump deployment targets and drop Toolkit in Project.swift**

In `OvertimeOverview/Project.swift` change all three `deploymentTargets: .iOS("16.0")` to `.iOS("17.0")` and remove the line `.external(name: "Toolkit"),` from the app target's `dependencies` array.

- [ ] **Step 2: Drop Toolkit from Tuist/Package.swift**

Remove `"Toolkit": .framework,` from `productTypes` and the line `.package(url: "https://github.com/paydogs/Toolkit", from: "0.1.0"),` (and its trailing comment) from `dependencies`.

- [ ] **Step 3: Replace print with os.Logger and remove dead push residue in AppDelegate.swift**

Replace the whole file content with:

```swift
//
//  AppDelegate.swift
//  OvertimeOverview
//
//  Created by Andras Olah on 2026. 09. 25..
//

import OSLog
import UIKit

final class AppDelegate: NSObject, UIApplicationDelegate {
    private let logger = Logger(subsystem: "hu.paydogs.overtimeoverview", category: "app")

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        logger.debug("didFinishLaunching")
        return true
    }
}
```

- [ ] **Step 4: Regenerate and build**

Run: `tuist generate --no-open && tuist build`
Expected: dependency resolution succeeds without Toolkit; build succeeds.

- [ ] **Step 5: Report done** — suggested message: `chore: bump to iOS 17, drop Toolkit dependency, clean AppDelegate logging`

### Task 2: Localization fixes (app + Tuist stencil) with tests

**Files:**
- Modify: `OvertimeOverview/Application/System/Localization/Localization.swift`
- Modify: `Tuist/Templates/Template/System/Localization/Localization.stencil`
- Modify: `OvertimeOverview/Application/Resources/en.lproj/Localizable.strings`, `hu.lproj/Localizable.strings` (read both first, append lines below; keep existing content)
- Test: `OvertimeOverview/Application/Tests/UnitTests/LocalizationTests.swift`

**Interfaces:**
- Consumes: existing generated `Keys` (stencil `tr` calls `Localization.sharedInstance.translate(key, table)` synchronously — this forces the sync API).
- Produces: `Localization` as a lock-protected `@unchecked Sendable` class; injectable `init(bundle:deviceLanguage:defaults:)`; `LanguageCode` detection from a bare language code.

**Why a lock, not an actor:** the generated `Keys.tr` is a nonisolated sync function, so `translate` cannot be actor-isolated. All mutable state is guarded by `NSLock`, making the class data-race-free; `@unchecked Sendable` is the deliberate isolation choice.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  LocalizationTests.swift
//  OvertimeOverview
//

import Testing
@testable import OvertimeOverview

@MainActor
struct LocalizationTests {
    private func makeDefaults() -> UserDefaults {
        let name = "LocalizationTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func detectsHungarianFromLocale() {
        let defaults = makeDefaults()
        let localization = Localization(
            bundle: Bundle(for: AppDelegate.self),
            deviceLanguage: "hu",
            defaults: defaults
        )
        #expect(localization.currentLanguageCode == .hu)
        #expect(defaults.string(forKey: "savedLanguage") == "hu")
    }

    @Test func unknownLocaleFallsBackToEnglish() {
        let localization = Localization(
            bundle: Bundle(for: AppDelegate.self),
            deviceLanguage: "de",
            defaults: makeDefaults()
        )
        #expect(localization.currentLanguageCode == .en)
    }

    @Test func storedLanguageWins() {
        let defaults = makeDefaults()
        defaults.set("hu", forKey: "savedLanguage")
        let localization = Localization(
            bundle: Bundle(for: AppDelegate.self),
            deviceLanguage: "en",
            defaults: defaults
        )
        #expect(localization.currentLanguageCode == .hu)
    }

    @Test func missingKeyFallsBackToBaseLanguage() {
        let defaults = makeDefaults()
        let localization = Localization(
            bundle: Bundle(for: AppDelegate.self),
            deviceLanguage: "hu",
            defaults: defaults
        )
        // "test_englishOnly" exists in en.lproj only (added below)
        #expect(localization.translate("test_englishOnly", "Localizable") == "English only string")
        // A key missing everywhere still surfaces the raw key
        #expect(localization.translate("no.such.key", "Localizable") == "no.such.key")
    }
}
```

- [ ] **Step 2: Add the fallback-test string**

Append to `en.lproj/Localizable.strings` only (NOT hu — the missing key is the test):

```
/* Test-only key: exists in English only to verify base-language fallback */
"test_englishOnly" = "English only string";
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `tuist generate --no-open && tuist test --target OvertimeOverviewTests`
Expected: FAIL — `Localization(bundle:deviceLanguage:defaults:)` doesn't exist; `LanguageCode(rawValue: "hu")` from identifier-based detection would also fail.

- [ ] **Step 4: Rewrite Localization.swift**

Replace the whole file with:

```swift
//
//  Localization.swift
//  OvertimeOverview
//
//  Created by Andras Olah on 2026. 09. 25..
//

import Foundation

public enum LanguageCode: String {
    case en
    case hu

    var localizedValue: String {
        switch self {
        case .en: Keys.languageCodeEn
        case .hu: Keys.languageCodeHu
        }
    }
}

/// Sync, lock-protected localization: the generated `Keys.tr` is nonisolated and
/// synchronous, so this cannot be an actor — every mutable state access is
/// guarded by `lock`, which makes the class data-race-free.
public final class Localization: @unchecked Sendable {
    public static let sharedInstance = Localization()

    // MARK: - Privates
    private static let languageKey = "savedLanguage"
    private let bundle: Bundle
    private let lock = NSLock()
    private var _currentLanguageCode: LanguageCode

    // MARK: - Init
    init(
        bundle: Bundle = .module,
        deviceLanguage: String? = Locale.current.language.languageCode,
        defaults: UserDefaults = .standard
    ) {
        self.bundle = bundle
        if let storedLanguage = defaults.string(forKey: Self.languageKey),
           let languageCode = LanguageCode(rawValue: storedLanguage) {
            _currentLanguageCode = languageCode
        } else {
            // Locale.current.identifier is e.g. "hu_HU@calendar=…" and never matches
            // a bare raw value; `language.languageCode` is the bare "hu" / "en".
            let languageCode = LanguageCode(rawValue: deviceLanguage ?? "") ?? .en
            defaults.set(languageCode.rawValue, forKey: Self.languageKey)
            _currentLanguageCode = languageCode
        }
    }
}

public extension Localization {
    var currentLanguageCode: LanguageCode {
        lock.withLock { _currentLanguageCode }
    }

    func setLanguage(_ code: LanguageCode) {
        lock.withLock { _currentLanguageCode = code }
        UserDefaults.standard.set(code.rawValue, forKey: Self.languageKey)
        NotificationCenter.default.post(name: .languageDidChange, object: nil)
    }

    /// Resolve localized string manually
    func translate(_ key: String, _ table: String) -> String {
        let code = lock.withLock { _currentLanguageCode }
        // value: nil makes missing keys fall back to the base-language string
        // instead of surfacing the raw key.
        guard let path = bundle.path(forResource: code.rawValue, ofType: "lproj"),
              let localizedBundle = Bundle(path: path)
        else { return bundle.localizedString(forKey: key, value: nil, table: table) }

        return localizedBundle.localizedString(forKey: key, value: nil, table: table)
    }
}

public extension Notification.Name {
    static let languageDidChange = Notification.Name("Localization.languageDidChange")
}
```

- [ ] **Step 5: Mirror the same fixes into the stencil**

Apply the identical changes to `Tuist/Templates/Template/System/Localization/Localization.stencil` (detection via `deviceLanguage`, `NSLock`, `value: nil`, `set` instead of `setValue`) so future scaffolded apps don't regress. The stencil's `Keys.` references keep their stencil escaping (`{{ }}`-free here — this stencil is plain Swift with generated `Keys`).

- [ ] **Step 6: Run tests to verify they pass**

Run: `tuist generate --no-open && tuist test --target OvertimeOverviewTests`
Expected: PASS (all LocalizationTests green).

- [ ] **Step 7: Report done** — suggested message: `fix: language detection from bare locale code, lock-protected Localization, base-language fallback (+ stencil)`

### Task 3: Domain foundation — model, mapper, store

**Files:**
- Create: `OvertimeOverview/Domain/Models/WorkSession.swift`
- Create: `OvertimeOverview/Domain/Models/WorkSessionModel.swift`
- Create: `OvertimeOverview/Domain/Mappers/WorkSessionMapper.swift`
- Create: `OvertimeOverview/Domain/WorktimeStore.swift`
- Modify: `OvertimeOverview/Project.swift` (app target `sources` gains the Domain glob)
- Test: `OvertimeOverview/Application/Tests/UnitTests/WorktimeStoreTests.swift`

**Interfaces:**
- Consumes: none.
- Produces:
  - `struct WorkSession: Identifiable, Equatable, Sendable { let id: UUID; let start: Date; let end: Date?; var isOpen: Bool; func duration(now: Date) -> TimeInterval }`
  - `struct WorkDay: Identifiable, Equatable, Sendable { let dayStart: Date; let sessions: [WorkSession]; func inOffice(now: Date) -> TimeInterval }`
  - `@Model final class WorkSessionModel { @Attribute(.unique) var id: UUID; var start: Date; var end: Date? }`
  - `@ModelActor actor WorktimeStore` with `static func makeModelContainer() throws -> ModelContainer`, `static func makeInMemoryContainer() throws -> ModelContainer`, `nonisolated static let appGroup = "group.hu.paydogs.overtimeoverview"`, and async methods `openSession() throws -> WorkSession?`, `clockIn(at:)`, `clockOut(at:)`, `update(session:start:end:)`, `delete(session:)`, `deleteAllSessions()`, `insertSession(start:end:)`, `allSessions()`, `allDays(calendar:)`.

- [ ] **Step 1: Add the Domain glob to the app target in Project.swift**

In `OvertimeOverview/Project.swift`, change the app target's sources to:

```swift
    sources: [
        .glob("Application/**/*.swift", excluding: ["Application/Tests/**"]),
        .glob("Domain/**/*.swift")
    ],
```

- [ ] **Step 2: Write the failing tests**

```swift
//
//  WorktimeStoreTests.swift
//  OvertimeOverview
//

import SwiftData
import Testing
@testable import OvertimeOverview

struct WorktimeStoreTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest")!
        return calendar
    }()

    /// 2026-09-23 09:12:30 local (Budapest).
    static func date(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 23, month: Int = 9) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func makeStore() throws -> WorktimeStore {
        WorktimeStore(modelContainer: try WorktimeStore.makeInMemoryContainer())
    }

    @Test func clockInWhileOpenIsNoop() async throws {
        let store = try makeStore()
        try await store.clockIn(at: Self.date(9, 12))
        try await store.clockIn(at: Self.date(11, 0))
        let all = try await store.allSessions()
        #expect(all.count == 1)
    }

    @Test func clockOutWhileClosedIsNoop() async throws {
        let store = try makeStore()
        try await store.clockOut(at: Self.date(9, 12))
        #expect(try await store.allSessions().isEmpty)
    }

    @Test func singleOpenSessionInvariant() async throws {
        let store = try makeStore()
        try await store.clockIn(at: Self.date(9, 12))
        let open = try await store.openSession()
        #expect(open?.isOpen == true)
        try await store.clockOut(at: Self.date(17, 30))
        #expect(try await store.openSession() == nil)
    }

    @Test func allDaysGroupsByStartDayNewestFirst() async throws {
        let store = try makeStore()
        try await store.clockIn(at: Self.date(8, 0)); try await store.clockOut(at: Self.date(9, 0))
        try await store.clockIn(at: Self.date(9, 12)); try await store.clockOut(at: Self.date(12, 45))
        try await store.clockIn(at: Self.date(13, 0)); // stays open — presence keeps growing
        let days = try await store.allDays(calendar: Self.calendar)
        #expect(days.count == 1)
        #expect(days[0].sessions.count == 3)
        #expect(days[0].sessions.map(\.start) == days[0].sessions.map(\.start).sorted())
    }

    @Test func updateMovesSessionToAnotherDay() async throws {
        let store = try makeStore()
        try await store.clockIn(at: Self.date(9, 12)); try await store.clockOut(at: Self.date(17, 0))
        let session = try await store.allSessions()[0]
        try await store.update(session: session, start: Self.date(9, 0, day: 22), end: Self.date(17, 0, day: 22))
        let days = try await store.allDays(calendar: Self.calendar)
        #expect(days.count == 1)
        #expect(Self.calendar.isDate(days[0].dayStart, inSameDayAs: Self.date(9, 0, day: 22)))
    }

    @Test func deleteRemovesSession() async throws {
        let store = try makeStore()
        try await store.clockIn(at: Self.date(9, 12)); try await store.clockOut(at: Self.date(17, 0))
        let session = try await store.allSessions()[0]
        try await store.delete(session: session)
        #expect(try await store.allSessions().isEmpty)
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `tuist generate --no-open && tuist test --target OvertimeOverviewTests`
Expected: FAIL — Domain types don't exist (build error).

- [ ] **Step 4: Create the domain model and mapper**

`OvertimeOverview/Domain/Models/WorkSession.swift`:

```swift
//
//  WorkSession.swift
//  OvertimeOverview
//

import Foundation

/// A single office visit. `end` is nil while it's still in progress.
struct WorkSession: Identifiable, Equatable, Sendable {
    let id: UUID
    let start: Date
    let end: Date?

    var isOpen: Bool { end == nil }
    func duration(now: Date) -> TimeInterval { (end ?? now).timeIntervalSince(start) }
}

/// A calendar day with the time segments that belong to it. A session belongs to
/// the day it started in, even if it spans midnight.
struct WorkDay: Identifiable, Equatable, Sendable {
    let dayStart: Date
    let sessions: [WorkSession]

    var id: Date { dayStart }
    func inOffice(now: Date) -> TimeInterval { sessions.reduce(0) { $0 + $1.duration(now: now) } }
}
```

`OvertimeOverview/Domain/Models/WorkSessionModel.swift`:

```swift
//
//  WorkSessionModel.swift
//  OvertimeOverview
//

import Foundation
import SwiftData

@Model
final class WorkSessionModel {
    @Attribute(.unique) var id: UUID
    var start: Date
    var end: Date?

    init(id: UUID = UUID(), start: Date, end: Date? = nil) {
        self.id = id
        self.start = start
        self.end = end
    }
}
```

`OvertimeOverview/Domain/Mappers/WorkSessionMapper.swift`:

```swift
//
//  WorkSessionMapper.swift
//  OvertimeOverview
//

import Foundation

/// The only place that maps between persistence and domain models.
enum WorkSessionMapper {
    static func toDomain(_ model: WorkSessionModel) -> WorkSession {
        WorkSession(id: model.id, start: model.start, end: model.end)
    }

    static func apply(_ session: WorkSession, to model: WorkSessionModel) {
        model.start = session.start
        model.end = session.end
    }
}
```

- [ ] **Step 5: Create the store**

`OvertimeOverview/Domain/WorktimeStore.swift`:

```swift
//
//  WorktimeStore.swift
//  OvertimeOverview
//

import Foundation
import SwiftData

@ModelActor
actor WorktimeStore {
    nonisolated static let appGroup = "group.hu.paydogs.overtimeoverview"

    nonisolated static func makeModelContainer() throws -> ModelContainer {
        // App Group when the entitlement is present, otherwise a plain local store
        // (unit tests, previews).
        if let groupURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroup
        ) {
            let configuration = ModelConfiguration(
                url: groupURL.appendingPathComponent("worktime.sqlite")
            )
            return try ModelContainer(for: WorkSessionModel.self, configurations: configuration)
        }
        return try ModelContainer(for: WorkSessionModel.self)
    }

    nonisolated static func makeInMemoryContainer() throws -> ModelContainer {
        try ModelContainer(
            for: WorkSessionModel.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func openSessionModel() throws -> WorkSessionModel? {
        var descriptor = FetchDescriptor<WorkSessionModel>(predicate: #Predicate { $0.end == nil })
        descriptor.fetchLimit = 1
        return try modelContext.fetch(descriptor).first
    }

    func openSession() throws -> WorkSession? {
        try openSessionModel().map(WorkSessionMapper.toDomain)
    }

    func clockIn(at date: Date) throws {
        guard try openSessionModel() == nil else { return }
        modelContext.insert(WorkSessionModel(start: date, end: nil))
        try modelContext.save()
    }

    func clockOut(at date: Date) throws {
        guard let open = try openSessionModel() else { return }
        open.end = date
        try modelContext.save()
    }

    func update(session: WorkSession, start: Date, end: Date?) throws {
        let id = session.id
        guard let model = try modelContext.fetch(
            FetchDescriptor<WorkSessionModel>(predicate: #Predicate { $0.id == id })
        ).first else { return }
        WorkSessionMapper.apply(WorkSession(id: id, start: start, end: end), to: model)
        try modelContext.save()
    }

    func delete(session: WorkSession) throws {
        let id = session.id
        guard let model = try modelContext.fetch(
            FetchDescriptor<WorkSessionModel>(predicate: #Predicate { $0.id == id })
        ).first else { return }
        modelContext.delete(model)
        try modelContext.save()
    }

    func deleteAllSessions() throws {
        try modelContext.delete(model: WorkSessionModel.self)
        try modelContext.save()
    }

    func insertSession(start: Date, end: Date?) throws {
        modelContext.insert(WorkSessionModel(start: start, end: end))
        try modelContext.save()
    }

    func allSessions() throws -> [WorkSession] {
        try modelContext.fetch(
            FetchDescriptor<WorkSessionModel>(sortBy: [SortDescriptor(\.start)])
        ).map(WorkSessionMapper.toDomain)
    }

    /// All days newest first, sessions chronological within a day. Day grouping
    /// is derived from each session's start — never stored, never split at midnight.
    func allDays(calendar: Calendar) throws -> [WorkDay] {
        WorktimeMath.groupSessions(try allSessions(), calendar: calendar)
    }
}
```

Note: `allDays` calls `WorktimeMath.groupSessions`, implemented in Task 4. Implement that single function now as part of this task (see Task 4 Step 4 for the full file; the function is):

```swift
static func groupSessions(_ sessions: [WorkSession], calendar: Calendar) -> [WorkDay] {
    let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.start) }
    return grouped
        .map { WorkDay(dayStart: $0.key, sessions: $0.value.sorted { $0.start < $1.start }) }
        .sorted { $0.dayStart > $1.dayStart }
}
```

Put it in `OvertimeOverview/Domain/WorktimeMath.swift` now (Task 4 fills in the rest of that enum).

- [ ] **Step 6: Run tests to verify they pass**

Run: `tuist generate --no-open && tuist test --target OvertimeOverviewTests`
Expected: PASS — all WorktimeStoreTests green.

- [ ] **Step 7: Report done** — suggested message: `feat: SwiftData-backed WorktimeStore with derived day grouping`

### Task 4: WorktimeMath + Formatters — the exact business rules

**Files:**
- Modify: `OvertimeOverview/Domain/WorktimeMath.swift` (extend the enum created in Task 3)
- Create: `OvertimeOverview/Domain/Formatters.swift`
- Modify: `Application/Resources/en.lproj/Localizable.strings`, `hu.lproj/Localizable.strings`
- Test: `OvertimeOverview/Application/Tests/UnitTests/WorktimeMathTests.swift`

**Interfaces:**
- Consumes: `WorkSession`, `WorkDay` (Task 3).
- Produces (all `static`, on `enum WorktimeMath` unless noted):
  - `func startOfDay(_ date: Date, calendar: Calendar) -> Date`
  - `func startOfMonth(_ date: Date, calendar: Calendar) -> Date`
  - `func groupSessions(_:calendar:) -> [WorkDay]` (from Task 3)
  - `func todaysSessions(_ sessions: [WorkSession], now: Date, calendar: Calendar) -> [WorkSession]`
  - `func presence(_ sessions: [WorkSession], now: Date) -> TimeInterval`
  - `func netWorktime(presence: TimeInterval, lunch: TimeInterval) -> TimeInterval`
  - `func showsOvertime(overtime: TimeInterval, dayEnded: Bool) -> Bool`
  - `func projectedFinish(now: Date, presence: TimeInterval, target: TimeInterval) -> Date`
  - `func monthOvertime(netPerDay: [TimeInterval], workPerDay: TimeInterval) -> TimeInterval`
  - `func historyCandidates(days: [WorkDay], now: Date, dayEnded: Bool, calendar: Calendar) -> [WorkDay]`
  - `func groupByMonth(_ days: [WorkDay], calendar: Calendar) -> [(monthStart: Date, days: [WorkDay])]`
  - `func punchDate(onDay:hour:minute:second:calendar:) -> Date`
  - `enum TodayStatus: Equatable { case atOffice(since: Date), doneForToday, onBreak, notAtOffice }` + `func status(todayPresence: TimeInterval, openSession: WorkSession?, dayEnded: Bool) -> TodayStatus`
  - `func clockInLabel(todayPresence: TimeInterval, dayEnded: Bool) -> Bool` (true = "Clock back in", false = "Clock in")
  - `enum Formatters`: `clock(_:) -> String` ("HH:mm"), `clockWithSeconds(_:)`, `elapsed(_ interval: TimeInterval) -> String` ("H:MM:SS"), `duration(_:) -> String` (localized "7h 32m"), `shortDuration(_:) -> String` (localized "25 min" under an hour, else `duration`), `month(_:)`, `weekdayDay(_:)`, `dateTime(_:)`, `exportStamp(_:)`.

- [ ] **Step 1: Add the duration format strings**

Append to `en.lproj/Localizable.strings`:

```
/* Duration in hours and minutes, e.g. 7h 32m */
"format_hoursMinutes" = "%1$dh %2$dm";
/* Duration under an hour in minutes, e.g. 25 min */
"format_minutes" = "%d min";
```

Append to `hu.lproj/Localizable.strings`:

```
/* Duration in hours and minutes, e.g. 7ó 32p */
"format_hoursMinutes" = "%1$dó %2$dp";
/* Duration under an hour in minutes, e.g. 25 perc */
"format_minutes" = "%d perc";
```

- [ ] **Step 2: Write the failing tests**

```swift
//
//  WorktimeMathTests.swift
//  OvertimeOverview
//

import Testing
@testable import OvertimeOverview

struct WorktimeMathTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest")!
        return calendar
    }()

    static func date(_ hour: Int, _ minute: Int, _ second: Int = 0, day: Int = 23, month: Int = 9, year: Int = 2026) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    static func session(_ start: Date, _ end: Date?) -> WorkSession {
        WorkSession(id: UUID(), start: start, end: end)
    }

    // Review Focus 1: a session crossing midnight stays in its start day.
    @Test func midnightCrossingSessionStaysInStartDay() {
        let start = Self.date(22, 0, day: 23)
        let crossing = Self.session(start, Self.date(2, 0, day: 24))
        let days = WorktimeMath.groupSessions([crossing], calendar: Self.calendar)
        #expect(days.count == 1)
        #expect(Self.calendar.isDate(days[0].dayStart, inSameDayAs: start))
    }

    // Review Focus 2: DST end (2026-10-25, 03:00 → 02:00 in Budapest) still
    // groups both sessions into their local midnights.
    @Test func dstDayBoundary() {
        let before = Self.session(Self.date(1, 0, day: 25, month: 10), nil)
        let after = Self.session(Self.date(4, 0, day: 25, month: 10), nil)
        let days = WorktimeMath.groupSessions([before, after], calendar: Self.calendar)
        #expect(days.count == 1)
        #expect(Self.calendar.isDate(days[0].dayStart, inSameDayAs: Self.date(1, 0, day: 25, month: 10)))
    }

    @Test func netWorktimeNeverNegative() {
        #expect(WorktimeMath.netWorktime(presence: 1200, lunch: 1800) == 0)
        #expect(WorktimeMath.netWorktime(presence: 3600, lunch: 1800) == 1800)
    }

    @Test func overtimeDisplayGating() {
        #expect(WorktimeMath.showsOvertime(overtime: 300, dayEnded: false))
        #expect(!WorktimeMath.showsOvertime(overtime: -300, dayEnded: false))
        #expect(WorktimeMath.showsOvertime(overtime: -300, dayEnded: true))
        #expect(!WorktimeMath.showsOvertime(overtime: 0, dayEnded: true))
    }

    @Test func projectedFinishAddsRemaining() {
        let now = Self.date(12, 0)
        let finish = WorktimeMath.projectedFinish(now: now, presence: 3 * 3600, target: 8 * 3600)
        #expect(finish == now.addingTimeInterval(5 * 3600))
    }

    @Test func monthOvertimeIsSigned() {
        // Two days: +1h and -30m net against an 8h target → +30m month overtime
        let monthOvertime = WorktimeMath.monthOvertime(netPerDay: [9 * 3600, 7.5 * 3600], workPerDay: 8 * 3600)
        #expect(monthOvertime == 1800)
    }

    @Test func historyCandidatesExcludesTodayUnlessEnded() {
        let today = Self.date(12, 0, day: 23)
        let yesterday = Self.date(12, 0, day: 22)
        let days = [
            WorkDay(dayStart: Self.calendar.startOfDay(for: today), sessions: []),
            WorkDay(dayStart: Self.calendar.startOfDay(for: yesterday), sessions: []),
        ]
        let notEnded = WorktimeMath.historyCandidates(days: days, now: today, dayEnded: false, calendar: Self.calendar)
        #expect(notEnded.count == 1)
        let ended = WorktimeMath.historyCandidates(days: days, now: today, dayEnded: true, calendar: Self.calendar)
        #expect(ended.count == 2)
    }

    @Test func groupByMonthSortsNewestFirst() {
        let aug = WorkDay(dayStart: Self.date(1, 0, day: 1, month: 8), sessions: [])
        let sep = WorkDay(dayStart: Self.date(1, 0, day: 1, month: 9), sessions: [])
        let groups = WorktimeMath.groupByMonth([aug, sep], calendar: Self.calendar)
        #expect(groups.count == 2)
        #expect(Self.calendar.isDate(groups[0].monthStart, inSameDayAs: sep.dayStart))
    }

    @Test func punchDateKeepsSeconds() {
        let day = Self.calendar.startOfDay(for: Self.date(12, 0, day: 23))
        let punched = WorktimeMath.punchDate(onDay: day, hour: 9, minute: 12, second: 34, calendar: Self.calendar)
        let comps = Self.calendar.dateComponents([.hour, .minute, .second], from: punched)
        #expect(comps.hour == 9 && comps.minute == 12 && comps.second == 34)
    }

    @Test func statusTransitions() {
        let open = Self.session(Self.date(9, 12), nil)
        #expect(WorktimeMath.status(todayPresence: 3600, openSession: open, dayEnded: false) == .atOffice(since: open.start))
        #expect(WorktimeMath.status(todayPresence: 3600, openSession: nil, dayEnded: true) == .doneForToday)
        #expect(WorktimeMath.status(todayPresence: 3600, openSession: nil, dayEnded: false) == .onBreak)
        #expect(WorktimeMath.status(todayPresence: 0, openSession: nil, dayEnded: false) == .notAtOffice)
    }

    @Test func clockInLabelVariants() {
        #expect(WorktimeMath.clockInLabel(todayPresence: 3600, dayEnded: false) == true)  // "Clock back in"
        #expect(WorktimeMath.clockInLabel(todayPresence: 3600, dayEnded: true) == false)   // ended → "Clock in"
        #expect(WorktimeMath.clockInLabel(todayPresence: 0, dayEnded: false) == false)     // fresh → "Clock in"
    }

    @Test func formatterShapes() {
        #expect(Formatters.elapsed(7 * 3600 + 32 * 60 + 10) == "7:32:10")
        #expect(Formatters.duration(-(2 * 3600 + 5 * 60)).hasPrefix("-"))
        #expect(Formatters.shortDuration(25 * 60).contains("25"))
        #expect(Formatters.shortDuration(75 * 60).contains("h"))
    }
}
```

- [ ] **Step 3: Run tests to verify they fail**

Run: `tuist generate --no-open && tuist test --target OvertimeOverviewTests`
Expected: FAIL — most `WorktimeMath` functions and all `Formatters` don't exist.

- [ ] **Step 4: Implement WorktimeMath**

Complete `OvertimeOverview/Domain/WorktimeMath.swift`:

```swift
//
//  WorktimeMath.swift
//  OvertimeOverview
//

import Foundation

/// Pure MagniTools-parity business rules. No state, no side effects —
/// views and the widget share these.
enum WorktimeMath {
    static func startOfDay(_ date: Date, calendar: Calendar) -> Date {
        calendar.startOfDay(for: date)
    }

    static func startOfMonth(_ date: Date, calendar: Calendar) -> Date {
        calendar.date(from: calendar.dateComponents([.year, .month], from: date))!
    }

    static func groupSessions(_ sessions: [WorkSession], calendar: Calendar) -> [WorkDay] {
        let grouped = Dictionary(grouping: sessions) { calendar.startOfDay(for: $0.start) }
        return grouped
            .map { WorkDay(dayStart: $0.key, sessions: $0.value.sorted { $0.start < $1.start }) }
            .sorted { $0.dayStart > $1.dayStart }
    }

    static func todaysSessions(_ sessions: [WorkSession], now: Date, calendar: Calendar) -> [WorkSession] {
        let dayStart = calendar.startOfDay(for: now)
        return sessions.filter { $0.start >= dayStart }.sorted { $0.start > $1.start }
    }

    static func presence(_ sessions: [WorkSession], now: Date) -> TimeInterval {
        sessions.reduce(0) { $0 + $1.duration(now: now) }
    }

    static func netWorktime(presence: TimeInterval, lunch: TimeInterval) -> TimeInterval {
        max(0, presence - lunch)
    }

    static func showsOvertime(overtime: TimeInterval, dayEnded: Bool) -> Bool {
        overtime > 0 || (overtime < 0 && dayEnded)
    }

    static func projectedFinish(now: Date, presence: TimeInterval, target: TimeInterval) -> Date {
        now.addingTimeInterval(target - presence)
    }

    static func monthOvertime(netPerDay: [TimeInterval], workPerDay: TimeInterval) -> TimeInterval {
        netPerDay.reduce(0) { $0 + ($1 - workPerDay) }
    }

    /// Past days, plus today only when the day has been marked ended.
    static func historyCandidates(days: [WorkDay], now: Date, dayEnded: Bool, calendar: Calendar) -> [WorkDay] {
        let today = calendar.startOfDay(for: now)
        return days.filter { $0.dayStart < today || ($0.dayStart == today && dayEnded) }
    }

    static func groupByMonth(_ days: [WorkDay], calendar: Calendar) -> [(monthStart: Date, days: [WorkDay])] {
        let grouped = Dictionary(grouping: days) { startOfMonth($0.dayStart, calendar: calendar) }
        return grouped
            .map { (monthStart: $0.key, days: $0.value.sorted { $0.dayStart > $1.dayStart }) }
            .sorted { $0.monthStart > $1.monthStart }
    }

    static func punchDate(onDay day: Date, hour: Int, minute: Int, second: Int, calendar: Calendar) -> Date {
        var components = calendar.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        components.second = second
        return calendar.date(from: components)!
    }

    enum TodayStatus: Equatable {
        case atOffice(since: Date)
        case doneForToday
        case onBreak
        case notAtOffice
    }

    static func status(todayPresence: TimeInterval, openSession: WorkSession?, dayEnded: Bool) -> TodayStatus {
        if let open = openSession { return .atOffice(since: open.start) }
        if dayEnded { return .doneForToday }
        if todayPresence > 0 { return .onBreak }
        return .notAtOffice
    }

    /// true → "Clock back in" (there is time today and the day isn't ended),
    /// false → "Clock in" (fresh day, or ended for today).
    static func clockInLabel(todayPresence: TimeInterval, dayEnded: Bool) -> Bool {
        todayPresence > 0 && !dayEnded
    }
}
```

- [ ] **Step 5: Implement Formatters**

`OvertimeOverview/Domain/Formatters.swift`:

```swift
//
//  Formatters.swift
//  OvertimeOverview
//

import Foundation

/// Display formatting. Cached formatters are used only from the main thread
/// (DateFormatter is not Sendable); elapsed() is pure arithmetic.
enum Formatters {
    private static let clockFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static let clockWithSecondsFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("LLLL yyyy")
        return formatter
    }()

    private static let weekdayDayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE, MMM d")
        return formatter
    }()

    private static let dateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }()

    private static let exportStampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH-mm"
        return formatter
    }()

    static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }
    static func clockWithSeconds(_ date: Date) -> String { clockWithSecondsFormatter.string(from: date) }
    static func month(_ date: Date) -> String { monthFormatter.string(from: date) }
    static func weekdayDay(_ date: Date) -> String { weekdayDayFormatter.string(from: date) }
    static func dateTime(_ date: Date) -> String { dateTimeFormatter.string(from: date) }
    static func exportStamp(_ date: Date) -> String { exportStampFormatter.string(from: date) }

    /// Live elapsed duration, e.g. "7:32:10". Truncates to whole seconds.
    static func elapsed(_ interval: TimeInterval) -> String {
        let totalSeconds = max(0, Int(interval))
        return String(format: "%d:%02d:%02d", totalSeconds / 3600, (totalSeconds % 3600) / 60, totalSeconds % 60)
    }

    /// Whole-minute duration, e.g. "7h 32m", sign-prefixed when negative.
    static func duration(_ interval: TimeInterval) -> String {
        let sign = interval < 0 ? "-" : ""
        let totalMinutes = Int(abs(interval) / 60)
        return sign + String(format: Keys.formatHoursMinutes, totalMinutes / 60, totalMinutes % 60)
    }

    /// Under an hour → localized whole minutes ("25 min"); otherwise `duration`.
    static func shortDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(abs(interval) / 60)
        guard minutes < 60 else { return duration(interval) }
        let sign = interval < 0 ? "-" : ""
        return sign + String(format: Keys.formatMinutes, minutes)
    }
}
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `tuist generate --no-open && tuist test --target OvertimeOverviewTests`
Expected: PASS.

- [ ] **Step 7: Report done** — suggested message: `feat: worktime business rules and formatters (MagniTools parity)`

### Task 5: WorktimeSettings

**Files:**
- Create: `OvertimeOverview/Domain/WorktimeSettings.swift`
- Test: `OvertimeOverview/Application/Tests/UnitTests/WorktimeSettingsTests.swift`

**Interfaces:**
- Consumes: `WorktimeStore.appGroup` (Task 3).
- Produces: `@MainActor @Observable final class WorktimeSettings` with `static let shared`, injectable `init(defaults:)`, `private(set) var workSeconds/lunchSeconds: TimeInterval` (defaults 8h / 30m), `var officeTarget: TimeInterval`, `updateWork(minutes:)`, `updateLunch(minutes:)`, `markEndedToday(now:calendar:)`, `clearEnded()`, `endedToday(now:calendar:) -> Bool`, `importState(work:lunch:endedDayStart:)`.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  WorktimeSettingsTests.swift
//  OvertimeOverview
//

import Testing
@testable import OvertimeOverview

@MainActor
struct WorktimeSettingsTests {
    static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Budapest")!
        return calendar
    }()

    private func makeSettings() -> WorktimeSettings {
        let name = "WorktimeSettingsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return WorktimeSettings(defaults: defaults)
    }

    @Test func defaults() {
        let settings = makeSettings()
        #expect(settings.workSeconds == 8 * 3600)
        #expect(settings.lunchSeconds == 30 * 60)
        #expect(settings.officeTarget == 8 * 3600 + 30 * 60)
    }

    @Test func updateWholeMinutes() {
        let settings = makeSettings()
        settings.updateWork(minutes: 90)
        #expect(settings.workSeconds == 5400)
    }

    // Review Focus 4: a marker set yesterday must not count as ended today.
    @Test func endedMarkerFromYesterdayIsNotEndedToday() {
        let settings = makeSettings()
        let yesterday = Self.calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 23, hour: 18)
        )!
        let today = Self.calendar.date(
            from: DateComponents(year: 2026, month: 9, day: 24, hour: 9)
        )!
        settings.markEndedToday(now: yesterday, calendar: Self.calendar)
        #expect(settings.endedToday(now: today, calendar: Self.calendar) == false)
        #expect(settings.endedToday(now: yesterday, calendar: Self.calendar) == true)
    }

    @Test func clearEnded() {
        let settings = makeSettings()
        settings.markEndedToday(calendar: Self.calendar)
        settings.clearEnded()
        #expect(settings.endedToday(calendar: Self.calendar) == false)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `tuist generate --no-open && tuist test --target OvertimeOverviewTests`
Expected: FAIL — `WorktimeSettings` doesn't exist.

- [ ] **Step 3: Implement**

`OvertimeOverview/Domain/WorktimeSettings.swift`:

```swift
//
//  WorktimeSettings.swift
//  OvertimeOverview
//

import Foundation
import Observation

/// workSeconds is the work you owe; lunchSeconds is added on top for the
/// presence target and deducted from presence for net worktime.
/// endedDayStart marks a day finished (break vs. clocking out for good).
@MainActor
@Observable
final class WorktimeSettings {
    static let shared = WorktimeSettings()

    static let workKey = "work_seconds"
    static let lunchKey = "lunch_seconds"
    static let endedKey = "ended_day_start"
    static let defaultWork: TimeInterval = 8 * 3600
    static let defaultLunch: TimeInterval = 30 * 60

    private let defaults: UserDefaults
    private(set) var workSeconds: TimeInterval
    private(set) var lunchSeconds: TimeInterval
    private(set) var endedDayStart: Date?

    var officeTarget: TimeInterval { workSeconds + lunchSeconds }

    init(defaults: UserDefaults = UserDefaults(suiteName: WorktimeStore.appGroup) ?? .standard) {
        self.defaults = defaults
        workSeconds = defaults.object(forKey: Self.workKey) as? Double ?? Self.defaultWork
        lunchSeconds = defaults.object(forKey: Self.lunchKey) as? Double ?? Self.defaultLunch
        endedDayStart = defaults.object(forKey: Self.endedKey) as? Date
    }

    func updateWork(minutes: Int) {
        workSeconds = Double(minutes) * 60
        defaults.set(workSeconds, forKey: Self.workKey)
    }

    func updateLunch(minutes: Int) {
        lunchSeconds = Double(minutes) * 60
        defaults.set(lunchSeconds, forKey: Self.lunchKey)
    }

    /// Marks today as finished ("Clock out for today" / widget clock-out).
    func markEndedToday(now: Date = Date(), calendar: Calendar = .current) {
        endedDayStart = calendar.startOfDay(for: now)
        defaults.set(endedDayStart, forKey: Self.endedKey)
    }

    /// Clears the end-of-day marker (clock-in, break clock-out).
    func clearEnded() {
        endedDayStart = nil
        defaults.removeObject(forKey: Self.endedKey)
    }

    func endedToday(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        guard let ended = endedDayStart else { return false }
        return calendar.startOfDay(for: ended) == calendar.startOfDay(for: now)
    }

    /// Restores all settings at once (backup import).
    func importState(work: TimeInterval, lunch: TimeInterval, endedDayStart: Date?) {
        workSeconds = work
        lunchSeconds = lunch
        self.endedDayStart = endedDayStart
        defaults.set(work, forKey: Self.workKey)
        defaults.set(lunch, forKey: Self.lunchKey)
        defaults.set(endedDayStart, forKey: Self.endedKey)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `tuist generate --no-open && tuist test --target OvertimeOverviewTests`
Expected: PASS.

- [ ] **Step 5: Report done** — suggested message: `feat: WorktimeSettings (work/lunch targets, end-of-day marker)`

### Task 6: BackupManager — MagniTools-compatible JSON

**Files:**
- Create: `OvertimeOverview/Domain/Mappers/BackupSessionMapper.swift`
- Test: `OvertimeOverview/Application/Tests/UnitTests/BackupManagerTests.swift`

**Interfaces:**
- Consumes: `WorkSession`, `WorktimeSettings` (Task 5), `Formatters`.
- Produces:
  - `struct BackupSessionDTO: Codable { start: Int64; end: Int64?; startText: String?; endText: String? }` (epoch ms)
  - `struct BackupSettingsDTO: Codable { workMillis: Int64?; lunchMillis: Int64?; endedDayStart: Int64? }`
  - `struct BackupDocument: Codable { app, version: Int, exportedAt: String, settings: BackupSettingsDTO?, worktime: [BackupSessionDTO]?, sessions: [BackupSessionDTO]? }`
  - `enum BackupManager` with `static func parse(_ data: Data) throws -> ParsedBackup`, `static func makeDocument(sessions:settings:now:) -> BackupDocument`, `static func encode(_:) throws -> Data`, `struct ParsedBackup { sessions: [(start: Date, end: Date?)]; settings: BackupSettingsDTO? }`, `static let formatVersion = 3`.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  BackupManagerTests.swift
//  OvertimeOverview
//

import Testing
@testable import OvertimeOverview

struct BackupManagerTests {
    private static let budapest = TimeZone(identifier: "Europe/Budapest")!

    /// A real MagniTools v3 export: dotted keys, millis timestamps, legacy top-level "sessions" absent.
    private static let magnitoolsJSON = """
    {
      "app": "MagniTools",
      "version": 3,
      "exportedAt": "2026-06-05 14:30:00",
      "settings": { "workMillis": 28800000, "lunchMillis": 1800000, "endedDayStart": 0 },
      "worktime": [
        { "start": 1748179200000, "end": 1748208000000,
          "startText": "2026-05-25 10:00:00", "endText": "2026-05-25 18:00:00" },
        { "start": 1748445600000, "end": null,
          "startText": "2026-05-28 12:00:00", "endText": null }
      ]
    }
    """

    @Test func parsesMagnitoolsV3() throws {
        let parsed = try BackupManager.parse(Data(Self.magnitoolsJSON.utf8))
        #expect(parsed.sessions.count == 2)
        #expect(parsed.sessions[0].start == Date(timeIntervalSince1970: 1_748_179_200))
        #expect(parsed.sessions[1].end == nil)
        #expect(parsed.settings?.workMillis == 28_800_000)
    }

    @Test func parsesLegacyTopLevelSessions() throws {
        let legacy = """
        { "app": "MagniTools", "version": 1, "exportedAt": "2026-01-01 09:00:00",
          "sessions": [ { "start": 1748179200000, "end": 1748208000000 } ] }
        """
        let parsed = try BackupManager.parse(Data(legacy.utf8))
        #expect(parsed.sessions.count == 1)
    }

    @Test func roundTrip() throws {
        let session = WorkSession(id: UUID(), start: Date(timeIntervalSince1970: 1_000), end: nil)
        let document = BackupManager.makeDocument(
            sessions: [session],
            settings: BackupSettingsDTO(workMillis: 28_800_000, lunchMillis: 1_800_000, endedDayStart: nil),
            now: Date(timeIntervalSince1970: 100)
        )
        let data = try BackupManager.encode(document)
        let parsed = try BackupManager.parse(data)
        #expect(parsed.sessions.count == 1)
        #expect(parsed.sessions[0].start == session.start)
        #expect(parsed.sessions[0].end == nil)
    }

    // Review Focus 5: merge appends without dedup; replace wipes first.
    // These exercise the store operations BackupManager's callers perform;
    // they live here to keep the backup contract in one place.
    @Test func mergeAppendAndReplaceWipe() async throws {
        let store = WorktimeStore(modelContainer: try WorktimeStore.makeInMemoryContainer())
        try await store.insertSession(start: Date(timeIntervalSince1970: 0), end: Date(timeIntervalSince1970: 10))
        let parsed = try BackupManager.parse(Data(Self.magnitoolsJSON.utf8))
        // Replace: wipe, then insert all
        try await store.deleteAllSessions()
        for session in parsed.sessions { try await store.insertSession(start: session.start, end: session.end) }
        #expect(try await store.allSessions().count == 2)
        // Merge: append without dedup — the same import again doubles the rows
        for session in parsed.sessions { try await store.insertSession(start: session.start, end: session.end) }
        #expect(try await store.allSessions().count == 4)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `tuist generate --no-open && tuist test --target OvertimeOverviewTests`
Expected: FAIL — BackupManager doesn't exist.

- [ ] **Step 3: Implement**

`OvertimeOverview/Domain/Mappers/BackupSessionMapper.swift`:

```swift
//
//  BackupSessionMapper.swift
//  OvertimeOverview
//

import Foundation

/// MagniTools-compatible backup document. Timestamps are epoch milliseconds.
struct BackupSessionDTO: Codable {
    let start: Int64
    let end: Int64?
    let startText: String?
    let endText: String?
}

struct BackupSettingsDTO: Codable {
    var workMillis: Int64?
    var lunchMillis: Int64?
    var endedDayStart: Int64?
}

struct BackupDocument: Codable {
    let app: String
    let version: Int
    let exportedAt: String
    var settings: BackupSettingsDTO?
    var worktime: [BackupSessionDTO]?
    /// Legacy MagniTools key, accepted on import only.
    var sessions: [BackupSessionDTO]?
}

enum BackupManager {
    static let formatVersion = 3

    struct ParsedBackup {
        let sessions: [(start: Date, end: Date?)]
        let settings: BackupSettingsDTO?
    }

    static func parse(_ data: Data) throws -> ParsedBackup {
        let document = try JSONDecoder().decode(BackupDocument.self, from: data)
        let entries = document.worktime ?? document.sessions ?? []
        return ParsedBackup(
            sessions: entries.map {
                (start: Date(timeIntervalSince1970: Double($0.start) / 1000),
                 end: $0.end.map { Date(timeIntervalSince1970: Double($0) / 1000) })
            },
            settings: document.settings
        )
    }

    static func makeDocument(sessions: [WorkSession], settings: BackupSettingsDTO, now: Date) -> BackupDocument {
        BackupDocument(
            app: "OvertimeOverview",
            version: formatVersion,
            exportedAt: Formatters.dateTime(now),
            settings: settings,
            worktime: sessions.map { session in
                BackupSessionDTO(
                    start: Int64(session.start.timeIntervalSince1970 * 1000),
                    end: session.end.map { Int64($0.timeIntervalSince1970 * 1000) },
                    startText: Formatters.dateTime(session.start),
                    endText: session.end.map(Formatters.dateTime)
                )
            },
            sessions: nil
        )
    }

    static func encode(_ document: BackupDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(document)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `tuist generate --no-open && tuist test --target OvertimeOverviewTests`
Expected: PASS.

- [ ] **Step 5: Report done** — suggested message: `feat: MagniTools-compatible backup import/export`

### Task 7: Haptics — settings store + controller

**Files:**
- Create: `OvertimeOverview/Domain/Haptics.swift`
- Test: `OvertimeOverview/Application/Tests/UnitTests/HapticsTests.swift`

**Interfaces:**
- Consumes: `WorktimeStore.appGroup`.
- Produces:
  - `enum HapticPattern: String, CaseIterable, Codable { case single, double, triple, long; var bursts: [UInt]; var pauses: [UInt] }` (MagniTools timing: single 45ms; long 180ms; double 45/[60]/45; triple 40/[55]/40/[55]/40)
  - `struct HapticSettings: Codable { enabled: Bool (true); strength: Double (0.7, 0…1); pattern: HapticPattern (.single) }`
  - `@MainActor @Observable final class HapticsSettingsStore` with `static let shared`, injectable `init(defaults:)`, `private(set) var settings: HapticSettings`, `update(_:)`
  - `@MainActor enum HapticsController` with `static func play(_ settings: HapticSettings)`.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  HapticsTests.swift
//  OvertimeOverview
//

import Testing
@testable import OvertimeOverview

@MainActor
struct HapticsTests {
    @Test func patternTimings() {
        #expect(HapticPattern.single.bursts == [45])
        #expect(HapticPattern.long.bursts == [180])
        #expect(HapticPattern.double.bursts == [45, 45] && HapticPattern.double.pauses == [60])
        #expect(HapticPattern.triple.bursts == [40, 40, 40] && HapticPattern.triple.pauses == [55, 55])
    }

    @Test func settingsPersist() {
        let name = "HapticsTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let store = HapticsSettingsStore(defaults: defaults)
        #expect(store.settings.enabled && store.settings.strength == 0.7)
        store.update(HapticSettings(enabled: false, strength: 0.4, pattern: .long))
        let reloaded = HapticsSettingsStore(defaults: defaults)
        #expect(reloaded.settings.enabled == false)
        #expect(reloaded.settings.strength == 0.4)
        #expect(reloaded.settings.pattern == .long)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `tuist generate --no-open && tuist test --target OvertimeOverviewTests`
Expected: FAIL — types don't exist.

- [ ] **Step 3: Implement**

`OvertimeOverview/Domain/Haptics.swift`:

```swift
//
//  Haptics.swift
//  OvertimeOverview
//

import CoreHaptics
import Foundation
import Observation

enum HapticPattern: String, CaseIterable, Codable {
    case single, double, triple, long

    /// Transient burst durations in ms (MagniTools timings).
    var bursts: [UInt] {
        switch self {
        case .single: [45]
        case .long: [180]
        case .double: [45, 45]
        case .triple: [40, 40, 40]
        }
    }

    /// Pauses between bursts in ms.
    var pauses: [UInt] {
        switch self {
        case .single, .long: []
        case .double: [60]
        case .triple: [55, 55]
        }
    }
}

struct HapticSettings: Codable {
    var enabled = true
    var strength = 0.7
    var pattern: HapticPattern = .single
}

@MainActor
@Observable
final class HapticsSettingsStore {
    static let shared = HapticsSettingsStore()
    private static let key = "haptic_settings"

    private let defaults: UserDefaults
    private(set) var settings: HapticSettings

    init(defaults: UserDefaults = UserDefaults(suiteName: WorktimeStore.appGroup) ?? .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode(HapticSettings.self, from: data) {
            settings = decoded
        } else {
            settings = HapticSettings()
        }
    }

    func update(_ newSettings: HapticSettings) {
        settings = newSettings
        if let data = try? JSONEncoder().encode(newSettings) {
            defaults.set(data, forKey: Self.key)
        }
    }
}

@MainActor
enum HapticsController {
    private static let engine = try? CHHapticEngine()

    static func play(_ settings: HapticSettings) {
        guard settings.enabled,
              CHHapticEngine.capabilitiesForHardware().supportsHaptics,
              let engine
        else { return }

        let intensity = CHHapticEventParameter(
            parameterID: .hapticIntensity, value: Float(settings.strength)
        )
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 1)
        var events: [CHHapticEvent] = []
        var time: TimeInterval = 0
        for (index, burst) in settings.pattern.bursts.enumerated() {
            events.append(
                CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [intensity, sharpness],
                    relativeTime: time
                )
            )
            if index < settings.pattern.pauses.count {
                time += Double(burst) / 1000 + Double(settings.pattern.pauses[index]) / 1000
            }
        }
        guard let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makePlayer(with: pattern)
        else { return }
        try? engine.start()
        try? player.start(atTime: 0)
    }
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `tuist generate --no-open && tuist test --target OvertimeOverviewTests`
Expected: PASS.

- [ ] **Step 5: Report done** — suggested message: `feat: haptic settings and Core Haptics controller`

### Task 8: App shell — AppModel, WorktimeViewModel, TabView

**Files:**
- Create: `OvertimeOverview/Domain/WorktimeViewModel.swift`
- Create: `OvertimeOverview/Application/AppModel.swift`
- Create: `OvertimeOverview/Application/UI/Theme.swift`
- Modify: `OvertimeOverview/Application/UI/ContentView.swift` (TabView)
- Modify: `OvertimeOverview/Application/OvertimeOverviewApp.swift` (inject AppModel, foreground refresh)
- Create: `OvertimeOverview/Support/OvertimeOverview.entitlements`
- Modify: `OvertimeOverview/Project.swift` (entitlements on app target)
- Modify: `Application/Resources/{en,hu}.lproj/Localizable.strings` (tab titles)
- Create placeholders: `OvertimeOverview/Application/UI/TodayView.swift`, `HistoryView.swift`, `SettingsView.swift` (each a stub for this task; filled by Tasks 9–14)
- Test: `OvertimeOverview/Application/Tests/UnitTests/WorktimeViewModelTests.swift`

**Interfaces:**
- Consumes: Tasks 3–7 types.
- Produces:
  - `@MainActor @Observable final class AppModel` with `let store: WorktimeStore`, `let viewModel: WorktimeViewModel`, `let settings: WorktimeSettings`, `let haptics: HapticsSettingsStore`
  - `@MainActor @Observable final class WorktimeViewModel` with `init(store:)`, `private(set) var days: [WorkDay]`, `var openSession: WorkSession?`, `refresh()`, `clockIn(at:)`, `clockOut(at:)`, `update(session:start:end:)`, `delete(session:)`, `todaysSessions(now:) -> [WorkSession]`, `importBackup(data:replace:settings:) async -> Int?`, `exportBackup(settings:) -> Data?`
  - `enum Theme` with `static let brand: LinearGradient`, `static let warm: LinearGradient`
  - `ContentView` = TabView with `TodayView`, `HistoryView`, `SettingsView` injected via `@Environment(AppModel.self)`.

- [ ] **Step 1: Write the failing tests**

```swift
//
//  WorktimeViewModelTests.swift
//  OvertimeOverview
//

import SwiftData
import Testing
@testable import OvertimeOverview

@MainActor
struct WorktimeViewModelTests {
    private func makeViewModel() throws -> WorktimeViewModel {
        WorktimeViewModel(store: WorktimeStore(modelContainer: try WorktimeStore.makeInMemoryContainer()))
    }

    @Test func refreshLoadsDays() async throws {
        let viewModel = try makeViewModel()
        let calendar = Calendar.current
        await viewModel.clockIn(at: calendar.startOfDay(for: Date()).addingTimeInterval(3600))
        #expect(viewModel.days.count == 1)
        #expect(viewModel.openSession?.isOpen == true)
    }

    @Test func importBackupReplacesAndMerges() async throws {
        let viewModel = try makeViewModel()
        let name = "VMBackupTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        let settings = WorktimeSettings(defaults: defaults)
        let json = """
        { "app": "OvertimeOverview", "version": 3, "exportedAt": "2026-01-01 00:00:00",
          "worktime": [ { "start": 1000000, "end": 2000000 } ] }
        """
        // Merge into empty store
        let merged = await viewModel.importBackup(data: Data(json.utf8), replace: false, settings: settings)
        #expect(merged == 1)
        // Replace wipes the 1 existing, inserts 1
        let replaced = await viewModel.importBackup(data: Data(json.utf8), replace: true, settings: settings)
        #expect(replaced == 1)
        #expect(viewModel.days.flatMap(\.sessions).count == 1)
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `tuist generate --no-open && tuist test --target OvertimeOverviewTests`
Expected: FAIL — `WorktimeViewModel` doesn't exist.

- [ ] **Step 3: Implement the view model**

`OvertimeOverview/Domain/WorktimeViewModel.swift`:

```swift
//
//  WorktimeViewModel.swift
//  OvertimeOverview
//

import Foundation
import Observation

@MainActor
@Observable
final class WorktimeViewModel {
    private let store: WorktimeStore

    /// All days with their sessions, newest day first.
    private(set) var days: [WorkDay] = []

    var openSession: WorkSession? {
        days.flatMap(\.sessions).last { $0.isOpen }
    }

    init(store: WorktimeStore) {
        self.store = store
    }

    func refresh() async {
        days = (try? await store.allDays(calendar: .current)) ?? []
    }

    func clockIn(at date: Date) async {
        try? await store.clockIn(at: date)
        await refresh()
    }

    func clockOut(at date: Date) async {
        try? await store.clockOut(at: date)
        await refresh()
    }

    func update(session: WorkSession, start: Date, end: Date?) async {
        try? await store.update(session: session, start: start, end: end)
        await refresh()
    }

    func delete(session: WorkSession) async {
        try? await store.delete(session: session)
        await refresh()
    }

    /// Sessions that started today, newest first.
    func todaysSessions(now: Date = Date()) -> [WorkSession] {
        WorktimeMath.todaysSessions(days.flatMap(\.sessions), now: now, calendar: .current)
    }

    /// Number of imported sessions, nil when the document couldn't be parsed.
    func importBackup(data: Data, replace: Bool, settings: WorktimeSettings) async -> Int? {
        guard let parsed = try? BackupManager.parse(data) else { return nil }
        if replace {
            try? await store.deleteAllSessions()
        }
        for session in parsed.sessions {
            try? await store.insertSession(start: session.start, end: session.end)
        }
        if let imported = parsed.settings {
            settings.importState(
                work: imported.workMillis.map { Double($0) / 1000 } ?? settings.workSeconds,
                lunch: imported.lunchMillis.map { Double($0) / 1000 } ?? settings.lunchSeconds,
                endedDayStart: imported.endedDayStart
                    .flatMap { $0 == 0 ? nil : $0 }
                    .map { Date(timeIntervalSince1970: Double($0) / 1000) }
            )
        }
        await refresh()
        return parsed.sessions.count
    }

    func exportBackup(settings: WorktimeSettings, now: Date = Date()) -> Data? {
        let document = BackupManager.makeDocument(
            sessions: days.flatMap(\.sessions),
            settings: BackupSettingsDTO(
                workMillis: Int64(settings.workSeconds * 1000),
                lunchMillis: Int64(settings.lunchSeconds * 1000),
                endedDayStart: settings.endedDayStart.map { Int64($0.timeIntervalSince1970 * 1000) }
            ),
            now: now
        )
        return try? BackupManager.encode(document)
    }
}
```

- [ ] **Step 4: Implement AppModel, Theme, TabView shell, entitlements, and stubs**

`OvertimeOverview/Application/AppModel.swift`:

```swift
//
//  AppModel.swift
//  OvertimeOverview
//

import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class AppModel {
    private static let logger = Logger(subsystem: "hu.paydogs.overtimeoverview", category: "app")

    let store: WorktimeStore
    let viewModel: WorktimeViewModel
    let settings = WorktimeSettings.shared
    let haptics = HapticsSettingsStore.shared

    init() {
        let container = try? WorktimeStore.makeModelContainer()
        // App Group store, or in-memory fallback (missing entitlement) so the
        // app still runs instead of crashing.
        store = WorktimeStore(modelContainer: container ?? (try! WorktimeStore.makeInMemoryContainer()))
        viewModel = WorktimeViewModel(store: store)
        if container == nil {
            Self.logger.error("App Group container unavailable — running with in-memory store")
        }
    }
}
```

`OvertimeOverview/Application/UI/Theme.swift`:

```swift
//
//  Theme.swift
//  OvertimeOverview
//

import SwiftUI

enum Theme {
    static let brand = LinearGradient(
        colors: [Color(red: 106 / 255, green: 90 / 255, blue: 224 / 255),
                 Color(red: 166 / 255, green: 75 / 255, blue: 244 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let warm = LinearGradient(
        colors: [Color(red: 1, green: 107 / 255, blue: 107 / 255),
                 Color(red: 1, green: 142 / 255, blue: 83 / 255)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
}
```

`OvertimeOverview/Application/UI/ContentView.swift` (replace content):

```swift
//
//  ContentView.swift
//  OvertimeOverview
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label(Keys.tabToday, systemImage: "clock") }
            HistoryView()
                .tabItem { Label(Keys.tabHistory, systemImage: "calendar") }
            SettingsView()
                .tabItem { Label(Keys.tabSettings, systemImage: "gearshape") }
        }
    }
}
```

`OvertimeOverview/Application/UI/TodayView.swift`, `HistoryView.swift`, `SettingsView.swift` — each a stub replaced later:

```swift
import SwiftUI

struct TodayView: View {
    var body: some View { Text(Keys.tabToday) }
}
```

```swift
import SwiftUI

struct HistoryView: View {
    var body: some View { Text(Keys.tabHistory) }
}
```

```swift
import SwiftUI

struct SettingsView: View {
    var body: some View { Text(Keys.tabSettings) }
}
```

`OvertimeOverview/Application/OvertimeOverviewApp.swift` (replace content):

```swift
//
//  OvertimeOverviewApp.swift
//  OvertimeOverview
//

import SwiftUI

@main
struct OvertimeOverviewApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    @Environment(\.scenePhase) private var scenePhase
    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .onChange(of: scenePhase) { _, phase in
            // Widget punches may have changed data while we were backgrounded.
            guard phase == .active else { return }
            Task { await appModel.viewModel.refresh() }
        }
    }
}
```

`OvertimeOverview/Support/OvertimeOverview.entitlements`:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.application-groups</key>
	<array>
		<string>group.hu.paydogs.overtimeoverview</string>
	</array>
</dict>
</plist>
```

In `OvertimeOverview/Project.swift`, add to the app target (after `infoPlist:`):

```swift
    entitlements: .file(path: "Support/OvertimeOverview.entitlements"),
```

- [ ] **Step 5: Add tab strings**

Append to `en.lproj/Localizable.strings`:

```
"tab_today" = "Today";
"tab_history" = "History";
"tab_settings" = "Settings";
```

Append to `hu.lproj/Localizable.strings`:

```
"tab_today" = "Ma";
"tab_history" = "Előzmények";
"tab_settings" = "Beállítások";
```

- [ ] **Step 6: Run tests to verify they pass, then build**

Run: `tuist generate --no-open && tuist test --target OvertimeOverviewTests && tuist build`
Expected: PASS + build green (stub tabs render).

- [ ] **Step 7: Report done** — suggested message: `feat: app shell — TabView, AppModel, WorktimeViewModel, App Group entitlement`

### Task 9: TodayView — hero card, status, punch buttons

**Files:**
- Modify: `OvertimeOverview/Application/UI/TodayView.swift`
- Modify: `Application/Resources/{en,hu}.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `AppModel` (environment), `WorktimeMath` (status/overtime/punch), `Formatters`, `Theme`, `HapticsController`.
- Produces: `struct TodayView: View` (full Today tab). Views for Task 10 append to this file: `SessionRow` and edit dialogs, driven by `TodayView`'s `sessions` list section.

- [ ] **Step 1: Add the Today strings**

Append to `en.lproj/Localizable.strings`:

```
"today_now" = "Now  %@";
"today_progress" = "%1$d%% of %2$@";
"today_overtime" = "Overtime: %@";
"today_undertime" = "Undertime: %@";
"status_atOffice" = "At the office since %@";
"status_done" = "Done for today";
"status_onBreak" = "On a break — Clock in to continue";
"status_notAtOffice" = "Not at the office";
"finish_finishes" = "Workday finishes at %@";
"finish_finished" = "Workday finished at %@";
"button_clockIn" = "Clock in";
"button_clockBackIn" = "Clock back in";
"button_break" = "Clock out for a break";
"button_endOfDay" = "Clock out for today";
"worktime_title" = "Worktime";
"worktime_net" = "Worktime: %@";
"worktime_breakdown" = "In office %1$@ · lunch −%2$@";
"picker_clockIn" = "Clock-in time";
"picker_breakOut" = "Clock-out time (break)";
"picker_endOfDay" = "Clock-out time (end of day)";
"common_ok" = "OK";
"common_cancel" = "Cancel";
```

Append to `hu.lproj/Localizable.strings`:

```
"today_now" = "Most  %@";
"today_progress" = "%1$d%% / %2$@";
"today_overtime" = "Túlóra: %@";
"today_undertime" = "Hiány: %@";
"status_atOffice" = "Az irodában %1$@ óta";
"status_done" = "Mára kész";
"status_onBreak" = "Szünetben — a folytatáshoz jelentkezz be";
"status_notAtOffice" = "Nem vagy az irodában";
"finish_finishes" = "A munkanap %1$@-kor ér véget";
"finish_finished" = "A munkanap %1$@-kor véget ért";
"button_clockIn" = "Érkezés";
"button_clockBackIn" = "Visszaérkezés";
"button_break" = "Távozás szünetre";
"button_endOfDay" = "Mai nap zárása";
"worktime_title" = "Munkaidő";
"worktime_net" = "Munkaidő: %@";
"worktime_breakdown" = "Irodában %1$@ · ebéd −%2$@";
"picker_clockIn" = "Érkezés időpontja";
"picker_breakOut" = "Távozás időpontja (szünet)";
"picker_endOfDay" = "Távozás időpontja (nap zárása)";
"common_ok" = "OK";
"common_cancel" = "Mégse";
```

- [ ] **Step 2: Implement TodayView**

Replace `TodayView.swift` with:

```swift
//
//  TodayView.swift
//  OvertimeOverview
//

import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var appModel
    @State private var punchTarget: PunchTarget?

    /// Which punch the time-picker sheet is configuring; `now` is captured so
    /// the picked time keeps the real second of the tap moment.
    struct PunchTarget: Identifiable {
        enum Kind { case clockIn, breakOut, endOfDay }
        let kind: Kind
        let now: Date
        var id: String { "\(kind)" }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            TodayContentView(
                appModel: appModel,
                now: timeline.date,
                punchTarget: $punchTarget
            )
        }
        .sheet(item: $punchTarget) { target in
            PunchTimePicker(target: target, appModel: appModel)
        }
    }
}

private struct TodayContentView: View {
    let appModel: AppModel
    let now: Date
    @Binding var punchTarget: TodayView.PunchTarget?

    var body: some View {
        let viewModel = appModel.viewModel
        let settings = appModel.settings
        let todays = viewModel.todaysSessions(now: now)
        let presence = WorktimeMath.presence(todays, now: now)
        let target = settings.officeTarget
        let net = WorktimeMath.netWorktime(presence: presence, lunch: settings.lunchSeconds)
        let overtime = presence - target
        let open = viewModel.openSession
        let dayEnded = settings.endedToday(now: now)
        let status = WorktimeMath.status(todayPresence: presence, openSession: open, dayEnded: dayEnded)

        ScrollView {
            VStack(spacing: 24) {
                Text(Keys.todayNow(Formatters.clockWithSeconds(now)))
                    .foregroundStyle(.secondary)

                heroCard(presence: presence, target: target, overtime: overtime,
                         dayEnded: dayEnded, status: status, open: open)

                actionButtons(open: open, presence: presence, dayEnded: dayEnded)

                VStack(spacing: 4) {
                    Text(Keys.worktimeNet(Formatters.duration(net)))
                        .font(.title2.weight(.semibold))
                    Text(Keys.worktimeBreakdown(
                        Formatters.duration(presence),
                        Formatters.duration(settings.lunchSeconds)
                    ))
                    .foregroundStyle(.secondary)
                }

                Divider()

                SessionSection(now: now, appModel: appModel)
            }
            .padding()
        }
        .navigationTitle(Keys.worktimeTitle)
    }

    private func heroCard(presence: TimeInterval, target: TimeInterval, overtime: TimeInterval,
                          dayEnded: Bool, status: WorktimeMath.TodayStatus, open: WorkSession?) -> some View {
        let progress = target > 0 ? min(1, presence / target) : 0
        return ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Theme.brand)
            VStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(0.25), lineWidth: 12)
                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(Color.white, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.easeInOut(duration: 0.6), value: progress)
                    Text(Formatters.elapsed(presence))
                        .font(.system(size: 32, weight: .bold, design: .monospaced))
                        .foregroundStyle(.white)
                }
                .frame(width: 180, height: 180)

                Text(Keys.todayProgress(
                    Int(progress * 100),
                    Formatters.duration(target)
                ))
                .foregroundStyle(.white.opacity(0.9))

                if WorktimeMath.showsOvertime(overtime: overtime, dayEnded: dayEnded) {
                    let label = overtime > 0 ? Keys.todayOvertime : Keys.todayUndertime
                    Text(label(Formatters.shortDuration(overtime)))
                        .font(.headline)
                        .foregroundStyle(.white)
                }

                switch status {
                case .atOffice(let since):
                    Text(Keys.statusAtOffice(Formatters.clock(since)))
                        .foregroundStyle(.white.opacity(0.9))
                case .doneForToday:
                    Text(Keys.statusDone).foregroundStyle(.white.opacity(0.9))
                case .onBreak:
                    Text(Keys.statusOnBreak).foregroundStyle(.white.opacity(0.9))
                case .notAtOffice:
                    Text(Keys.statusNotAtOffice).foregroundStyle(.white.opacity(0.9))
                }

                if let open, open.isOpen {
                    let finish = WorktimeMath.projectedFinish(now: now, presence: presence, target: target)
                    let text = finish <= now
                        ? Keys.finishFinished(Formatters.clock(finish))
                        : Keys.finishFinishes(Formatters.clock(finish))
                    Text(text)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.9))
                }
            }
            .padding(24)
        }
    }

    private func actionButtons(open: WorkSession?, presence: TimeInterval, dayEnded: Bool) -> some View {
        VStack(spacing: 12) {
            if open != nil {
                Button {
                    HapticsController.play(appModel.haptics.settings)
                    punchTarget = .init(kind: .breakOut, now: now)
                } label: {
                    Text(Keys.buttonBreak)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Theme.warm, in: Capsule())
                }
                Button {
                    HapticsController.play(appModel.haptics.settings)
                    punchTarget = .init(kind: .endOfDay, now: now)
                } label: {
                    Text(Keys.buttonEndOfDay)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1))
                }
            } else {
                Button {
                    HapticsController.play(appModel.haptics.settings)
                    punchTarget = .init(kind: .clockIn, now: now)
                } label: {
                    Text(WorktimeMath.clockInLabel(todayPresence: presence, dayEnded: dayEnded)
                         ? Keys.buttonClockBackIn : Keys.buttonClockIn)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .foregroundStyle(.white)
                        .background(Theme.brand, in: Capsule())
                }
            }
        }
    }
}

struct PunchTimePicker: View {
    let target: TodayView.PunchTarget
    let appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickerDate: Date = .now

    private var title: String {
        switch target.kind {
        case .clockIn: Keys.pickerClockIn
        case .breakOut: Keys.pickerBreakOut
        case .endOfDay: Keys.pickerEndOfDay
        }
    }

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $pickerDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .padding()
                .navigationTitle(Keys.worktimeTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Keys.commonCancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Keys.commonOk) { confirm() }
                    }
                }
        }
        .presentationDetents([.medium])
    }

    private func confirm() {
        let calendar = Calendar.current
        // Clock-out uses the open session's start day as the base day
        // (MagniTools parity: a session can be closed on the day it started).
        let baseDay: Date
        if target.kind == .clockIn {
            baseDay = calendar.startOfDay(for: target.now)
        } else {
            baseDay = calendar.startOfDay(for: appModel.viewModel.openSession?.start ?? target.now)
        }
        let components = calendar.dateComponents([.hour, .minute], from: pickerDate)
        let date = WorktimeMath.punchDate(
            onDay: baseDay,
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: calendar.component(.second, from: target.now),
            calendar: calendar
        )

        Task {
            let viewModel = appModel.viewModel
            let settings = appModel.settings
            switch target.kind {
            case .clockIn:
                await viewModel.clockIn(at: date)
                settings.clearEnded()
            case .breakOut:
                await viewModel.clockOut(at: date)
                settings.clearEnded()
            case .endOfDay:
                await viewModel.clockOut(at: date)
                settings.markEndedToday()
            }
            HapticsController.play(appModel.haptics.settings)
            dismiss()
        }
    }
}
```

Note: `SessionSection` arrives in Task 10. Until then, add a temporary placeholder inside this task so it compiles:

```swift
struct SessionSection: View {
    let now: Date
    let appModel: AppModel
    var body: some View { EmptyView() }
}
```

(Task 10 replaces this placeholder — do not keep it after that task.)

- [ ] **Step 3: Build and run manually**

Run: `tuist generate --no-open && tuist build`
Expected: build green. If a simulator is available, launch and check the Today tab renders the hero card with live clock.

- [ ] **Step 4: Report done** — suggested message: `feat: Today tab — live presence ring, statuses, punch flow`

### Task 10: TodayView — session list + edit dialog

**Files:**
- Modify: `OvertimeOverview/Application/UI/TodayView.swift` (replace the `SessionSection` placeholder)
- Modify: `Application/Resources/{en,hu}.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `AppModel`, `Formatters`, `WorktimeMath.punchDate`, `HapticsController`.
- Produces: `struct SessionSection: View` (renders today's sessions, edit/delete flow).

- [ ] **Step 1: Add the session strings**

Append to `en.lproj/Localizable.strings`:

```
"today_emptySessions" = "No sessions yet today. Tap a session to edit its times.";
"session_now" = "now";
"session_edit" = "Edit session";
"session_start" = "Start: %@";
"session_end" = "End: %@";
"session_delete" = "Delete";
"session_close" = "Close";
"picker_start" = "Start time";
"picker_end" = "End time";
```

Append to `hu.lproj/Localizable.strings`:

```
"today_emptySessions" = "Ma még nincs bejegyzés. Koppints egy bejegyzésre a szerkesztéshez.";
"session_now" = "most";
"session_edit" = "Bejegyzés szerkesztése";
"session_start" = "Kezdés: %@";
"session_end" = "Befejezés: %@";
"session_delete" = "Törlés";
"session_close" = "Bezárás";
"picker_start" = "Kezdés időpontja";
"picker_end" = "Befejezés időpontja";
```

- [ ] **Step 2: Replace the SessionSection placeholder**

Replace the placeholder `SessionSection` in `TodayView.swift` with:

```swift
struct SessionSection: View {
    let now: Date
    let appModel: AppModel
    @State private var editingSession: WorkSession?
    @State private var editingEnd = false

    var body: some View {
        let sessions = appModel.viewModel.todaysSessions(now: now)
        VStack(alignment: .leading, spacing: 8) {
            if sessions.isEmpty {
                Text(Keys.todayEmptySessions)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions) { session in
                    Button {
                        HapticsController.play(appModel.haptics.settings)
                        editingSession = session
                        editingEnd = false
                    } label: {
                        SessionRow(session: session, now: now)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .sheet(item: $editingSession) { session in
            SessionEditSheet(
                session: session,
                editingEnd: editingEnd,
                appModel: appModel
            )
        }
    }
}

private struct SessionRow: View {
    let session: WorkSession
    let now: Date

    var body: some View {
        HStack {
            Text(session.isOpen
                 ? "\(Formatters.clock(session.start)) – \(Keys.sessionNow)"
                 : "\(Formatters.clock(session.start)) – \(Formatters.clock(session.end!))"
            )
            Spacer()
            Text(Formatters.duration(session.duration(now: now)))
                .bold()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct SessionEditSheet: View {
    let session: WorkSession
    let editingEnd: Bool
    let appModel: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var pickerDate: Date = .now
    @State private var pickEnd = false

    private var title: String { pickEnd ? Keys.pickerEnd : Keys.pickerStart }

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $pickerDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .padding()
                .navigationTitle(Keys.sessionEdit)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Keys.sessionClose) { dismiss() }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(Keys.sessionDelete, role: .destructive) {
                            Task {
                                await appModel.viewModel.delete(session: session)
                                dismiss()
                            }
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Keys.commonOk) { confirm() }
                    }
                }
                .toolbar {
                    ToolbarItemGroup(placement: .bottomBar) {
                        Button(Keys.sessionStart(Formatters.clock(session.start))) {
                            pickEnd = false
                            seedPicker()
                        }
                        Spacer()
                        if session.end != nil {
                            Button(Keys.sessionEnd(Formatters.clock(session.end!))) {
                                pickEnd = true
                                seedPicker()
                            }
                        }
                    }
                }
        }
        .presentationDetents([.medium])
        .onAppear {
            pickEnd = editingEnd
            seedPicker()
        }
    }

    private func seedPicker() {
        let calendar = Calendar.current
        let reference = pickEnd ? session.end! : session.start
        // Base day is always the session's start day (MagniTools parity).
        let baseDay = calendar.startOfDay(for: session.start)
        let components = calendar.dateComponents([.hour, .minute], from: reference)
        pickerDate = WorktimeMath.punchDate(
            onDay: baseDay,
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            // Edits carry the original timestamp's second through.
            second: calendar.component(.second, from: reference),
            calendar: calendar
        )
    }

    private func confirm() {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.hour, .minute], from: pickerDate)
        let reference = pickEnd ? session.end! : session.start
        let date = WorktimeMath.punchDate(
            onDay: calendar.startOfDay(for: session.start),
            hour: components.hour ?? 0,
            minute: components.minute ?? 0,
            second: calendar.component(.second, from: reference),
            calendar: calendar
        )
        Task {
            if pickEnd {
                await appModel.viewModel.update(session: session, start: session.start, end: date)
            } else {
                await appModel.viewModel.update(session: session, start: date, end: session.end)
            }
            dismiss()
        }
    }
}
```

Note: `editingSession` is `@State private var editingSession: WorkSession?` — `WorkSession` is `Identifiable`, so `.sheet(item:)` works.

- [ ] **Step 3: Build**

Run: `tuist generate --no-open && tuist build`
Expected: green.

- [ ] **Step 4: Report done** — suggested message: `feat: Today tab — session list with edit/delete`

### Task 11: HistoryView

**Files:**
- Modify: `OvertimeOverview/Application/UI/HistoryView.swift`
- Modify: `Application/Resources/{en,hu}.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `AppModel`, `WorktimeMath.historyCandidates/groupByMonth/monthOvertime/netWorktime`, `Formatters`.
- Produces: `struct HistoryView: View`.

- [ ] **Step 1: Add the history strings**

Append to `en.lproj/Localizable.strings`:

```
"history_empty" = "No previous days yet.";
"history_monthWorktime" = "Worktime %@";
"history_monthOvertime" = "Overtime %@";
"history_monthUndertime" = "Undertime %@";
"history_inOfficeSessions" = "In office %1$@ · %2$d sessions";
"history_noSessions" = "No sessions.";
```

Append to `hu.lproj/Localizable.strings`:

```
"history_empty" = "Még nincsenek korábbi napok.";
"history_monthWorktime" = "Munkaidő %@";
"history_monthOvertime" = "Túlóra %@";
"history_monthUndertime" = "Hiány %@";
"history_inOfficeSessions" = "Irodában %1$@ · %2$d bejegyzés";
"history_noSessions" = "Nincs bejegyzés.";
```

- [ ] **Step 2: Implement HistoryView**

Replace `HistoryView.swift` with:

```swift
//
//  HistoryView.swift
//  OvertimeOverview
//

import SwiftUI

struct HistoryView: View {
    @Environment(AppModel.self) private var appModel
    @State private var expandedMonths: Set<Date> = []
    @State private var selectedDay: WorkDay?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            HistoryContentView(
                appModel: appModel,
                now: timeline.date,
                expandedMonths: $expandedMonths,
                selectedDay: $selectedDay
            )
        }
        .sheet(item: $selectedDay) { day in
            DaySessionsSheet(day: day, now: Date())
                .presentationDetents([.medium])
        }
    }
}

private struct HistoryContentView: View {
    let appModel: AppModel
    let now: Date
    @Binding var expandedMonths: Set<Date>
    @Binding var selectedDay: WorkDay?

    var body: some View {
        let settings = appModel.settings
        let calendar = Calendar.current
        let candidates = WorktimeMath.historyCandidates(
            days: appModel.viewModel.days,
            now: now,
            dayEnded: settings.endedToday(now: now),
            calendar: calendar
        )
        let months = WorktimeMath.groupByMonth(candidates, calendar: calendar)

        List {
            if months.isEmpty {
                Text(Keys.historyEmpty)
                    .foregroundStyle(.secondary)
            }
            ForEach(months, id: \.monthStart) { month in
                MonthSection(
                    month: month,
                    now: now,
                    lunch: settings.lunchSeconds,
                    work: settings.workSeconds,
                    isExpanded: expandedMonths.contains(month.monthStart),
                    toggle: {
                        if expandedMonths.contains(month.monthStart) {
                            expandedMonths.remove(month.monthStart)
                        } else {
                            expandedMonths.insert(month.monthStart)
                        }
                    },
                    onSelectDay: { selectedDay = $0 }
                )
            }
        }
        .onAppear {
            // Only the newest month is expanded by default.
            if expandedMonths.isEmpty, let first = months.first {
                expandedMonths = [first.monthStart]
            }
        }
        .navigationTitle(Keys.tabHistory)
    }
}

private struct MonthSection: View {
    let month: (monthStart: Date, days: [WorkDay])
    let now: Date
    let lunch: TimeInterval
    let work: TimeInterval
    let isExpanded: Bool
    let toggle: () -> Void
    let onSelectDay: (WorkDay) -> Void

    var body: some View {
        Section {
            if isExpanded {
                ForEach(month.days) { day in
                    Button { onSelectDay(day) } label: { DayRow(day: day, now: now, lunch: lunch, work: work) }
                        .buttonStyle(.plain)
                }
            }
        } header: {
            Button(action: toggle) { header }
        }
    }

    private var header: some View {
        let netPerDay = month.days.map {
            WorktimeMath.netWorktime(presence: $0.inOffice(now: now), lunch: lunch)
        }
        let monthNet = netPerDay.reduce(0, +)
        let monthOvertime = WorktimeMath.monthOvertime(netPerDay: netPerDay, workPerDay: work)

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(Formatters.month(month.monthStart))
                    .font(.headline)
                    .foregroundStyle(.accentColor)
                Spacer()
                Image(systemName: "chevron_right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
            }
            HStack {
                Text(Keys.historyMonthWorktime(Formatters.duration(monthNet)))
                    .font(.subheadline)
                Spacer()
                if monthOvertime > 0 {
                    Text(Keys.historyMonthOvertime(Formatters.duration(monthOvertime)))
                        .font(.subheadline)
                        .foregroundStyle(.accentColor)
                } else if monthOvertime < 0 {
                    Text(Keys.historyMonthUndertime(Formatters.duration(monthOvertime)))
                        .font(.subheadline)
                        .foregroundStyle(.red)
                }
            }
        }
        .contentShape(Rectangle())
    }
}

private struct DayRow: View {
    let day: WorkDay
    let now: Date
    let lunch: TimeInterval
    let work: TimeInterval

    var body: some View {
        let inOffice = day.inOffice(now: now)
        let net = WorktimeMath.netWorktime(presence: inOffice, lunch: lunch)
        let overtime = net - work

        return VStack(alignment: .leading, spacing: 4) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Formatters.weekdayDay(day.dayStart))
                        .font(.body)
                    Text(Keys.historyInOfficeSessions(
                        Formatters.duration(inOffice),
                        day.sessions.count
                    ))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(Formatters.duration(net)).bold()
                    if overtime != 0 {
                        Text(Formatters.shortDuration(overtime))
                            .font(.caption)
                            .foregroundStyle(overtime > 0 ? .accentColor : .red)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

private struct DaySessionsSheet: View {
    let day: WorkDay
    let now: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if day.sessions.isEmpty {
                    Text(Keys.historyNoSessions)
                }
                ForEach(day.sessions) { session in
                    HStack {
                        Text(session.isOpen
                             ? "\(Formatters.clock(session.start)) – \(Keys.sessionNow)"
                             : "\(Formatters.clock(session.start)) – \(Formatters.clock(session.end!))")
                        Spacer()
                        Text(Formatters.duration(session.duration(now: now)))
                    }
                }
            }
            .navigationTitle(Formatters.weekdayDay(day.dayStart))
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button(Keys.sessionClose) { dismiss() }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Build**

Run: `tuist generate --no-open && tuist build`
Expected: green.

- [ ] **Step 4: Report done** — suggested message: `feat: History tab — monthly accordion with signed overtime`

### Task 12: SettingsView — work/lunch pickers, haptics, backup, version footer

**Files:**
- Modify: `OvertimeOverview/Application/UI/SettingsView.swift`
- Modify: `Application/Resources/{en,hu}.lproj/Localizable.strings`

**Interfaces:**
- Consumes: `AppModel` (settings, haptics, viewModel), `WorktimeSettings.updateWork/updateLunch`, `HapticsSettingsStore`, `HapticsController`, `WorktimeViewModel.exportBackup/importBackup`, `Formatters.exportStamp`.
- Produces: `struct SettingsView: View`.

- [ ] **Step 1: Add the settings strings**

Append to `en.lproj/Localizable.strings`:

```
"settings_work" = "Work time";
"settings_workSubtitle" = "Actual work you owe per day";
"settings_lunch" = "Lunch length";
"settings_lunchSubtitle" = "Added to the office target, deducted from worktime";
"settings_officeTarget" = "Office target: %@ (work + lunch)";
"settings_pickWork" = "Work time (hours : minutes)";
"settings_pickLunch" = "Lunch length (hours : minutes)";
"settings_haptics" = "Haptics";
"settings_hapticsSubtitle" = "Haptic feedback on button taps";
"settings_hapticStrength" = "Strength: %d%%";
"settings_hapticPattern" = "Pattern";
"haptic_single" = "Single";
"haptic_double" = "Double";
"haptic_triple" = "Triple";
"haptic_long" = "Long";
"settings_testHaptics" = "Test haptics";
"settings_backup" = "Backup";
"settings_export" = "Export backup";
"settings_import" = "Import backup";
"backup_importQuestion" = "Replace all sessions or merge with existing?";
"backup_replace" = "Replace";
"backup_merge" = "Merge";
"backup_imported" = "Imported %d sessions";
"backup_failed" = "Could not read the backup file";
"backup_exportFailed" = "Could not create the backup file";
```

Append to `hu.lproj/Localizable.strings`:

```
"settings_work" = "Munkaidő hossza";
"settings_workSubtitle" = "A napi elvégzendő munkaidő";
"settings_lunch" = "Ebéd hossza";
"settings_lunchSubtitle" = "Hozzáadódik az irodai célhoz, levonódik a munkaidőből";
"settings_officeTarget" = "Irodai cél: %@ (munka + ebéd)";
"settings_pickWork" = "Munkaidő (óra : perc)";
"settings_pickLunch" = "Ebéd hossza (óra : perc)";
"settings_haptics" = "Rezgés";
"settings_hapticsSubtitle" = "Reakció a gombok megérintésére";
"settings_hapticStrength" = "Erősség: %d%%";
"settings_hapticPattern" = "Minta";
"haptic_single" = "Egyszer";
"haptic_double" = "Dupla";
"haptic_triple" = "Hármas";
"haptic_long" = "Hosszú";
"settings_testHaptics" = "Rezgés tesztelése";
"settings_backup" = "Biztonsági mentés";
"settings_export" = "Mentés exportálása";
"settings_import" = "Mentés importálása";
"backup_importQuestion" = "Cseréled az összes bejegyzést, vagy egyesítsed a meglévőkkel?";
"backup_replace" = "Csere";
"backup_merge" = "Egyesítés";
"backup_imported" = "%d bejegyzés importálva";
"backup_failed" = "A mentési fájl nem olvasható";
"backup_exportFailed" = "A mentési fájl nem hozható létre";
```

- [ ] **Step 2: Implement SettingsView**

Replace `SettingsView.swift` with:

```swift
//
//  SettingsView.swift
//  OvertimeOverview
//

import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var pickingWork = false
    @State private var pickingLunch = false
    @State private var importing = false
    @State private var pendingImport: Data?
    @State private var shareURL: URL?
    @State private var alertMessage: String?

    var body: some View {
        Form {
            Section(Keys.worktimeTitle) {
                valueRow(
                    title: Keys.settingsWork,
                    subtitle: Keys.settingsWorkSubtitle,
                    value: Formatters.duration(appModel.settings.workSeconds)
                ) { pickingWork = true }
                valueRow(
                    title: Keys.settingsLunch,
                    subtitle: Keys.settingsLunchSubtitle,
                    value: Formatters.duration(appModel.settings.lunchSeconds)
                ) { pickingLunch = true }
                Text(Keys.settingsOfficeTarget(Formatters.duration(appModel.settings.officeTarget)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle(isOn: hapticsBinding) {
                    VStack(alignment: .leading) {
                        Text(Keys.settingsHaptics)
                        Text(Keys.settingsHapticsSubtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if appModel.haptics.settings.enabled {
                    VStack(alignment: .leading) {
                        Text(Keys.settingsHapticStrength(Int(appModel.haptics.settings.strength * 100)))
                        Slider(value: strengthBinding, in: 0.1...1)
                    }
                    Picker(Keys.settingsHapticPattern, selection: patternBinding) {
                        ForEach(HapticPattern.allCases, id: \.self) { pattern in
                            Text(Self.patternLabel(pattern)).tag(pattern)
                        }
                    }
                    Button(Keys.settingsTestHaptics) {
                        HapticsController.play(appModel.haptics.settings)
                    }
                }
            }

            Section(Keys.settingsBackup) {
                Button(Keys.settingsExport) { exportBackup() }
                Button(Keys.settingsImport) { importing = true }
            }

            Section {
                Text(Self.versionFooter)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(Keys.tabSettings)
        .sheet(isPresented: $pickingWork) {
            DurationPickerSheet(title: Keys.settingsPickWork, minutes: Int(appModel.settings.workSeconds / 60)) {
                appModel.settings.updateWork(minutes: $0)
            }
        }
        .sheet(isPresented: $pickingLunch) {
            DurationPickerSheet(title: Keys.settingsPickLunch, minutes: Int(appModel.settings.lunchSeconds / 60)) {
                appModel.settings.updateLunch(minutes: $0)
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            if case .success(let url) = result { readImport(url) }
        }
        .confirmationDialog(
            Keys.backupImportQuestion,
            isPresented: Binding(
                get: { pendingImport != nil },
                set: { if !$0 { pendingImport = nil } }
            )
        ) {
            Button(Keys.backupReplace) { importBackup(replace: true) }
            Button(Keys.backupMerge) { importBackup(replace: false) }
            Button(Keys.commonCancel, role: .cancel) { pendingImport = nil }
        }
        .sheet(item: shareBinding) { url in
            ShareSheet(url: url)
        }
        .alert(
            Keys.settingsBackup,
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } }),
            presenting: alertMessage
        ) { _ in } message: { message in Text(message) }
    }

    // MARK: - Backup

    private func exportBackup() {
        guard let data = appModel.viewModel.exportBackup(settings: appModel.settings),
              let url = try? Self.writeTempJSON(data)
        else {
            alertMessage = Keys.backupExportFailed
            return
        }
        shareURL = url
    }

    private static func writeTempJSON(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("overtimeoverview-\(Formatters.exportStamp(Date())).json")
        try data.write(to: url, options: .atomic)
        return url
    }

    private func readImport(_ url: URL) {
        guard url.startAccessingSecurityScopedResource(),
              let data = try? Data(contentsOf: url)
        else {
            alertMessage = Keys.backupFailed
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        pendingImport = data
    }

    private func importBackup(replace: Bool) {
        guard let data = pendingImport else { return }
        pendingImport = nil
        Task {
            if let count = await appModel.viewModel.importBackup(
                data: data, replace: replace, settings: appModel.settings
            ) {
                alertMessage = Keys.backupImported(count)
            } else {
                alertMessage = Keys.backupFailed
            }
        }
    }

    // MARK: - Bindings

    private var hapticsBinding: Binding<Bool> {
        Binding(
            get: { appModel.haptics.settings.enabled },
            set: { newValue in
                var settings = appModel.haptics.settings
                settings.enabled = newValue
                appModel.haptics.update(settings)
                if newValue { HapticsController.play(settings) }
            }
        )
    }

    private var strengthBinding: Binding<Double> {
        Binding(
            get: { appModel.haptics.settings.strength },
            set: { newValue in
                var settings = appModel.haptics.settings
                settings.strength = newValue
                appModel.haptics.update(settings)
            }
        )
    }

    private var patternBinding: Binding<HapticPattern> {
        Binding(
            get: { appModel.haptics.settings.pattern },
            set: { newValue in
                var settings = appModel.haptics.settings
                settings.pattern = newValue
                appModel.haptics.update(settings)
            }
        )
    }

    private var shareBinding: Binding<ShareURL?> {
        Binding(get: { shareURL.map(ShareURL.init) }, set: { if $0 == nil { shareURL = nil } })
    }

    // MARK: - Rows

    private func valueRow(title: String, subtitle: String, value: String, onTap: @escaping () -> Void) -> some View {
        Button(action: {
            HapticsController.play(appModel.haptics.settings)
            onTap()
        }) {
            HStack {
                VStack(alignment: .leading) {
                    Text(title).foregroundStyle(.primary)
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(value).bold()
                Image(systemName: "chevron_right").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private static func patternLabel(_ pattern: HapticPattern) -> String {
        switch pattern {
        case .single: Keys.hapticSingle
        case .double: Keys.hapticDouble
        case .triple: Keys.hapticTriple
        case .long: Keys.hapticLong
        }
    }

    private static var versionFooter: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "OvertimeOverview v\(version) (\(build))"
    }
}

/// Wrapper so `.sheet(item:)` can present a URL.
private struct ShareURL: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
    init(_ url: URL) { self.url = url }
}

/// UIKit share sheet for the exported file.
private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// Hours:minutes wheel picker used for work time and lunch length.
private struct DurationPickerSheet: View {
    let title: String
    let minutes: Int
    let onConfirm: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pickerDate: Date = .now

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $pickerDate, displayedComponents: .hourAndMinute)
                .datePickerStyle(.wheel)
                .padding()
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(Keys.commonCancel) { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(Keys.commonOk) {
                            let components = Calendar.current.dateComponents([.hour, .minute], from: pickerDate)
                            onConfirm((components.hour ?? 0) * 60 + (components.minute ?? 0))
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.medium])
        .onAppear {
            let calendar = Calendar.current
            pickerDate = calendar.date(
                from: DateComponents(
                    year: 2000, month: 1, day: 1,
                    hour: minutes / 60, minute: minutes % 60
                )
            )!
        }
    }
}
```

- [ ] **Step 3: Build and run the full app flow manually**

Run: `tuist generate --no-open && tuist build`
Expected: green. On the simulator: set work time, hear/feel test haptic, export a backup (share sheet), re-import it.

- [ ] **Step 4: Run the whole test suite**

Run: `tuist test`
Expected: PASS — all suites from Tasks 2–8.

- [ ] **Step 5: Report done** — suggested message: `feat: Settings tab — work/lunch, haptics, backup export/import`

### Task 13: Widget extension — target, intents, widget view

**Files:**
- Create: `OvertimeOverview/WorktimeWidget/WorktimeWidgetBundle.swift`
- Create: `OvertimeOverview/WorktimeWidget/WorktimeWidget.swift`
- Create: `OvertimeOverview/WorktimeWidget/PunchIntents.swift`
- Create: `OvertimeOverview/WorktimeWidget/Resources/en.lproj/Localizable.strings`, `hu.lproj/Localizable.strings`
- Create: `OvertimeOverview/WorktimeWidget/Support/WorktimeWidget.entitlements`
- Modify: `OvertimeOverview/Project.swift` (new target + dependency)

**Interfaces:**
- Consumes: `Domain/**` (Task 3–5 types), `WorktimeStore.appGroup`.
- Produces: widget extension target `WorktimeWidget` (bundle id `hu.paydogs.overtimeoverview.WorktimeWidget`); `ClockInIntent` / `ClockOutIntent` App Intents; widget status "In since HH:mm" / "Done for today" / "Not clocked in".

- [ ] **Step 1: Add the widget target to Project.swift**

Add to the `targets:` array in `Project.swift` and the app target's `dependencies`:

```swift
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
    entitlements: .file(path: "WorktimeWidget/Support/WorktimeWidget.entitlements"),
    sources: [
        .glob("WorktimeWidget/**/*.swift", excluding: ["WorktimeWidget/Resources/**", "WorktimeWidget/Support/**"]),
        .glob("Domain/**/*.swift")
    ],
    resources: ["WorktimeWidget/Resources/**"]
)
```

In the app target's `dependencies` add `.target(name: "WorktimeWidget")` and change the project to `targets: [defaultApp, worktimeWidget, unitTests, uiTests]`.

`OvertimeOverview/WorktimeWidget/Support/WorktimeWidget.entitlements` — same XML as the app entitlements (Task 8) with the App Group `group.hu.paydogs.overtimeoverview`.

- [ ] **Step 2: Widget strings**

`WorktimeWidget/Resources/en.lproj/Localizable.strings`:

```
"widget_name" = "Worktime";
"widget_inSince" = "In since %@";
"widget_done" = "Done for today";
"widget_notClockedIn" = "Not clocked in";
"widget_clockIn" = "Clock In";
"widget_clockOut" = "Clock Out";
"widget_description" = "Clock in or out, or open the Worktime screen";
```

`WorktimeWidget/Resources/hu.lproj/Localizable.strings`:

```
"widget_name" = "Munkaidő";
"widget_inSince" = "Bent %1$@ óta";
"widget_done" = "Mára kész";
"widget_notClockedIn" = "Nincs bejelentkezve";
"widget_clockIn" = "Érkezés";
"widget_clockOut" = "Távozás";
"widget_description" = "Érkezés, távozás vagy a Munkaidő képernyő megnyitása";
```

(Widget target keys are looked up with `NSLocalizedString` — its own bundle — because the app's generated `Keys` isn't compiled here.)

- [ ] **Step 3: Implement intents, provider, widget**

`OvertimeOverview/WorktimeWidget/PunchIntents.swift`:

```swift
//
//  PunchIntents.swift
//  WorktimeWidget
//

import AppIntents
import Foundation
import WidgetKit

struct ClockInIntent: AppIntent {
    static var title: LocalizedStringResource = "widget_clockIn"

    func perform() async throws -> some IntentResult {
        guard let container = try? WorktimeStore.makeModelContainer() else {
            return .result()
        }
        let store = WorktimeStore(modelContainer: container)
        try? await store.clockIn(at: Date())
        await MainActor.run { WorktimeSettings.shared.clearEnded() }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}

struct ClockOutIntent: AppIntent {
    static var title: LocalizedStringResource = "widget_clockOut"

    func perform() async throws -> some IntentResult {
        guard let container = try? WorktimeStore.makeModelContainer() else {
            return .result()
        }
        let store = WorktimeStore(modelContainer: container)
        try? await store.clockOut(at: Date())
        // Widget clock-out always marks the day ended (MagniTools asymmetry).
        await MainActor.run { WorktimeSettings.shared.markEndedToday() }
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
```

`OvertimeOverview/WorktimeWidget/WorktimeWidget.swift`:

```swift
//
//  WorktimeWidget.swift
//  WorktimeWidget
//

import SwiftUI
import WidgetKit

struct StatusEntry: TimelineEntry {
    let date: Date
    let statusText: String
}

struct WorktimeStatusProvider: TimelineProvider {
    func placeholder(in context: Context) -> StatusEntry {
        StatusEntry(date: .now, statusText: NSLocalizedString("widget_notClockedIn", comment: ""))
    }

    func getSnapshot(in context: Context, completion: @escaping (StatusEntry) -> Void) {
        Task { completion(await currentEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StatusEntry>) -> Void) {
        Task {
            let entry = await currentEntry()
            // Refresh hourly while inactive; punches reload immediately.
            let next = Calendar.current.date(byAdding: .hour, value: 1, to: entry.date)!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func currentEntry() async -> StatusEntry {
        let now = Date()
        guard let container = try? WorktimeStore.makeModelContainer() else {
            return StatusEntry(date: now, statusText: NSLocalizedString("widget_notClockedIn", comment: ""))
        }
        let store = WorktimeStore(modelContainer: container)
        let endedToday = await MainActor.run { WorktimeSettings.shared.endedToday(now: now) }
        if let open = try? await store.openSession(), let open {
            return StatusEntry(
                date: now,
                statusText: String(
                    format: NSLocalizedString("widget_inSince", comment: ""),
                    Formatters.clock(open.start)
                )
            )
        }
        if endedToday {
            return StatusEntry(date: now, statusText: NSLocalizedString("widget_done", comment: ""))
        }
        return StatusEntry(date: now, statusText: NSLocalizedString("widget_notClockedIn", comment: ""))
    }
}

struct WorktimeWidgetView: View {
    let entry: StatusEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(NSLocalizedString("widget_name", comment: "")).bold()
                Spacer()
                Text(entry.statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            HStack(spacing: 12) {
                Button(intent: ClockInIntent()) {
                    Image(systemName: "arrow.right.circle.fill")
                }
                .buttonStyle(.borderedProminent)
                Button(intent: ClockOutIntent()) {
                    Image(systemName: "arrow.left.circle.fill")
                }
                .buttonStyle(.bordered)
            }
        }
        .containerBackground(for: .widget) {
            LinearGradient(
                colors: [Color(red: 106 / 255, green: 90 / 255, blue: 224 / 255),
                         Color(red: 166 / 255, green: 75 / 255, blue: 244 / 255)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
        }
    }
}

struct WorktimeWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WorktimeWidget", provider: WorktimeStatusProvider()) { entry in
            WorktimeWidgetView(entry: entry)
        }
        .configurationDisplayName(NSLocalizedString("widget_name", comment: ""))
        .description(NSLocalizedString("widget_description", comment: ""))
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
```

`OvertimeOverview/WorktimeWidget/WorktimeWidgetBundle.swift`:

```swift
//
//  WorktimeWidgetBundle.swift
//  WorktimeWidget
//

import WidgetKit

@main
struct WorktimeWidgetBundle: WidgetBundle {
    var body: some Widget {
        WorktimeWidget()
    }
}
```

- [ ] **Step 4: Build both targets**

Run: `tuist generate --no-open && tuist build`
Expected: green; the widget extension appears in the built app bundle's `PlugIns/`.

- [ ] **Step 5: Verify on the simulator manually**

Add the widget to the home screen, punch in from it, open the app — the Today tab must show the session; punch out from the widget and confirm the status line and History inclusion.

- [ ] **Step 6: Report done** — suggested message: `feat: interactive Worktime widget (App Intents, App Group store)`

### Task 14: Final sweep — docs, full verification, review

**Files:**
- Modify: `README.md`
- All sources (review pass)

- [ ] **Step 1: Update README**

Append to `README.md` (keep the existing scaffold usage section):

```markdown
## OvertimeOverview

Tracks office presence (clock in / out) with a live daily target ring, monthly
history with signed overtime, and an interactive home-screen widget. iOS 17+,
SwiftUI + SwiftData (App Group shared with the widget). en/hu localization.

Build: `tuist generate` then open the workspace; run tests with `tuist test`.
```

- [ ] **Step 2: Full verification**

Run: `tuist generate --no-open && tuist build && tuist test`
Expected: build green, all tests pass.

- [ ] **Step 3: Cross-check the business rules against the spec**

Read `docs/superpowers/specs/2026-09-25-worktime-port-design.md` §Business rules (1–14 in the source-analysis sense) and verify each in the shipped code:
- clock-in while open / clock-out while closed are no-ops (`WorktimeStore`)
- presence derived from `now`, never persisted
- overtime gated by `showsOvertime`
- ended marker set by "Clock out for today" + widget clock-out; cleared by clock-in and break clock-out
- history today-inclusion only when ended; newest month expanded; signed monthly sums
- punches preserve seconds; settings whole minutes
- widget clock-out always ends the day

Report any deviation to the user before finishing.

- [ ] **Step 4: Report done** — suggested message: `docs: describe app, verify build and tests`

---

## Execution notes

- **The user commits.** After each task, report the suggested message and wait; do not run `git commit` or `git branch` (global CLAUDE.md rule).
- Tasks 1–8 are independent of the UI tasks in order but not among themselves; execute in sequence. Task 9–12 depend on 8; Task 13 depends on 3–5 and 8.
- `tuist generate` is needed after every `Project.swift`, `Package.swift`, resource, or new-file change before building/testing.
- The generated `Keys` API camelizes underscore keys: `"today_now"` with a format argument becomes `Keys.todayNow(...)`, without arguments `Keys.todayNow` — **check the generated `Derived/Sources` `Strings.swift` for the exact accessor names** after adding strings, and adjust call sites if a generated name differs from what a task shows.
- Subagent execution (if chosen) runs via the user's Ollama models: `claude -p "<task prompt>" --model glm-5.3-flash:cloud` (ollamaM) or `--model glm-5.3:cloud` (ollamaXL), launched from the repo root in the background, output redirected to a temp file.