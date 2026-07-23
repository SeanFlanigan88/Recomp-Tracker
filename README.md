# Recomp Tracker

Personal body recomposition tracking app. Native iOS + macOS, HealthKit integration, CloudKit sync, local-first data.

## Purpose

A single destination for logging and analyzing all the inputs that drive body recomposition: workouts, body composition metrics, subjective daily state, nutrition, and progress photos. Designed for one user (me) but architected to generalize.

The phone is the primary logging surface — quick capture at the gym, taking measurements, morning check-ins. The Mac is for analysis, review, and iterating on the app itself.

## Architecture

- **iOS + macOS SwiftUI app**, shared code via a Swift Package (`RecompCore`)
- **GRDB (SQLite)** for local persistence — typed, migratable, testable
- **CloudKit** for cross-device sync (iCloud, private database)
- **HealthKit** for automatic import of body composition, activity, sleep, and cardiovascular metrics
- **CKAsset** for progress photos (blob storage, on-demand sync)

See `docs/` for detailed decisions and rationale.

## Repository structure

    recomp-tracker/
    ├── docs/
    │   ├── schema.md               Full data model + rationale
    │   ├── healthkit-scope.md      HealthKit permissions requested + why
    │   ├── sync-strategy.md        CloudKit architecture, CKAsset handling
    │   └── decisions/              Architecture Decision Records (ADRs)
    ├── shared/
    │   └── Sources/RecompCore/     Cross-platform data models, migrations, logic
    ├── ios/                        iOS app target
    └── macos/                      macOS app target (added later)

## Project setup

- **Bundle identifier:** `com.seanflanigan.recomptracker`
- **Minimum iOS version:** 17.0
- **Minimum macOS version:** 14.0
- **Xcode:** 26.6+

## Getting started

Clone:

    git clone git@github.com:SeanFlanigan88/Recomp-Tracker.git recomp-tracker
    cd recomp-tracker

Open `ios/RecompTracker/RecompTracker.xcodeproj` in Xcode and build for an iOS simulator. The shared data layer lives in `shared/` as a local Swift package (`RecompCore`) that the iOS target depends on. Package tests run via `swift test` from `shared/`.

## Roadmap

- [x] Schema, ADRs, project scaffold
- [ ] Xcode project + SwiftUI tab shell
- [x] GRDB integration + initial migration
- [ ] JSON import from legacy tracker (`cycle2-tracker.html` export format)
- [ ] Manual daily log + workout logging
- [ ] HealthKit read integration
- [ ] Progress photo capture with pose modifiers
- [ ] CloudKit sync layer
- [ ] macOS target
- [ ] Analysis views (trends, correlations, check-in generation)
