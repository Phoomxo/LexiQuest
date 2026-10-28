# Task 4 — Remove the retired Supabase package

## Implementation

- Moved `supabase_flutter` from the retained dependency list to the removed list in `test/config/flutter_dependency_surface_test.dart`.
- Removed `supabase_flutter: ^2.16.0` from `pubspec.yaml`.
- Ran `flutter pub get`, which removed `supabase_flutter`, its Supabase transitive graph, and only the corresponding generated Linux, macOS, and Windows plugin-registrant entries.

## RED/GREEN evidence

- RED: `flutter test test/config/flutter_dependency_surface_test.dart` exited 1. The removed-dependencies test failed exactly because `supabase_flutter` was still a direct dependency.
- GREEN: `flutter test test/config/flutter_dependency_surface_test.dart test/runtime/app_bootstrap_test.dart test/shop/product_artwork_test.dart` exited 0 with 15 passing tests.

## Commands and results

- `flutter pub get` — exited 0; removed 27 unneeded dependencies.
- Focused dependency and compilation tests — exited 0; 15 passed.
- `flutter test` — exited 0; 696 passed.
- `git diff --check` — exited 0.

## Generated files accepted

- `pubspec.lock`
- `linux/flutter/generated_plugin_registrant.cc`
- `linux/flutter/generated_plugins.cmake`
- `macos/Flutter/GeneratedPluginRegistrant.swift`
- `windows/flutter/generated_plugin_registrant.cc`
- `windows/flutter/generated_plugins.cmake`

## Self-review

- Confirmed `supabase_flutter` is absent from `pubspec.yaml`, `pubspec.lock`, and the generated platform registrants.
- Confirmed each generated deletion corresponds to packages removed by the resolver after retiring Supabase.
- No unrelated production, historical documentation, migration, or CI files were changed.

## Concerns

- The pre-existing `jni 1.0.1` retraction remains reported after the package removal; no unrelated dependency upgrade was performed.
