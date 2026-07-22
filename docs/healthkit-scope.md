# HealthKit Permissions

Read-only access requested at first launch. No write permissions in v1 — the app consumes HealthKit data, doesn't push to it.

## Requested read permissions

### Body composition
- `HKQuantityTypeIdentifier.bodyMass`
- `HKQuantityTypeIdentifier.bodyFatPercentage`
- `HKQuantityTypeIdentifier.leanBodyMass`
- `HKQuantityTypeIdentifier.bodyMassIndex`

### Activity & workouts
- `HKObjectType.workoutType()`
- `HKQuantityTypeIdentifier.activeEnergyBurned`
- `HKQuantityTypeIdentifier.basalEnergyBurned`
- `HKQuantityTypeIdentifier.appleExerciseTime`
- `HKQuantityTypeIdentifier.stepCount`
- `HKQuantityTypeIdentifier.distanceWalkingRunning`

### Cardiovascular
- `HKQuantityTypeIdentifier.restingHeartRate`
- `HKQuantityTypeIdentifier.heartRateVariabilitySDNN`

### Sleep
- `HKCategoryTypeIdentifier.sleepAnalysis`

## Deliberately excluded

- `vo2Max` — noisy, not decision-relevant during recomp
- Nutrition types — logging happens in-app, not via HealthKit
- Mindfulness, cycle tracking, etc. — out of scope

## Sync strategy

- **Initial sync:** on first HealthKit authorization, pull last 90 days of all authorized types
- **Ongoing sync:** `HKObserverQuery` + background delivery for real-time updates
- **Reconciliation:** every write includes the HealthKit UUID for dedup; if HealthKit revises a value, we update the corresponding row in `body_metrics`

## Vendor-specific scale metrics

Smart scales (Withings, Renpho, Eufy, etc.) push varying subsets of body composition data. Bone mass, body water %, and visceral fat rating are captured via the same HealthKit types when available. If a scale doesn't push a given metric, the field stays NULL — no fallback, no estimation.

## Info.plist keys required

- `NSHealthShareUsageDescription`
- `NSHealthUpdateUsageDescription` (not used in v1, but requesting it now avoids a re-authorization prompt if we add write support later)
