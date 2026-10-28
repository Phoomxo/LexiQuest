# P8-E Device Findings Remediation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove the four defects found on vivo V2041, prove the fixes on a bounded debug build, then create one immutable signed release candidate for P8-E/P8-F/P8-G certification.

**Architecture:** Persist only the user's app-entry choice separately from the local owner record, because bootstrap intentionally creates a local owner before the user chooses Guest. Make provider configuration perform an explicit, bounded generation probe before atomic credential replacement, classify Gemini HTTP failures without reading or retaining provider messages, and require explicit model selection. Treat the dropdown overflow as a functional settings defect; broader UI balancing remains out of scope.

**Tech Stack:** Flutter/Dart, SharedPreferences, Drift, Firebase Auth, provider REST APIs, PowerShell release/evidence tooling, Android Debug Bridge.

## Global Constraints

- Work only on `feature/p8a-voice-architecture`; preserve all existing uncommitted user changes.
- P8-A–D stay frozen except for a regression fix backed by a failing test.
- No automatic provider fallback, automatic retry, or silent model substitution.
- Never read, print, export, screenshot, or store an API key, prompt, response, transcript, email, account ID, or device identifier in evidence.
- The existing provider configuration remains active until the replacement key, selected model, and bounded generation probe all pass.
- A configuration probe is one disclosed API request; record metadata only with request type `configurationValidation`.
- Stop at the first failed gate, classify it as code, test, environment, credential, provider, signing, or device, and rerun only the failed focused gate after correction.
- Do not combine evidence from different source commits, dependency-lock hashes, APK hashes, or signing certificates.
- The 15-pixel Provider dropdown overflow is in scope because it blocks a critical system settings screen. General UI/layout redesign remains deferred.
- Do not create or rotate a release certificate automatically. Missing legacy signing material is an owner blocker.

---

## Verified root causes and chosen corrections

| Finding | Root cause | Correction |
|---|---|---|
| Guest returns to Login after force-stop | `lib/main.dart` maps `/` to Login unconditionally; an active local owner cannot distinguish first launch from a user who selected Guest | Add a separate persisted app-entry state and resolve the initial route during bootstrap |
| Gemini validation passes but generation fails | Configuration validates model discovery only; it never proves the selected model can execute the real generation path | Run one bounded generation probe before atomic credential replacement |
| App reports `invalid key` for multiple causes | Gemini maps HTTP 400, 401, and 403 to `invalidKey` | Map 400 to `requestRejected`, retain 401/403 as `invalidKey`, and classify safe provider status codes without retaining response text |
| Antigravity preview selected without an explicit decision | `_loadModels()` assigns `models.first.id` | Set no model after discovery and require a user selection |
| Provider dropdown overflows by 15 pixels | Dropdown content is not expanded or constrained | Use expanded dropdowns and one-line ellipsized labels, verified at vivo-width constraints |

Rejected shortcuts:

- Do not route every active local owner to Home; bootstrap creates one before first login and would bypass the entry screen.
- Do not hardcode or silently switch to a known Gemini model; the selected model must come from the authenticated model list.
- Do not retry the failed Gemini request automatically; it could duplicate cost and hide the real failure.

## File ownership map

| Work package | Exclusive production files |
|---|---|
| A — app-entry persistence | `lib/features/session/**`, `lib/services/guest_session_service.dart`, `lib/features/account/application/account_use_cases.dart`, `lib/runtime/app_bootstrap.dart`, `lib/runtime/app_dependencies.dart`, `lib/main.dart` |
| B — provider validation and errors | `lib/features/ai_tutor/domain/ai_tutor_contracts.dart`, `lib/features/ai_tutor/application/ai_tutor_use_cases.dart`, `lib/features/gemini/data/gemini_rest_gateway.dart` |
| C — settings behavior/layout | `lib/screens/ai_tutor_settings_screen.dart`, `lib/screens/ai_tutor_screen.dart` |
| D — evidence and release | `field/evidence/**`, `docs/development/**`, gate ledger entries; no source edits |

