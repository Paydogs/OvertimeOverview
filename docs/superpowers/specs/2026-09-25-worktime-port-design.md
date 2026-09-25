# Worktime Monitor Port — Design Spec

Date: 2026-09-25
Source app: MagniTools (Android, Kotlin, `hu.paydogs.magnitools`)
Target app: OvertimeOverview (SwiftUI, Tuist, iOS 17+)

## Goal

Re-implement MagniTools' Worktime monitor as an iOS app: track office presence with
clock-in/clock-out sessions, live daily progress toward a work + lunch target, a
per-day history grouped by month, work/lunch settings, JSON backup, haptics, and an
interactive home-screen widget. Everything poop-related and MagniTools' tool-picker
Home screen are excluded — OvertimeOverview gets a bottom TabView instead:
**Today | History | Settings**.

The Android sources were explored and the business logic verified against
`Worktime.kt` / `WorktimeSettings.kt` line by line; the rules below are semantic
requirements, not approximations.

## Module layout

```
OvertimeOverview/
  Domain/                ← plain folder, compiled into BOTH the app and widget targets
    Models/WorkSession.swift     SwiftData @Model: id, start: Date, end: Date?
    Mappers/                    ← all mapping lives here, nothing else maps:
      WorkSessionMapper.swift    SwiftData @Model ↔ domain struct (WorkSession)
      BackupSessionMapper.swift  backup JSON DTOs ↔ domain structs
    WorktimeStore.swift         SwiftData @ModelActor: clockIn/clockOut/update/delete/
                                todaysSessions/history grouping; in-memory snapshot
    WorktimeSettings.swift      work, lunch, endedDayStart (App Group UserDefaults)
    WorktimeMath.swift          day/month boundaries, presence/net/overtime rules
    Formatters.swift            HH:mm, H:MM:SS elapsed, "7h 32m", month/day names
    BackupManager.swift         JSON export/import (replace | merge)
    HapticsController.swift     Core Haptics wrapper (toggle, strength, pattern)
  Application/           ← app target: TabView UI, localization assets
  WorktimeWidget/       ← widget extension target (WidgetKit + App Intents)
```

- No separate package/module: `Project.swift` includes `Domain/**` in the app target's
  and the widget extension's `sources`, so both binaries share the same source files.
- **App Group** (`group.hu.paydogs.overtimeoverview`) on both targets: SwiftData store
  and UserDefaults live in the shared container.
- `Project.swift`: deployment targets bumped to iOS 17.0 (SwiftData, Observation,
  interactive widgets). Remove the `Toolkit` external dependency (approved). Keep the
  rest until their features land; re-add on demand.

## Data model

Persistence and domain stay separate: the SwiftData `@Model` (in `Models/`) is mapped
to a plain `WorkSession` domain struct by `WorktimeStore` through
`Mappers/WorkSessionMapper.swift`; UI and business logic touch only the domain
struct. Backup JSON DTOs map through `Mappers/BackupSessionMapper.swift`.

`WorkSession` (domain): `id`, `start: Date`, `end: Date?` — `end == nil` means the
session is open (clocked in). That is the entire model:

- A session belongs to the local-calendar day of its **start**; sessions spanning
  midnight are never split.
- No separate day table, no `isRunning` flag, no break entity (a break is a closed
  session followed by a later clock-in). Day grouping is derived in code from
  `Calendar.startOfDay(for:)`.
- At most one open session. `clockIn` while open and `clockOut` while closed are no-ops.

## Business rules (ported exactly)

1. Presence (a day, or "today") = Σ over sessions of `(end ?? now) − start`. The live
   timer is always derived from `now`; never accumulated or persisted.
2. Net worktime = `max(0, presence − lunch)`. Office target = `work + lunch`
   (defaults: work 8h, lunch 30m → target 8h 30m).
3. Daily overtime = `presence − target`. Shown only when positive, or when negative
   **and** the day is marked ended (while working, being under target is normal
   progress). Format: ≥ 60 min → `1h 05m` style; < 60 min → whole minutes
   (`25 min` / `Undertime: -40 min`).
4. End-of-day marker: "Clock out for today" sets `endedDayStart = today's midnight`;
   any clock-in and break clock-out clear it. `endedToday ⇔ marker != 0 && == today`.
5. History candidate days: `dayStart < today`, plus today itself only when
   `endedToday`. Grouped by calendar month, newest month first; only the newest month
   is expanded initially. Month header: `Σ net` and `Σ (net − work)` — **signed** sums,
   undertime days deduct from the month's overtime. No weekly or yearly aggregation.
6. Punch times come from an hour/minute picker but keep the real current second (so
   the elapsed timer counts from the exact moment); session edits preserve the edited
   timestamp's original second. Settings values are whole minutes (seconds zeroed).
   No `end > start` or overlap validation exists in the original; keep that behavior.
