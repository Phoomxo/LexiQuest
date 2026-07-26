# LexiQuest Production Foundation Integration Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the current LexiQuest Android build enter the real production navigation, establish an authenticated guest session, connect safely to LAN backends in debug builds, and provide CLI diagnostics that cannot disturb active GPU training.

**Architecture:** Add a CPU-only PowerShell control plane that treats GPU training as a protected workload, then introduce a small Flutter composition root around validated public runtime configuration and authentication. Android permits cleartext only in the debug source set while Dart restricts HTTP to loopback/emulator/private-LAN addresses. The new five-destination learning shell becomes `/home`; legacy categories, shop, and settings remain reachable from a drawer.

**Tech Stack:** Flutter/Dart 3.12+, Firebase Authentication, Provider, Android manifest overlays/network security XML, PowerShell 7/Windows PowerShell 5.1, Flutter test, Python backend health endpoints.

## Global Constraints

- Never stop, suspend, reprioritize, attach a debugger to, or start a competing CUDA workload while `lora_finetune.py --train` is active.
- Cointh/GLM-5.2 with `--effort max` proposes each bounded RED/GREEN change; Codex reviews, applies, and verifies every change.
- Do not commit `.zcode/`, local provider keys, `.env` files, runtime PIDs, or logs.
- Android is the primary acceptance platform. Windows and Web receive smoke checks; iOS/macOS/Linux receive compile/configuration compatibility checks only in this phase.
- Release builds accept HTTPS backend origins only. Debug builds accept HTTP only for loopback, the Android emulator host alias, or RFC 1918 private IPv4 addresses.
- Server credentials and provider keys stay outside the Flutter bundle. Public Firebase/Supabase client identifiers are configuration, not server secrets, but should be centralized in a later deployment-hardening phase.
- Every behavior change begins with a failing automated test. If a proposed test passes before implementation, revise the test until it proves the missing behavior.
- Use Thai UTF-8 source text for user-facing strings touched by this plan; do not perpetuate mojibake.

---

## Task 1: Protected GPU Runtime Probes and CLI Doctor

**Files:**

- Create: `tool/cli/lib/runtime-probes.ps1`
- Create: `tool/cli/tests/runtime-probes.tests.ps1`
- Create: `tool/cli/doctor.ps1`
- Modify: `.gitignore`

**Contract:**

```powershell
function Test-LexiQuestTrainingProcess {
    [CmdletBinding()]
    param([object[]] $Processes)
    # True only when a command line contains lora_finetune.py and --train.
}

function Get-LexiQuestGpuSnapshot {
    [CmdletBinding()]
    param([scriptblock] $NvidiaSmiRunner)
    # Returns a data object; never starts or controls a GPU process.
}

function Get-LexiQuestRuntimeGuard {
    [CmdletBinding()]
    param([object[]] $Processes, [scriptblock] $NvidiaSmiRunner)
    # Returns TrainingActive, GpuAvailable, UsedMemoryMiB, UtilizationPercent,
    # and MayStartGpuInference. It never mutates system state.
}
```

- [x] **Step 1: Ask GLM for a test-only RED proposal**

Use a bounded prompt that includes the contract above, Windows PowerShell 5.1 compatibility, and a prohibition on process mutation.

- [x] **Step 2: Write the failing probe tests**

The custom test script must cover:

```powershell
$training = [pscustomobject]@{
    ProcessId = 42
    CommandLine = 'python lora_finetune.py --train'
}
$unrelated = [pscustomobject]@{
    ProcessId = 43
    CommandLine = 'python api.py'
}

Assert-True (Test-LexiQuestTrainingProcess -Processes @($training))
Assert-False (Test-LexiQuestTrainingProcess -Processes @($unrelated))
Assert-False (Test-LexiQuestTrainingProcess -Processes @())
```

Also assert that malformed `nvidia-smi` output produces `GpuAvailable = $false` and blocks GPU inference rather than throwing.

