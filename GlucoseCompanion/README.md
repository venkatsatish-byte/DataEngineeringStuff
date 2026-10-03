# GlucoseCompanion (working name)

An iPhone and Apple Watch app that helps people with Type 2 diabetes track
blood sugar, understand their daily trends, and get practical diet and
exercise suggestions that support better glucose control.

> **Not a medical device.** The app does not give insulin or medication dosing
> advice and is not a substitute for medical care. Users are told to consult
> their doctor before changing diet, exercise or medication.

## Status

Design phase. Nothing is built yet.

| Document | Contents |
|---|---|
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | MVVM architecture, targets, folder structure, data models, HealthKit and sync strategy, safety design |
| [docs/MVP_SCOPE.md](docs/MVP_SCOPE.md) | What ships in the MVP, v1 and v2, and the open questions that shape the build |

## Platforms

- iOS 17+ (SwiftUI, SwiftData, Swift Charts, WidgetKit)
- watchOS 10+ (SwiftUI, WidgetKit complications)
- HealthKit for glucose (CGM and fingerstick), steps, workouts, heart rate, sleep, and dietary data
- No servers or third-party analytics. Health data stays on the device and in the user's own Apple Health.