Packages execute serially A → B → C → D. If a package must touch a file owned by another package, stop and merge that change into the owning package rather than editing concurrently.

---

### Task 1: Persist and restore the user's app-entry state

**Files:**

- Create: `lib/features/session/domain/app_entry_state.dart`
- Create: `lib/features/session/data/shared_preferences_app_entry_state_store.dart`
- Create: `lib/runtime/app_start_route_resolver.dart`
- Modify: `lib/services/guest_session_service.dart:94-178`
- Modify: `lib/features/account/application/account_use_cases.dart:6-114`
- Modify: `lib/runtime/app_bootstrap.dart:221-253,291-303,398-415`
- Modify: `lib/runtime/app_dependencies.dart:24-78`
- Modify: `lib/main.dart:10-102`
- Create test: `test/features/session/shared_preferences_app_entry_state_store_test.dart`
- Create test: `test/runtime/app_start_route_resolver_test.dart`
- Modify test: `test/services/guest_session_service_test.dart`
- Modify test: `test/features/account/account_use_cases_test.dart`
- Modify test: `test/runtime/app_bootstrap_test.dart`

**Interfaces:**

- Produces `AppEntryMode { signedOut, guest }`.
- Produces `AppEntryStateStore.read()`, `markGuest()`, and `clear()`.
- Produces `AppEntryStateStoreFactory = Future<AppEntryStateStore> Function()` so bootstrap tests never depend on process-global preferences.
- Produces `AppStartRouteResolver.resolve(accountSession:, entryState:) -> Future<AppRoute>`.
- `AppDependencies.initialRoute` becomes the only `/` startup route source used by `MyApp`.

- [ ] **Step 1: Write persistence and route-resolution tests that fail**

Cover these exact cases:

```dart
expect(await store.read(), AppEntryMode.signedOut);
await store.markGuest();
final reopened = SharedPreferencesAppEntryStateStore(await SharedPreferences.getInstance());
expect(await reopened.read(), AppEntryMode.guest);
await reopened.clear();
expect(await reopened.read(), AppEntryMode.signedOut);
```

In the resolver test harness, use one fake store per enum value and a throwing fake store. Assert signed-out → Login, Guest → Home, authenticated session → Home, and store read failure → Login.

Run:

```powershell
flutter test test/features/session/shared_preferences_app_entry_state_store_test.dart test/runtime/app_start_route_resolver_test.dart --reporter compact
```

Expected: FAIL because the session contracts and resolver do not exist.

- [ ] **Step 2: Implement the minimal app-entry contract and fail-closed store**

Use this public surface:

```dart
enum AppEntryMode { signedOut, guest }

abstract interface class AppEntryStateStore {
  Future<AppEntryMode> read();
  Future<void> markGuest();
  Future<void> clear();
}
```

Store only `guest` under the versioned SharedPreferences key `lexiquest.app_entry_mode.v1`. Missing, malformed, or unreadable values resolve to `signedOut`. Reject a failed preference write instead of claiming persistence.

- [ ] **Step 3: Write lifecycle wiring tests that fail**

Add assertions that:

- successful `OwnerBindingGuestSessionService.start()` marks Guest before returning `GuestSessionStarted`;
- a failed Guest start does not mark Guest;
- successful register/sign-in clears stale Guest entry state only after account binding succeeds;
- logout clears Guest entry state and startup resolves to Login;
- bootstrap with a persisted Guest state exposes `AppRoute.home`;
- bootstrap on first launch exposes `AppRoute.login`;
- an authenticated Firebase session exposes `AppRoute.home`.

Run:

```powershell
flutter test test/services/guest_session_service_test.dart test/features/account/account_use_cases_test.dart test/runtime/app_bootstrap_test.dart --reporter compact
```

Expected: FAIL on missing entry-state injection and initial-route assertions.

- [ ] **Step 4: Wire state changes and startup routing**