- [x] **Step 3: Run RED**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/runtime-probes.tests.ps1
```

Expected: fail because `tool/cli/lib/runtime-probes.ps1` or its functions do not exist.

- [x] **Step 4: Ask GLM for the minimal GREEN implementation**

Require dependency injection for process and GPU samples so tests never call or control real processes.

- [x] **Step 5: Implement the probes and doctor**

`doctor.ps1` may use only read-only operations:

```powershell
Get-CimInstance Win32_Process
nvidia-smi --query-gpu=index,name,memory.used,memory.total,utilization.gpu,temperature.gpu --format=csv,noheader,nounits
```

The doctor must print one compact object and exit:

- `0` when the environment is inspectable, including when protected training is active.
- non-zero only when required tooling or repository paths are missing.

It must prominently report `MayStartGpuInference = False` while training is active.

- [x] **Step 6: Ignore runtime state**

Add:

```gitignore
tool/cli/.runtime/
tool/cli/logs/
```

- [x] **Step 7: Run GREEN and the live read-only doctor**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/runtime-probes.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/doctor.ps1
```

Expected: tests pass; live doctor reports active training and does not start or stop anything.

- [x] **Step 8: Commit**

```powershell
git add .gitignore tool/cli/lib/runtime-probes.ps1 tool/cli/tests/runtime-probes.tests.ps1 tool/cli/doctor.ps1
git commit -m "feat(cli): protect active GPU training"
```

---

## Task 2: Debug Private-LAN Application Configuration

**Files:**

- Modify: `test/config/app_config_test.dart`
- Modify: `lib/config/app_config.dart`

**Contract:**

```dart
final config = AppConfig.fromValues(
  voiceApiUrl: 'http://192.168.1.20:8001',
  aiApiUrl: 'http://192.168.1.20:8000',
  isDebug: true,
);
```

This succeeds. The following stay rejected:

- `http://example.com`
- `http://8.8.8.8`
- `http://172.15.255.255`
- `http://172.32.0.1`
- every HTTP origin in release mode
- IPv6 cleartext until an explicit LAN IPv6 policy is designed

- [x] **Step 1: Ask GLM for RED cases**

Require boundary coverage for:

- `10.0.0.0/8`
- `172.16.0.0/12`
- `192.168.0.0/16`
- loopback `127.0.0.1`
- emulator alias `10.0.2.2`

- [x] **Step 2: Add failing table-driven tests**

Move private hosts out of `_nonLocalHttpHosts` and add accepted debug cases, including the lower and upper `172.16/12` boundaries.

- [x] **Step 3: Run RED**

Run:

```powershell
flutter test test/config/app_config_test.dart
```

Expected: private-LAN accepted cases fail with `AppConfigException`.

- [x] **Step 4: Ask GLM for minimal GREEN**

Require a pure helper such as:

```dart
static bool _isDebugHttpHostAllowed(String host)
```

It must parse IPv4 octets numerically, reject malformed values, DNS names, IPv6, and public addresses, and never echo hostile input in an exception.

- [x] **Step 5: Implement and run GREEN**

Run:

```powershell
dart format lib/config/app_config.dart test/config/app_config_test.dart
flutter test test/config/app_config_test.dart
```

Expected: all AppConfig tests pass.

- [x] **Step 6: Commit**

```powershell
git add lib/config/app_config.dart test/config/app_config_test.dart
git commit -m "feat(config): allow private LAN backends in debug"
```

---

## Task 3: Android Debug-Only Cleartext Policy

**Files:**

- Create: `android/app/src/debug/AndroidManifest.xml`
- Create: `android/app/src/debug/res/xml/network_security_config.xml`
- Create: `test/config/android_network_security_test.dart`

**Policy:**

- Main/release manifest must not set `android:usesCleartextTraffic="true"`.
- Debug overlay references `@xml/network_security_config`.
- The debug XML permits cleartext because Android XML cannot enumerate arbitrary developer LAN subnets reliably; Dart `AppConfig` remains the narrower application-level allowlist.
- Release configuration remains HTTPS-only at both manifest and Dart layers.

