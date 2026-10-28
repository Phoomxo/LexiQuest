# LexiQuest Android Built-in Kotlin Migration Deferral

Date: 2026-07-27
Branch: `feature/production-vertical-slices`
Status: Deferred, not abandoned

## Decision

Strict Built-in Kotlin migration for the Android build is **deferred, not
abandoned**. The compatibility flags `android.builtInKotlin=false` and
`android.newDsl=false`, together with the settings-level
`org.jetbrains.kotlin.android` 2.3.20 `apply false` pin, remain load-bearing
until an objective removal gate (below) is satisfied. The normal Android debug
APK build succeeds with this configuration.

## Verified toolchain (2026-07-27)

- Flutter stable 3.44.7; Dart 3.12.2.
- Android SDK 36.1; Android Gradle Plugin 9.0.1; Gradle 9.1.0.
- Kotlin Gradle Plugin 2.3.20.
- JDK 21 runtime; Java and Kotlin bytecode target 17.

## Verified compatibility configuration

- `android/gradle.properties` sets `android.newDsl=false` and
  `android.builtInKotlin=false`, retaining Flutter's temporary AGP 9
  compatibility shim for plugins that still apply the Kotlin Gradle Plugin.
- `android/settings.gradle.kts` declares
  `id("org.jetbrains.kotlin.android") version "2.3.20" apply false`, so the
  Kotlin Gradle Plugin is resolved at the settings layer but not auto-applied;
  consumers that still need KGP apply it themselves.
- `android/app/build.gradle.kts` applies `dev.flutter.flutter-gradle-plugin`,
  pins Java source/target compatibility to 17, and sets the Kotlin
  `jvmTarget` to `JVM_17`.

## Why the flags and pin are load-bearing today

Flutter's AGP 9 compatibility path still routes the Android Application
extension through a type that the Flutter Gradle plugin expects. Holding both
flags false keeps that shim active so the existing module graph configures.
Removing either flag before the toolchain supports the strict path surfaces the
cast that today occurs only under strict mode during normal configuration. The
settings-level KGP pin is required in parallel: the modules that still apply KGP
must resolve a single, consistent Kotlin Gradle Plugin version, and
`apply false` prevents that pin from forcing KGP onto modules that do not need
it.

## Strict-mode experiment and failure

A non-mutating experiment was run with Gradle system project properties only:

- `-Dorg.gradle.project.android.builtInKotlin=true`
- `-Dorg.gradle.project.android.newDsl=true`

No repository file, pub-cache entry, or plugin source was modified. With both
flags forced true, configuration fails while applying
`dev.flutter.flutter-gradle-plugin` from `android/app/build.gradle.kts`. The
concrete failure is a ClassCastException-equivalent message:
`ApplicationExtensionImpl cannot be cast to AbstractAppExtension`. The
immediate blocker therefore lives in Flutter's own Gradle plugin, not in a
third-party package build script.

## Upstream plugin owners

Flutter's normal build compatibility warning identifies exactly two packages
that directly apply the Kotlin Gradle Plugin:

- `flutter_tts` 4.2.5
- `speech_to_text` 7.4.0

Both are direct dependencies in `pubspec.yaml` and `pubspec.lock`. They are the
upstream owners to track for Built-in Kotlin compatibility. They are distinct
from the immediate strict-mode failure above: even after Flutter's own Gradle
plugin supports the strict AGP 9 path, these two packages must stop applying
KGP before the compatibility surface can be removed.

Note: the earlier stabilization record listed four KGP consumers
(`firebase_storage`, `flutter_tts`, `fluttertoast`, `speech_to_text`).
`firebase_storage` and `fluttertoast` were subsequently removed as unused
dependencies, leaving `flutter_tts` and `speech_to_text`.

## Future removal gate

Remove the compatibility surface only when the same commit satisfies all of:

1. Flutter supports the strict AGP 9 path without the
   `ApplicationExtensionImpl`/`AbstractAppExtension` cast failure.
2. A normal build reports no packages applying KGP.
3. Remove `android.builtInKotlin=false` and `android.newDsl=false` together,
   then remove the settings-level `org.jetbrains.kotlin.android` pin only
   after confirming zero legacy consumers.
4. `flutter analyze`, `flutter test`, and `flutter build apk --debug` all pass.

## Cache integrity constraint

Never patch, hot-edit, or overlay source in
`C:\Users\Phet\AppData\Local\Pub\Cache` (or any other pub-cache location) to
force a build. Workarounds applied to cached packages are invisible to
teammates, fail to reproduce in CI, and are overwritten on the next resolve.
All changes must be expressed in tracked repository files or upstream releases.