Inject `AppEntryStateStore` into the Guest decorator and `AccountUseCases`. Resolve the launch route after account reconciliation in `AppBootstrap.initialize()`, store it in `AppDependencies.initialRoute`, and change `MyApp._initialRoute()` to:

```dart
String _initialRoute() {
  final platformRoute =
      WidgetsBinding.instance.platformDispatcher.defaultRouteName;
  return platformRoute == '/'
      ? widget.dependencies.initialRoute.path
      : platformRoute;
}
```

Do not infer Guest from `LocalOwner.isActive`; that row exists on first launch by design.

- [ ] **Step 5: Run the focused package gate**

```powershell
flutter test test/features/session/shared_preferences_app_entry_state_store_test.dart test/runtime/app_start_route_resolver_test.dart test/services/guest_session_service_test.dart test/features/account/account_use_cases_test.dart test/runtime/app_bootstrap_test.dart --reporter compact
flutter analyze lib/features/session lib/services/guest_session_service.dart lib/features/account/application/account_use_cases.dart lib/runtime lib/main.dart
```

Expected: all tests PASS and analyzer reports no issues.

- [ ] **Step 6: Commit Package A only**

```powershell
git add lib/features/session lib/services/guest_session_service.dart lib/features/account/application/account_use_cases.dart lib/runtime/app_bootstrap.dart lib/runtime/app_dependencies.dart lib/main.dart test/features/session test/runtime/app_start_route_resolver_test.dart test/services/guest_session_service_test.dart test/features/account/account_use_cases_test.dart test/runtime/app_bootstrap_test.dart
git commit -m "fix(session): restore explicit guest entry after restart"
```

---

### Task 2: Validate provider execution before replacing credentials

**Files:**

- Modify: `lib/features/ai_tutor/domain/ai_tutor_contracts.dart:9-25`
- Modify: `lib/features/ai_tutor/application/ai_tutor_use_cases.dart:119-169,249-323`
- Modify: `lib/features/gemini/data/gemini_rest_gateway.dart:49-79,201-208,285-295`
- Modify test: `test/features/ai_tutor/ai_tutor_use_cases_test.dart`
- Modify test: `test/features/gemini/gemini_rest_gateway_test.dart`
- Modify test: `test/features/ai_tutor/drift_ai_usage_repository_test.dart`

**Interfaces:**

- Adds `AiFailureCode.requestRejected`.
- `AiTutorController.configure()` keeps its existing signature.
- A successful configuration writes one metadata-only usage event with `requestType: configurationValidation` before storing the replacement credential.

- [ ] **Step 1: Write failing error-classification tests**

Add Gemini fixtures containing only safe provider codes and verify the following exact mapping:

```text
400 + INVALID_ARGUMENT     -> requestRejected
401 + UNAUTHENTICATED      -> invalidKey
403 + PERMISSION_DENIED    -> invalidKey
429 + RESOURCE_EXHAUSTED   -> quota
500 + INTERNAL             -> providerUnavailable
```

The test must also assert that exception text contains only the enum name and never the provider response message.

Run:

```powershell
flutter test test/features/gemini/gemini_rest_gateway_test.dart --reporter compact
```

Expected: FAIL because HTTP 400 currently maps to `invalidKey`.

- [ ] **Step 2: Implement bounded safe Gemini classification**

Parse only `error.status` and allowlisted structured reason identifiers from the JSON body. Never retain or surface `error.message`, headers, request bodies, or credentials. Use status-only fallback when the body is missing or malformed:

```dart
400 => AiFailureCode.requestRejected,
401 || 403 => AiFailureCode.invalidKey,
408 => AiFailureCode.timeout,
429 => AiFailureCode.quota,
500 || 502 || 503 || 504 => AiFailureCode.providerUnavailable,
_ => AiFailureCode.providerUnavailable,
```

- [ ] **Step 3: Write failing atomic configuration-probe tests**

Add tests proving:

- discovery alone never writes a credential;
- configure calls model discovery, then exactly one bounded generation probe;
- probe success writes the new credential atomically;
- probe failure preserves the complete previous provider/key/model/consent configuration;
- cancellation before probe completion writes nothing;
- the probe sends no learning summary and uses fixed non-user text;
- success and failure record metadata only with `requestType: configurationValidation`;
- the normal tutor request remains `requestType: tutorReply`;
- no automatic retry occurs.

Use this fixed probe input:

```dart
scenario: 'Configuration validation',
learnerMessage: 'Reply with OK.',
learningSummary: null,
```

Run:

```powershell
flutter test test/features/ai_tutor/ai_tutor_use_cases_test.dart test/features/ai_tutor/drift_ai_usage_repository_test.dart --reporter compact
```

Expected: FAIL because configure currently stops after model discovery.

- [ ] **Step 4: Implement validate-before-write and request-type usage recording**

Refactor `_recordUsage` to require `requestType`. In `configure()`, validate the selected model against the authenticated list, run exactly one generation probe through the resolved gateway, record its metadata, and call `store.writeCredential()` only after probe success. Discard the probe response immediately.

Do not catch-and-retry. Preserve the prior secure-store value on every failure path.

- [ ] **Step 5: Run the focused provider gate**

```powershell
flutter test test/features/gemini/gemini_rest_gateway_test.dart test/features/ai_tutor/ai_tutor_use_cases_test.dart test/features/ai_tutor/drift_ai_usage_repository_test.dart --reporter compact
flutter analyze lib/features/ai_tutor lib/features/gemini
```

Expected: all tests PASS and analyzer reports no issues.

- [ ] **Step 6: Commit Package B only**

```powershell
git add lib/features/ai_tutor/domain/ai_tutor_contracts.dart lib/features/ai_tutor/application/ai_tutor_use_cases.dart lib/features/gemini/data/gemini_rest_gateway.dart test/features/ai_tutor/ai_tutor_use_cases_test.dart test/features/ai_tutor/drift_ai_usage_repository_test.dart test/features/gemini/gemini_rest_gateway_test.dart
git commit -m "fix(ai): validate selected provider model before activation"
```

---

### Task 3: Require explicit model selection and remove settings overflow

**Files:**

- Modify: `lib/screens/ai_tutor_settings_screen.dart:84-179,300-454,510-530`
- Modify: `lib/screens/ai_tutor_screen.dart:430-450`
- Modify test: `test/screens/gemini_settings_screen_test.dart`
- Modify test: `test/screens/ai_tutor_screen_test.dart`

**Interfaces:**

- Consumes `AiFailureCode.requestRejected` from Task 2.
- The model dropdown has no selected value after discovery until the user taps a model.
- The save action remains disabled or returns `missingModel` until selection.

- [ ] **Step 1: Write failing widget tests**

Verify all of the following:

```dart
await tester.tap(find.byKey(const ValueKey('ai-load-models')));
await tester.pumpAndSettle();
expect(controller.configureCalls, 0);
expect(selectedModelValue(), isNull);

await tester.tap(find.byKey(const ValueKey('ai-save-key')));
await tester.pumpAndSettle();
expect(find.text('Select or enter a model.'), findsOneWidget);
```

Add a constrained-device test at 360 logical pixels wide and text scale 1.3. Pump long provider and model labels, open both dropdowns, and assert `tester.takeException()` is null and no `RenderFlex overflowed` message occurs.

Run:

```powershell
flutter test test/screens/gemini_settings_screen_test.dart test/screens/ai_tutor_screen_test.dart --reporter expanded
```

Expected: FAIL because the first model is auto-selected and the Provider dropdown overflows.

- [ ] **Step 2: Implement explicit selection and bounded labels**

After model discovery set `_model = null`. Add a dropdown hint and keep Save guarded by the existing missing-model validation. Configure both provider and model dropdowns as follows:

```dart
isExpanded: true,
child: Text(
  label,
  maxLines: 1,
  overflow: TextOverflow.ellipsis,
),
```