- [x] **Step 1: Ask GLM for a structural RED test**

The test should read repository files through `File` and validate the two-layer policy without invoking Gradle.

- [x] **Step 2: Add the failing test**

Assertions:

```dart
expect(mainManifest, isNot(contains('usesCleartextTraffic="true"')));
expect(debugManifest, contains('@xml/network_security_config'));
expect(debugConfig, contains('cleartextTrafficPermitted="true"'));
```

Also assert the cleartext declaration exists only under `android/app/src/debug`.

- [x] **Step 3: Run RED**

Run:

```powershell
flutter test test/config/android_network_security_test.dart
```

Expected: fail because the debug manifest and XML do not exist.

- [x] **Step 4: Ask GLM for minimal GREEN and implement**

Use a manifest overlay containing only the application attribute required for debug network security.

- [x] **Step 5: Run GREEN and manifest merge smoke check**

Run:

```powershell
flutter test test/config/android_network_security_test.dart
flutter build apk --debug --dart-define=LEXIQUEST_VOICE_API_URL=http://10.0.2.2:8001 --dart-define=LEXIQUEST_AI_API_URL=http://10.0.2.2:8000
```

Expected: test passes and debug APK builds without changing the release manifest.

- [x] **Step 6: Commit**

```powershell
git add android/app/src/debug test/config/android_network_security_test.dart
git commit -m "feat(android): permit debug LAN backend access"
```

---

## Task 4: Authenticated Anonymous Guest Session

**Files:**

- Create: `lib/services/guest_session_service.dart`
- Create: `test/services/guest_session_service_test.dart`
- Modify: `lib/screens/login_screen.dart`
- Create: `test/screens/login_guest_mode_test.dart`

**Contract:**

```dart
enum GuestSessionFailure {
  firebaseUnavailable,
  providerDisabled,
  network,
  unknown,
}

sealed class GuestSessionResult {
  const GuestSessionResult();
}

final class GuestSessionStarted extends GuestSessionResult {
  const GuestSessionStarted({required this.uid});
  final String uid;
}

final class GuestSessionFailed extends GuestSessionResult {
  const GuestSessionFailed(this.reason);
  final GuestSessionFailure reason;
}

abstract interface class GuestSessionService {
  Future<GuestSessionResult> start();
}
```

`FirebaseGuestSessionService` wraps `FirebaseAuth.signInAnonymously()`. A guest reaches `/home` only after `GuestSessionStarted`. Failure stays on login and shows a fixed Thai action message with no credential or provider response leakage.

- [x] **Step 1: Ask GLM for service RED tests**

Use an injected callback or narrow auth adapter; do not initialize Firebase in unit tests.

- [x] **Step 2: Write failing service tests**

Cover success and mapping of Firebase codes:

- `operation-not-allowed` → `providerDisabled`
- `network-request-failed` → `network`
- missing Firebase app → `firebaseUnavailable`
- everything else → `unknown`

- [x] **Step 3: Run service RED**

Run:

```powershell
flutter test test/services/guest_session_service_test.dart
```

Expected: fail because the service contract does not exist.

- [x] **Step 4: Ask GLM for service GREEN, implement, and verify**

Run:

```powershell
dart format lib/services/guest_session_service.dart test/services/guest_session_service_test.dart
flutter test test/services/guest_session_service_test.dart
```

- [x] **Step 5: Ask GLM for widget RED tests**

Make `LoginScreen` accept an optional `GuestSessionService`. Test:

- button shows progress and cannot be double-submitted;
- success replaces login with `/home`;
- failure does not navigate and displays the fixed message;
- disposal during the async call causes no `setState after dispose`.

- [x] **Step 6: Add widget RED and run it**

Run:

```powershell
flutter test test/screens/login_guest_mode_test.dart
```

