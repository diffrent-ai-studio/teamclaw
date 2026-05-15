# TeamClaw Android

Native Android port of the TeamClaw AI Agent Platform.

## Stack

- Kotlin 2.1 + Jetpack Compose + Material3
- Gradle 8.10 KTS + Version Catalog (`gradle/libs.versions.toml`)
- Hilt (DI), Supabase (backend), Sentry (observability)

## Modules

| Module | Purpose |
|---|---|
| `:app` | Application entry point |
| `:core:design` | Design system (tokens, components) |
| `:core:model` | Shared domain models |
| `:core:deeplink` | Deep-link routing |
| `:core:network` | Ktor/Supabase clients |
| `:core:auth` | Auth state + Supabase OTP |
| `:feature:onboarding` | Email OTP onboarding flow |

## Prerequisites

- JDK 21 (Temurin recommended)
- Android SDK (API 35 target, API 26 min)

## Build

```bash
# From repo root
./apps/android/gradlew -p apps/android assembleDebug
```

## Secrets

Copy `secrets.defaults.properties` → `secrets.properties` and fill in any
values that differ from defaults (e.g. your own OAuth client ID).
`secrets.properties` is gitignored.