7. All day/month boundaries in local calendar time; all math exact (no rounding);
   display truncates to minutes (live timer: to seconds).

## UI (bottom TabView: Today | History | Settings)

**Today tab** — top to bottom:
- Live `Now HH:mm:ss` line and a 1-second ticker (`TimelineView(.periodic(1s))`).
- Hero card (brand gradient #6A5AE0→#A64BF4, warm variant for the break button):
  progress ring toward target, big `H:MM:SS` presence timer, `NN% of 8h 30m`,
  overtime/undertime line per rule 3, status line with the four states
  ("At the office since HH:mm" / "Done for today" / "On a break — Clock in to
  continue" / "Not at the office"), and — only while clocked in — the predicted
  `Workday finishes at HH:mm` (`now + (target − presence)`; "finished" once past).
- Buttons: clocked in → `Clock out for a break` (gradient) + `Clock out for today`
  (outlined); clocked out → `Clock in` / `Clock back in` (when there is time today).
  Each opens a 24-hour time picker dialog.
- `Worktime: Xh Ym` net line + `In office Xh Ym · lunch -30m` breakdown.
- Today's sessions list: `09:12 – now` / `09:12 – 12:45` + duration. Tap → edit
  dialog: Start / End pickers (end only if closed) and Delete.

**History tab** — empty state `No previous days yet.`; otherwise month sections
(`DisclosureGroup`): month name (`LLLL yyyy`), `Worktime Xh Ym` and
`Overtime`/`Undertime` totals, day rows (`EEE, MMM d`, `In office Xh Ym · N sessions`,
net, signed ±overtime), tap → read-only sheet listing the day's sessions with
durations. No editing/deleting from History.

**Settings tab** — Worktime section: Work time row (`Actual work you owe per day`),
Lunch length row (`Added to the office target, deducted from worktime`), each opening
an hours:minutes picker; live `Office target: 8h 30m (work + lunch)` line.
Haptics section: enable switch, strength slider, pattern choice (Single/Double/
Triple/Long → Core Haptics), test button; fired on every punch and widget tap.
Backup section: export (share sheet, JSON) and import (document picker) with a
replace-or-merge choice; replace wipes sessions first, merge appends without
deduplication. Same JSON shape as MagniTools v3 for worktime/settings sections
(`{start, end}` array; dayStart recomputed on import), so Android backups import.
Version footer.

## Widget

WidgetKit extension, small 2×1-family widget:
- Status line: `In since HH:mm` / `Done for today` / `Not clocked in`.
- Clock-in button: punch at wall-clock now (no-op + "already" handling when open);
  clears the ended marker.
- Clock-out button: closes the open session and **always marks the day ended**
  (asymmetric with in-app break clock-out — this matches Android).
- Tap-to-open lands on the Today tab.
- Interactive buttons via App Intents (iOS 17); both targets read/write the App Group
  SwiftData store; widget reloads itself and the app refreshes on foreground.

## Pre-work (before the port)

Fix the reviewed Localization.swift bugs — in the app **and** the Tuist stencils:
1. Locale detection: derive the language from `Locale.current.language.languageCode`,
   not `Locale.current.identifier` (which never equals "en"/"hu" and pins English on
   every fresh install).
2. Isolation: make `Localization` an actor (or @MainActor) — no unsynchronized shared
   mutable state.
3. Missing-key fallback: `localizedString(forKey:value:table:)` with `value: nil`, so
   absent keys fall back to the base language instead of showing the raw key.
4. Replace the debug `print()` in AppDelegate with the linked `os.Logger`/swift-log;
   remove the dead `appController?.didRegisterForPush` comment residue.

## Localization

All new UI strings go through the existing `Strings.stencil` / `.strings` system in
**en and hu** (the source app hardcoded English; the target app already has the
localization infrastructure and a Hungarian user). Duration formats (`8h 30m`,
`H:MM:SS`) and time formats stay locale-aware via `DateFormatter`/`Duration`.

## Testing

Unit tests (Swift Testing) against an in-memory SwiftData store:
- day-boundary math (local midnight, month grouping, DST-adjacent dates),
- overtime/undertime display rules (incl. ended-day gating and <60-min formatting),
- clockIn/clockOut no-op guards and single-open-session invariant,
- history month grouping and signed monthly sums,
- backup export → import round-trip, replace and merge, MagniTools v3 import.

## Out of scope

Poop tracker, color-theme pickers, Android's Home screen, notifications/alarms
(none exist in the source feature), weekly/yearly summaries (don't exist upstream).

## Open items

- Committing (spec, plan, implementation) is done by the user only, per global rules.
- Alamofire/Lottie/Swinject/Logging stay linked for now (Toolkit removed as approved);
  prune when it's clear nothing will use them.