Expected: fail because `LoginScreen` has no injectable guest session and navigates immediately.

- [x] **Step 7: Implement minimal widget GREEN**

Replace the direct guest navigation with `_startGuestSession()`. Preserve the existing email/password flow.

- [x] **Step 8: Run focused and related tests**

Run:

```powershell
dart format lib/screens/login_screen.dart test/screens/login_guest_mode_test.dart
flutter test test/services/guest_session_service_test.dart test/screens/login_guest_mode_test.dart
```

Expected: all pass.

- [x] **Step 9: Commit**

```powershell
git add lib/services/guest_session_service.dart lib/screens/login_screen.dart test/services/guest_session_service_test.dart test/screens/login_guest_mode_test.dart
git commit -m "feat(auth): authenticate anonymous guest sessions"
```

---

## Task 5: Safe Application Bootstrap and Runtime Status

**Files:**

- Create: `lib/runtime/app_bootstrap.dart`
- Create: `lib/runtime/app_dependencies.dart`
- Create: `lib/runtime/app_runtime_status.dart`
- Create: `test/runtime/app_bootstrap_test.dart`
- Modify: `lib/main.dart`

**Contract:**

The app must always render a useful screen even when Firebase, Supabase, or endpoint configuration is unavailable. Bootstrap records typed status instead of swallowing initialization exceptions.

```dart
enum RuntimeAvailability { ready, degraded, unavailable }

final class AppRuntimeStatus {
  const AppRuntimeStatus({
    required this.firebase,
    required this.supabase,
    required this.backends,
  });
  final RuntimeAvailability firebase;
  final RuntimeAvailability supabase;
  final RuntimeAvailability backends;
}
```

`AppDependencies` contains only public configuration and injectable service boundaries. It must not contain server keys.

- [ ] **Step 1: Ask GLM for bootstrap RED tests**

Use injected async initializers and a supplied `AppConfig` factory. Do not call real Firebase, Supabase, or the network.

- [ ] **Step 2: Add failing tests**

Cover:

- all initialization succeeds → `ready`;
- Firebase throws → app status is degraded/unavailable but bootstrap returns;
- Supabase throws → bootstrap returns;
- AppConfig missing/invalid → backends unavailable with a safe fixed label;
- no exception text containing supplied sentinel credentials reaches `toString()`.

- [ ] **Step 3: Run RED**

Run:

```powershell
flutter test test/runtime/app_bootstrap_test.dart
```

Expected: fail because bootstrap types do not exist.

- [ ] **Step 4: Ask GLM for minimal GREEN and implement**

Refactor `main()` to:

```dart
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppBootstrap.production().initialize();
  runApp(MyApp(dependencies: dependencies));
}
```

Do not change authentication or navigation behavior in this task.

- [ ] **Step 5: Run GREEN**

Run:

```powershell
dart format lib/main.dart lib/runtime test/runtime/app_bootstrap_test.dart
flutter test test/runtime/app_bootstrap_test.dart
flutter analyze
```

- [ ] **Step 6: Commit**

```powershell
git add lib/main.dart lib/runtime test/runtime/app_bootstrap_test.dart
git commit -m "refactor(app): add safe runtime composition root"
```

---

## Task 6: Canonical Five-Destination Learning Shell

**Files:**

- Modify: `lib/main.dart`
- Modify: `lib/screens/main_navigation_screen.dart`
- Create: `test/screens/production_shell_navigation_test.dart`
- Modify: any existing navigation tests that assert the retired four-tab shell

**Information architecture:**

Primary navigation:

1. เรียนรู้
2. สถิติ
3. จุดอ่อน
4. รางวัล
5. โปรไฟล์

Drawer compatibility destinations:

- คลังหมวดหมู่ → `CategoriesPage`
- ร้านค้า → `ShopPage`
- ตั้งค่าเดิม → `SettingScreen`
- build/runtime status summary

`/home` must create `MainNavigationScreen`, not the retired `MainNavigation`.