Add user-facing copy that Save performs one small validation request and may consume provider quota. Map `requestRejected` to a message that asks the user to choose another listed model or check provider restrictions; do not call it an invalid key.

On failed replacement display that the previous active provider remains unchanged.

- [ ] **Step 3: Run the focused screen gate**

```powershell
flutter test test/screens/gemini_settings_screen_test.dart test/screens/ai_tutor_screen_test.dart --reporter compact
flutter analyze lib/screens/ai_tutor_settings_screen.dart lib/screens/ai_tutor_screen.dart
```

Expected: all tests PASS, no overflow exception, and analyzer reports no issues.

- [ ] **Step 4: Commit Package C only**

```powershell
git add lib/screens/ai_tutor_settings_screen.dart lib/screens/ai_tutor_screen.dart test/screens/gemini_settings_screen_test.dart test/screens/ai_tutor_screen_test.dart
git commit -m "fix(ai-ui): require model choice and constrain provider labels"
```

---

### Task 4: Run the single software integration gate

**Files:**

- Modify only through generated formatting/build commands: generated Drift files if schema generation proves necessary; no planned schema change.
- Record: gate ledger using `tool/cli/record-gate-result.ps1`.

- [ ] **Step 1: Confirm focused gates and hashes changed before running the full suite**

Record source commit, `pubspec.lock` SHA-256, and the focused test commands. If none changed since a recorded passing integration gate, do not rerun it.

- [ ] **Step 2: Run the full gate once**

```powershell
flutter analyze
flutter test --reporter compact
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify.ps1
flutter build apk --debug
```

Expected:

- Flutter analyzer: 0 issues.
- Flutter tests: all pass.
- Backend and Firestore/policy suites invoked by `verify.ps1`: all required tests pass; optional real-service E2E remains explicitly skipped.
- Debug APK build succeeds.

- [ ] **Step 3: Run bounded secret and dependency checks once**

Run the existing Gitleaks changed-file gate and dependency audits. Do not rerun OSV Scanner on the known Windows path failure unless its invocation/path handling has changed; record that environment failure instead of looping.

