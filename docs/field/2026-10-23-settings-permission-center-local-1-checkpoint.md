# SETTINGS-PERMISSION-CENTER-LOCAL-1 checkpoint

## Status and authority

- Date: 2026-10-23, Asia/Bangkok
- Worktree: `C:\Users\Phet\Documents\LexiQuest`
- Branch: `feature/associative-reading-loop`
- HEAD: `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1` (unchanged; no commit)
- Authority: bounded Settings A3 Device Permission Center card, one production writer and serialized Flutter checks.
- ADLC: Intent, Ground, Plan, Execute, Review and Attest completed.
- Status: local engineering complete. This is not deployment or Android hardware acceptance.

## Grounded behavior

- `MediaPermissionState` remains the shared five-state contract.
- The installed `permission_handler` package remains the Android permission source; no dependency, manifest, preference or schema authority was added.
- The new application port separates permission state from plugin access, preserving the participant-screen architecture boundary.
- Opening Settings or Permission Center reads current camera and microphone status only. It never calls a permission request API.
- Android app settings open only after the user presses the explicit button shown for permanent denial.

## Bounded change

1. `lib/features/media_practice/application/device_permission_access.dart`
   - Adds the narrow read/open-settings application port.
2. `lib/features/media_practice/data/plugin_device_permission_access.dart`
   - Reads `Permission.camera.status` and `Permission.microphone.status`.
   - Maps plugin-only limited/provisional states to unavailable and delegates explicit `openAppSettings()`.
3. `lib/runtime/app_dependencies.dart` and `lib/runtime/app_bootstrap.dart`
   - Compose one production adapter without changing lifecycle ownership or disposal.
4. `lib/screens/device_permission_center_screen.dart`
   - Shows plain-Thai camera/microphone state, fails closed, refreshes on app resume, blocks repeated settings taps and ignores stale async results after refresh, replacement or disposal.
   - Re-resolves the scoped permission adapter when an explicit widget injection is removed, so an obsolete adapter cannot remain active.
   - Announces refreshed camera and microphone states through TalkBack live regions.
   - Supports scroll/reflow and a 48dp Android Settings action.
5. `lib/screens/setting_screen.dart`
   - Adds one Settings row to the real Permission Center destination.
6. Focused tests
   - Adapter mapping and explicit settings delegation.
   - Read-only opening, all five statuses, failure privacy, explicit/single-flight settings action, resume refresh, dependency replacement, same-access refresh races and 200% responsive layouts.
   - Settings navigation and bootstrap composition.

No schema, generated source, dependency, Android manifest, preference store, media request gateway, research contract, Source Practice or Tutor behavior changed.

## TDD and recovery evidence

- Initial RED: both new focused tests failed to compile because the application port, plugin adapter and Permission Center screen did not exist.
- First GREEN: adapter/state/lifecycle/navigation behavior passed, while two layout tests showed controls were below the lazy-list viewport. The tests were corrected to scroll the real list before interacting; no product workaround was added.
- Race RED: a delayed initial read could overwrite a newer resume refresh. Separate access and status generations now make the latest refresh authoritative; the regression test passed after the focused fix.
- Review RED: replacing a non-null injected adapter with `null` left the old adapter active (`fallback.cameraReads` stayed `0`). `didUpdateWidget` now resolves `widget.permissionAccess ?? AppDependenciesScope.maybeOf(context)?.devicePermissions`; the scope-fallback regression passes.
- Accessibility RED: refreshed statuses had no keyed live-region semantics node. Each camera/microphone status now has a `Semantics(liveRegion: true)` label containing the permission name and current Thai status; the resume-refresh regression passes.

## Final verification on current source

```powershell
flutter test --no-pub test/features/media_practice/plugin_device_permission_access_test.dart test/screens/device_permission_center_screen_test.dart test/screens/setting_screen_test.dart test/runtime/app_bootstrap_test.dart --reporter expanded
```

Result: exit 0, **66/66 passed**.

```powershell
flutter test --no-pub test/architecture/participant_screen_boundary_test.dart --reporter expanded
```

Result: exit 0, **1/1 passed**.

```powershell
flutter analyze --no-pub lib/features/media_practice/application/device_permission_access.dart lib/features/media_practice/data/plugin_device_permission_access.dart lib/runtime/app_dependencies.dart lib/runtime/app_bootstrap.dart lib/screens/device_permission_center_screen.dart lib/screens/setting_screen.dart test/features/media_practice/plugin_device_permission_access_test.dart test/screens/device_permission_center_screen_test.dart test/screens/setting_screen_test.dart test/runtime/app_bootstrap_test.dart
dart format --output=none --set-exit-if-changed <the same 10 files>
git diff --check -- <tracked files in the card>
```

- Scoped analyzer: exit 0, no issues.
- Formatter: exit 0, 10 files / 0 changed.
- Architecture boundary: passed; participant screens do not import `permission_handler`.
- Tracked scoped diff check: exit 0; Git emitted existing LF-to-CRLF notices only.
- Several card files are untracked in the shared checkout, so Git has no index baseline for a normal diff check; Dart format and analyzer covered their final source.

## Verified source manifest (SHA-256)

| Path | SHA-256 |
| --- | --- |
| `lib/features/media_practice/application/device_permission_access.dart` | `C92303C5D1348707E613E7B5F612A89E15F744A352AF52D8B509A22831838BB8` |
| `lib/features/media_practice/data/plugin_device_permission_access.dart` | `FCB23B9060E2C1D22631DD225110AF05854F43F9F508AB98454D2F986878F885` |
| `lib/runtime/app_dependencies.dart` | `EA0D437535C5803E3E5BA760F444B8635FE26CB92D4D51CB7CFE00F5D52BB2DE` |
| `lib/runtime/app_bootstrap.dart` | `FDE77F117C1CCB2A769B2D338A41DA78CF02DF9B2092602717AB8093F4321852` |
| `lib/screens/device_permission_center_screen.dart` | `9C5CF4250D60C30249D28A841E5AA67DABFC550D7DC8BBDA864A1A8323DC5CF3` |
| `lib/screens/setting_screen.dart` | `9599A0FAE44B61E6C173822A31EA0F17F3F38323BBFC26FD193147CCDFE27454` |
| `test/features/media_practice/plugin_device_permission_access_test.dart` | `0C288F20EAB7B3313DBAAA4640BC7FE1CE45E07B161B16C6BE02873164B2A8EB` |
| `test/screens/device_permission_center_screen_test.dart` | `DDB87872D5FA5F525DFF6B1782B0A4241A5D900FF9F05CB1A12F89BA1DF47A3E` |
| `test/screens/setting_screen_test.dart` | `67C3C40058F7A094C658F04D8A1662B1FF5829E6A654EBFBF822F27A054938EC` |
| `test/runtime/app_bootstrap_test.dart` | `098C86BA775335014CAD3B7B3FC3AE7313F9FF4FB732477DD2C04CE4B3DF1B19` |

## Review disposition and remaining integration work

- Accepted: local A3 behavior, plugin boundary, latest-refresh authority, dependency fallback, TalkBack status announcements, accessibility layout and focused composition evidence.
- Not run in this card: full repository regression, APK build, emulator matrix or physical Android Settings round trip. LQ-00 owns those integration checks on the current source snapshot.
- Risk: plugin status and return-from-settings behavior still require confirmation on real Android OEM permission screens; restricted/limited/provisional states deliberately fail closed.