- [ ] **Step 1: Ask GLM for navigation RED tests**

Test route construction, five bottom destinations, IndexedStack state preservation, and drawer access to the three legacy destinations.

- [ ] **Step 2: Add failing widget test**

The test must use a deterministic `MaterialApp` and avoid Firebase/network initialization.

- [ ] **Step 3: Run RED**

Run:

```powershell
flutter test test/screens/production_shell_navigation_test.dart
```

Expected: `/home` still resolves to the legacy four-tab shell or the new shell has no drawer.

- [ ] **Step 4: Ask GLM for minimal GREEN and implement**

Delete the duplicate `MainNavigation` class from `main.dart`, import `main_navigation_screen.dart`, and add a drawer to `MainNavigationScreen`. Correct all touched Thai labels to valid UTF-8.

- [ ] **Step 5: Run GREEN and navigation regression tests**

Run:

```powershell
dart format lib/main.dart lib/screens/main_navigation_screen.dart test/screens/production_shell_navigation_test.dart
flutter test test/screens/production_shell_navigation_test.dart
flutter test test
```

Expected: new shell and complete Flutter unit/widget suite pass.

- [ ] **Step 6: Commit**

```powershell
git add lib/main.dart lib/screens/main_navigation_screen.dart test
git commit -m "feat(navigation): make learning shell canonical"
```

---

## Task 7: Visible Build Identity and Android Run Command

**Files:**

- Create: `lib/runtime/app_build_info.dart`
- Create: `test/runtime/app_build_info_test.dart`
- Modify: `lib/screens/main_navigation_screen.dart`
- Create: `tool/cli/run-android.ps1`
- Create: `tool/cli/tests/run-android.tests.ps1`

**Contract:**

```dart
final class AppBuildInfo {
  const AppBuildInfo({required this.version, required this.buildId});

  factory AppBuildInfo.fromEnvironment() => const AppBuildInfo(
    version: String.fromEnvironment(
      'LEXIQUEST_VERSION',
      defaultValue: '1.0.0+1',
    ),
    buildId: String.fromEnvironment(
      'LEXIQUEST_BUILD_ID',
      defaultValue: 'development',
    ),
  );
}
```

The drawer displays a compact non-sensitive identity such as `1.0.0+1 · 22944f2-dirty`. `run-android.ps1` calculates the Git short SHA, detects a dirty tree, accepts `-DeviceId`, `-LanHost`, `-VoicePort` and `-AiPort`, and prints the exact command before invoking Flutter.

- [ ] **Step 1: Ask GLM for Dart and PowerShell RED tests**

PowerShell command construction must be a pure function, allowing tests without launching Flutter or an emulator.

- [ ] **Step 2: Add failing tests and run RED**

Run:

```powershell
flutter test test/runtime/app_build_info_test.dart
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/run-android.tests.ps1
```

Expected: both fail because their contracts do not exist.

- [ ] **Step 3: Ask GLM for minimal GREEN and implement**

The generated Flutter command must include:

```text
--dart-define=LEXIQUEST_BUILD_ID=<short-sha[-dirty]>
--dart-define=LEXIQUEST_VERSION=1.0.0+1
--dart-define=LEXIQUEST_VOICE_API_URL=http://<LanHost>:<VoicePort>
--dart-define=LEXIQUEST_AI_API_URL=http://<LanHost>:<AiPort>
```

Before invoking Flutter, the script must call the Task 1 runtime guard. Active training does not block the Flutter app itself, but the script must state that GPU inference backends are protected/offline.

- [ ] **Step 4: Run GREEN**

Run:

```powershell
dart format lib/runtime/app_build_info.dart lib/screens/main_navigation_screen.dart test/runtime/app_build_info_test.dart
flutter test test/runtime/app_build_info_test.dart
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/run-android.tests.ps1
```

- [ ] **Step 5: Commit**