- [ ] **Step 4: Record the integration result**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/record-gate-result.ps1 -Gate integration -Command "flutter analyze; flutter test; tool/cli/verify.ps1; flutter build apk --debug" -Result pass
```

Do not create a release-candidate commit until every command above is green.

---

### Task 5: Rerun only the affected vivo V2041 journeys on the new debug hash

**Files:**

- Create: `field/evidence/nonrelease/p8e-remediation-debug-manifest-2026-08-01.json`
- Create: `field/evidence/nonrelease/devices/mid-remediation-vivo-v2041-20260801.json`
- Create: `field/evidence/nonrelease/p8e-remediation-debug-report-2026-08-01.md`

- [ ] **Step 1: Install and identify the exact debug artifact**

Record APK SHA-256, source commit, dependency-lock hash, package/version, certificate SHA-256, device pseudonym, Android version, and test start UTC. Label every file `nonrelease-debug-device-test`.

Do not clear application data on the owner's phone without explicit approval. Use a dedicated test profile/device for the first-launch case; otherwise test only restoration of the existing Guest choice.

- [ ] **Step 2: Verify Guest restart persistence**

Enter Guest, confirm the known `Animals` category, then perform three separate `am force-stop` plus launcher restarts. Require:

- a changed PID after each restart;
- Home opens without tapping Guest again;
- `Animals` remains visible;
- no Login password field appears;
- no crash, ANR, or data loss.

Any single failure stops this device gate and returns work to Task 1.

- [ ] **Step 3: Verify Gemini configuration and generation once**

The owner enters the key on-device. Load the authenticated model list, explicitly select a non-preview model offered by the provider, acknowledge the disclosed validation request, and save.

Require:

- configuration probe succeeds exactly once;
- a separate one-message AI Tutor request succeeds exactly once;
- usage contains `configurationValidation` and `tutorReply` metadata;
- no key, prompt, or response is present in screenshots, XML, logs, database exports, or evidence;
- no fallback or retry occurs.

If the provider rejects the request, record only provider, model, request type, safe error category, latency, token counts, and UTC. Stop without trying a second model in the same gate.

- [ ] **Step 4: Verify the settings layout**

Open both Provider and Model dropdowns with the device font scale used in the failed run. Require no yellow/black overflow indicator, clipped action, or inaccessible selection.

- [ ] **Step 5: Verify background/resume and bounded health**

Background and resume AI settings and AI Tutor. Require route preservation, cancellation of any active request when leaving the screen, and 0 crash/ANR markers. Record RSS, battery, and temperature as a smoke snapshot only; do not label it endurance.

- [ ] **Step 6: Publish a debug-only remediation report**

Mark only the affected checks as pass/fail. Keep clean install, upgrade install, reboot, endurance, account conversion, and the remaining 14-journey certification items pending. Never merge this evidence with release evidence.

---

### Task 6: Create the immutable signed RC and restart P8-E certification

**Files:**

- Create through release tooling: `build/field-release/**`
- Create: `field/evidence/release-evidence.json`
- Update: `docs/development/p8e-mid-tier-completion-evidence-2026-07-31.md` only after verified results exist.

- [ ] **Step 1: Freeze source after the debug remediation gate passes**

Create one release-candidate commit. Record commit SHA and dependency-lock hash. No source, generated source, or dependency changes are allowed after this point without invalidating the RC.

- [ ] **Step 2: Recover existing signing material**

Verify the legacy keystore path, alias, certificate SHA-256, and passwords without printing them. If any item is unavailable, stop with classification `signing/owner` and leave P8-E blocked. Do not rotate the certificate.

- [ ] **Step 3: Build and hash the signed RC**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/package-field-release.ps1 -Version 1.0.1+2
```

The planned upgrade target is `1.0.1+2`, above the installed `1.0.0+1`. Before building, query the closed-testing track; if versionCode 2 is already used, stop with classification `release-version/owner` instead of inventing another value. Record APK/AAB SHA-256 and signing certificate SHA-256.

- [ ] **Step 4: Run upgradeInstall before other destructive journeys**

Install the prior signed release, create known local Guest data, then install the RC without uninstalling. Require successful package upgrade, preserved data, correct database migration, restored Guest entry, and identical signing certificate.

- [ ] **Step 5: Run P8-E 14/14 on vivo using only the RC hash**

Include real Gemini BYOK, Guest→Authenticated conversion, reboot/background, and 30-minute endurance. Any source or APK byte change invalidates all RC device evidence. A crash, ANR, data loss, consent bypass, secret leak, or failed journey blocks release.

- [ ] **Step 6: Continue P8-F and P8-G only after P8-E passes**

Use the same immutable RC on low-, mid-, and high-tier physical devices. Then run the owner smoke and closed rollout gates. Do not claim release readiness until `verify-field-release.ps1` passes with private App Check/support/research references and 14/14 evidence for all required devices.

---

## Completion criteria

- First launch remains Login; an explicitly selected Guest session survives three process restarts; logout returns to Login.
- Provider discovery never auto-selects a model.
- Replacement configuration performs exactly one disclosed generation probe and remains atomic on failure.
- Gemini HTTP 400 is no longer reported as an invalid key; evidence stores only the safe error category.
- Provider and model dropdowns do not overflow at vivo-width and 1.3 text scale.
- Focused tests pass before the single full integration gate.
- Debug remediation evidence passes before signing work starts.
- P8-E reaches 14/14 on one signed APK hash; P8-F/P8-G use that same immutable hash.

## Plan self-review

- Coverage: all four observed device defects, the incomplete endurance/upgrade gates, and evidence separation are assigned to tasks.
- Collision control: no production file is owned by more than one work package.
- Test-loop control: focused gate → one integration gate → one debug device gate → one immutable RC gate.
- Scope: broad UI redesign, backend proxy architecture, new providers, and pricing calculations are excluded.