```powershell
git add lib/runtime/app_build_info.dart lib/screens/main_navigation_screen.dart test/runtime/app_build_info_test.dart tool/cli/run-android.ps1 tool/cli/tests/run-android.tests.ps1
git commit -m "feat(runtime): expose verifiable build identity"
```

---

## Task 8: Foundation Verification and Operator Runbook

**Files:**

- Create: `tool/cli/verify.ps1`
- Create: `docs/runbooks/android-lan-development.md`
- Modify: `README.md`

**Verification sequence:**

1. Protected runtime probe tests.
2. Android runner construction tests.
3. `flutter pub get`.
4. `dart format --output=none --set-exit-if-changed`.
5. `flutter analyze`.
6. Full `flutter test`.
7. Voice API CPU-only tests.
8. AI API CPU-only tests.
9. Local LM CPU-only tests.
10. Android debug APK build with emulator loopback defines.
11. Read-only live GPU doctor.

The script must not start Voice API, Ollama, OmniVoice, the local LM server, or any other CUDA consumer.

- [ ] **Step 1: Ask GLM for a fail-fast verification script and runbook outline**

Require clear phase names, propagated exit codes, and a final summary. No hidden `continue-on-error`.

- [ ] **Step 2: Create `verify.ps1`**

Use explicit working directories and commands already present in the repository. Detect missing optional platform tooling and report `SKIPPED` only for unsupported platform smoke checks, never for Flutter analyze/tests or the three backend unit suites.

- [ ] **Step 3: Document the operator workflow**

The runbook must explain:

- why Developer Mode is sufficient and Device Portal/Device discovery stay off;
- how to find the workstation LAN IPv4 address;
- how to use `doctor.ps1`;
- how to build/run the Android debug app;
- why AI/voice remain unavailable during LoRA training;
- how to distinguish a newly installed artifact by build ID;
- release HTTPS requirement.

- [ ] **Step 4: Run complete CPU-safe verification**

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify.ps1
```

Expected: all mandatory CPU-safe checks pass; doctor reports the training guard accurately; no GPU service starts.

- [ ] **Step 5: Inspect the diff and secrets boundary**

Run:

```powershell
git diff --check
git status --short
rg -n "(api[_-]?key|secret|token|Bearer )" lib tool docs android -g "*.dart" -g "*.ps1" -g "*.md" -g "*.xml"
```

Review every match. Public client configuration already tracked in the historical app is not expanded in this phase; no new server credential may be present.

- [ ] **Step 6: Commit**

```powershell
git add tool/cli/verify.ps1 docs/runbooks/android-lan-development.md README.md
git commit -m "docs: add production foundation runbook"
```

---

## Completion Gate for This Plan

- [ ] `doctor.ps1` detects active LoRA training and reports that GPU inference may not start.
- [ ] Debug AppConfig accepts RFC 1918 HTTP origins; release rejects all HTTP origins.
- [ ] Android cleartext is enabled only through the debug source set.
- [ ] Guest mode creates a Firebase anonymous session before entering `/home`.
- [ ] App bootstrap exposes degraded/unavailable runtime states without crashing.
- [ ] `/home` opens the five-destination learning shell.
- [ ] Legacy categories, shop, and settings remain reachable from the drawer.
- [ ] The installed app exposes an unambiguous build identity.
- [ ] Full CPU-safe verification passes.
- [ ] No active GPU training process was stopped, suspended, reprioritized, or competed with.

## Deferred to the Next Vertical-Slice Plans

- Learning event schema, Firestore/local repositories, mastery/weakness real data.
- Real speech-to-text input, camera/OCR pipeline, shadowing signal analysis.
- AI provider provenance and authenticated local-model proxy at `127.0.0.1:8002`.
- OmniVoice lazy loading, real telemetry, cache controls, and GPU acceptance after training.
- Real PDF/CSV/JSON export with research metadata and provenance.
- Release signing, HTTPS reverse proxy, CI/CD, and production deployment.
