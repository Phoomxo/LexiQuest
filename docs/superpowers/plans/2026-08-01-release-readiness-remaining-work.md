# LexiQuest Release Readiness Remaining Work Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ปิดงานที่เหลือจาก development build ปัจจุบันให้เป็น immutable signed release candidate ที่ผ่าน P8-E, P8-F และ P8-G ด้วยหลักฐานจาก APK hash เดียวกัน

**Architecture:** ปิด source และ provider behavior ก่อนเพียงครั้งเดียว จากนั้นสร้าง signed RC ที่แก้ไขไม่ได้ แล้วใช้ RC เดิมกับ provider smoke, 14 journeys, device matrix, cloud controls และ rollout ทุกขั้น ระบบใช้ client-side BYOK เฉพาะ controlled/closed rollout; public production แยกเป็นโครงการ backend proxy หลัง P8-G

**Tech Stack:** Flutter/Dart, Drift, Flutter Secure Storage, SharedPreferences, Firebase Auth/App Check, provider REST APIs, PowerShell release tooling, Android Debug Bridge, Gitleaks

## Global Constraints

- ใช้ branch `feature/p8a-voice-architecture` เป็น canonical branch เดียว
- รักษา P8-A–D เป็น frozen baseline; regression fix ต้องเริ่มจาก failing test
- ห้าม automatic provider fallback, automatic retry และ silent model substitution
- ห้ามอ่าน แสดง log ส่งออก หรือเก็บ API key, prompt, response, transcript, email, account ID หรือ device identifier ลง evidence
- เก็บ raw API usage event ในเครื่อง 90 วันและไม่ sync ขึ้น cloud
- Provider configuration เดิมต้องคงอยู่จนกว่า key, model list, model selection และ bounded generation probe ของ configuration ใหม่ผ่านทั้งหมด
- การใช้ key ที่อยู่ใน secure storage ซ้ำต้องทำภายใน controller เท่านั้น ห้ามส่ง key กลับไปยัง UI
- ห้ามรวม evidence จากคนละ commit SHA, dependency-lock SHA-256, APK SHA-256 หรือ signing certificate
- หาก source, generated source, dependency หรือ APK เปลี่ยนหลังสร้าง RC ให้ยกเลิก RC เดิมและออก hash ใหม่
- เมื่อ gate ล้มเหลวให้หยุดที่ failure แรก จัดประเภทเป็น code, test, environment, credential, provider, signing, cloud หรือ device แล้ว rerun เฉพาะ focused gate
- ถ้า failure เดิมเกิดสามรอบให้หยุดแก้เฉพาะหน้าและทบทวน architecture
- ห้าม rotate signing certificate โดยอัตโนมัติ
- APK debug ปัจจุบัน SHA-256 `30DEEF3CACDBF436148AC7BE7F4C4BF053551EFBA8A735D99CC12E4903C3837F` เป็น nonrelease evidence เท่านั้น

---

## Current verified baseline

- `flutter analyze`: 0 issues
- Flutter tests: 1,013 passed
- Backend tests: 255 passed
- Field evidence contract tests: 60 passed
- Gate-ledger tests: 6 passed
- vivo V2041 Guest persistence: 3/3 process restarts passed
- vivo V2041 BYOK layout: no overflow observed
- Gemini request: correctly classified as `requestRejected`; legacy model `antigravity-preview-05-2026` remains unusable
- Changed-file secret scan: no leaks after replacing realistic test credentials

## File ownership map

| Work package | Exclusive files |
|---|---|
| A — secure stored-key model repair | `lib/features/ai_tutor/domain/ai_tutor_contracts.dart`, `lib/features/ai_tutor/application/ai_tutor_use_cases.dart`, `lib/screens/ai_tutor_settings_screen.dart` and their focused tests |
| B — source consolidation | current P8-H provider, usage, database, runtime and documentation files; no behavior change |
| C — integration and release tooling | `tool/cli/**`, `docs/field/**`, `docs/runbooks/**`, gate ledger |
| D — immutable RC and device evidence | `build/field-release/**`, `field/evidence/**`; no source edits |
| E — rollout | private rollout records and store-console configuration; no source edits |

Packages execute serially A → B → C → D → E. A file may not be edited by two active packages.

---

### Task 1: Revalidate the stored provider key without exposing it to UI

**Files:**

- Modify: `lib/features/ai_tutor/domain/ai_tutor_contracts.dart`
- Modify: `lib/features/ai_tutor/application/ai_tutor_use_cases.dart`
- Modify: `lib/screens/ai_tutor_settings_screen.dart`
- Modify test: `test/features/ai_tutor/ai_tutor_use_cases_test.dart`
- Modify test: `test/screens/gemini_settings_screen_test.dart`

**Interfaces:**

- Produces `AiTutorController.listModelsForActiveCredential()`.
- Produces `AiTutorController.configureActiveModel()`.
- Neither method returns an API key.
- Both methods operate only on the currently active provider and its stored endpoint.

- [ ] **Step 1: Add failing controller tests for stored-key model discovery**

Add the following interface expectations to the fake controller and use-case tests:

```dart
final models = await controller.listModelsForActiveCredential();
expect(models.map((model) => model.id), contains('gemini-2.5-flash'));
expect(gateway.lastKey, 'stored-key-test-key-0000');
expect(store.readCredentialCalls, 1);
```

Cover missing credential → `missingKey`, revoked consent → `consentRequired`, cancellation → `cancelled`, and gateway failure preserving the stored credential byte-for-byte.

Run:

```powershell
flutter test test/features/ai_tutor/ai_tutor_use_cases_test.dart --reporter compact
```

Expected: FAIL because the two controller methods do not exist.

- [ ] **Step 2: Extend the provider-neutral controller**

Add these exact contracts:

```dart
Future<List<AiModel>> listModelsForActiveCredential({
  AiCancellation? cancellation,
});

Future<void> configureActiveModel({
  required String model,
  required bool shareLearningSummary,
  AiCancellation? cancellation,
});
```

`listModelsForActiveCredential()` reads `AiTutorCredential` inside the serialized transition gate, rejects a missing key or revoked provider consent, resolves the stored provider/endpoint and calls `gateway.listModels(credential.key)` without returning the key.

- [ ] **Step 3: Implement atomic model replacement using the stored key**

`configureActiveModel()` must:

```dart
final previous = await store.readCredential();
if (previous == null || previous.key.trim().isEmpty) {
  throw const AiTutorException(AiFailureCode.missingKey);
}
if (!previous.providerConsent) {
  throw const AiTutorException(AiFailureCode.consentRequired);
}
```

Then validate the selected model against the authenticated list, run exactly one `_runConfigurationProbe`, and write `previous.copyWith(model: normalizedModel, shareLearningSummary: shareLearningSummary)` only after the probe succeeds. Failure or cancellation writes nothing and performs no retry.

- [ ] **Step 4: Add failing widget tests for the active-key path**

Cover these behaviors:

```dart
expect(find.text('Status: active key'), findsOneWidget);
await tester.tap(find.byKey(const ValueKey('ai-load-models')));
await tester.pumpAndSettle();
expect(fake.listActiveModelsCalls, 1);
expect(fake.lastPlaintextKey, isNull);
expect(selectedModelValue(), isNull);
```

After selecting `gemini-2.5-flash`, Save must call `configureActiveModel()` when the key field is empty. Entering a new key must continue to call `configure()` and atomically replace the complete provider configuration.

Run:

```powershell
flutter test test/screens/gemini_settings_screen_test.dart --reporter compact
```

Expected: FAIL because the screen currently requires key re-entry.

- [ ] **Step 5: Wire the settings screen without exposing the stored key**

Use `_hasKey`, the active provider loaded from `AiTutorSettingsStatus`, and whether `_keyController.text.trim().isEmpty` to choose the controller method. Never populate `_keyController` from secure storage. After discovery always set `_model = null` and require explicit selection.

- [ ] **Step 6: Run Package A gate and commit**

```powershell
dart format lib/features/ai_tutor/domain/ai_tutor_contracts.dart lib/features/ai_tutor/application/ai_tutor_use_cases.dart lib/screens/ai_tutor_settings_screen.dart test/features/ai_tutor/ai_tutor_use_cases_test.dart test/screens/gemini_settings_screen_test.dart
flutter test test/features/ai_tutor/ai_tutor_use_cases_test.dart test/screens/gemini_settings_screen_test.dart --reporter compact
flutter analyze lib/features/ai_tutor lib/screens/ai_tutor_settings_screen.dart
git add lib/features/ai_tutor/domain/ai_tutor_contracts.dart lib/features/ai_tutor/application/ai_tutor_use_cases.dart lib/screens/ai_tutor_settings_screen.dart test/features/ai_tutor/ai_tutor_use_cases_test.dart test/screens/gemini_settings_screen_test.dart
git commit -m "fix(ai): reuse stored credential for model repair"
```

Expected: focused tests pass and analyzer reports 0 issues.

---

### Task 2: Consolidate the current P8-H source into reviewable commits

**Files:**

- Provider and usage package: `lib/data/local/**`, `lib/features/ai_tutor/**`, `lib/features/gemini/**` and matching tests
- Session package: `lib/features/session/**`, `lib/features/account/application/account_use_cases.dart`, `lib/runtime/app_bootstrap.dart`, `lib/runtime/app_start_route_resolver.dart`, `lib/services/guest_session_service.dart` and matching tests
- Integration package: `lib/screens/**`, `lib/screens/main_navigation_screen.dart`, generated plugin registrants and dependency manifests
- Evidence package: `docs/field/**`, `docs/runbooks/**`, `tool/cli/**`

**Interfaces:**

- Produces one clean feature branch with no untracked production file.
- Produces reviewable commits before the immutable RC commit.

- [ ] **Step 1: Inventory every changed file without staging**

```powershell
git status --short
git diff --check
git diff --name-status
git ls-files --others --exclude-standard
```

Classify each file into provider/usage, session, integration, generated, evidence or unrelated owner change. An unrelated owner change remains unstaged.

- [ ] **Step 2: Verify generated source matches declared dependencies and schema**

```powershell
dart run build_runner build --delete-conflicting-outputs
git diff --check
```

Expected: generated Drift/plugin output is deterministic. Any unexpected unrelated rewrite stops this task for diff review.

- [ ] **Step 3: Run package gates before each scoped commit**

```powershell
flutter test test/data/local test/features/ai_tutor test/features/gemini --reporter compact
flutter test test/features/session test/features/account test/runtime test/services/guest_session_service_test.dart --reporter compact
flutter test test/screens/ai_tutor_screen_test.dart test/screens/gemini_settings_screen_test.dart --reporter compact
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/verify-field-release.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/gate-ledger.tests.ps1
```

Expected: every command passes before its owned files are staged.

- [ ] **Step 4: Commit by ownership without mixing packages**

Create these commit subjects in this order:

```text
feat(ai): add provider-neutral byok and local usage ledger
fix(session): make guest entry persistence fail closed
fix(ai-ui): require explicit provider model selection
docs(release): add immutable evidence and rollout gates
```

Use explicit scoped staging commands. Provider/usage stages `lib/data/local`, `lib/features/ai_tutor`, `lib/features/gemini` and matching tests; session stages `lib/features/session`, `lib/features/account/application/account_use_cases.dart`, `lib/runtime`, `lib/services/guest_session_service.dart` and matching tests; UI stages only the two AI screens and their tests; release documentation stages only `docs/field`, `docs/runbooks` and `tool/cli`. Do not use `git add .`.

- [ ] **Step 5: Confirm the branch is clean enough to freeze**

```powershell
git status --short
git log --oneline -8
```

Expected: no untracked production source and no unstaged feature file. Only identified unrelated owner files may remain, and they must not enter the RC build worktree.

---

### Task 3: Run one final integration gate and create the RC source commit

**Files:**

- Record: `field/evidence/gate-ledger.json`
- Build output: `build/app/outputs/flutter-apk/app-debug.apk`

**Interfaces:**

- Consumes the clean source from Task 2.
- Produces one source commit SHA and one dependency-lock SHA-256 for release packaging.

- [ ] **Step 1: Run the full software gate once**

```powershell
flutter analyze
flutter test --reporter compact
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify.ps1
flutter build apk --debug
```

Expected: analyzer 0 issues, every required Flutter/backend/policy test passes, and debug APK builds successfully.

- [ ] **Step 2: Scan the current changed-file contents for secrets**

```powershell
$files = @(@(git diff --name-only --diff-filter=ACMR), @(git ls-files --others --exclude-standard)) |
    Sort-Object -Unique |
    Where-Object { $_ -ne 'lib/firebase_options.dart' -and (Test-Path -LiteralPath $_ -PathType Leaf) }
$files | ForEach-Object { Get-Content -Raw -LiteralPath $_ } |
    gitleaks stdin --redact --no-banner --exit-code 1
```

Expected: `no leaks found`. Firebase client configuration remains excluded because its API identifier is not a server secret and is protected by Firebase policy/App Check.

- [ ] **Step 3: Record the integration tuple**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/record-gate-result.ps1 -Gate integration -Command "flutter analyze; flutter test; tool/cli/verify.ps1; flutter build apk --debug" -Result pass
```

- [ ] **Step 4: Create the immutable RC source commit**

```powershell
git status --short
git commit --allow-empty -m "chore(release): freeze p8 release candidate source"
git rev-parse HEAD
Get-FileHash -Algorithm SHA256 pubspec.lock
```

Expected: source commit and dependency-lock hash are recorded. No source edit is allowed after this point.

---

### Task 4: Preflight every first-class provider with real credentials

**Files:**

- Create: `field/evidence/nonrelease/providers/gemini.json`
- Create: `field/evidence/nonrelease/providers/openai.json`
- Create: `field/evidence/nonrelease/providers/openrouter.json`
- Create: `field/evidence/nonrelease/providers/claude.json`
- Create: `field/evidence/nonrelease/providers/maxPlus.json`

**Interfaces:**

- Produces one debug-only metadata smoke record per first-class provider before signing.
- A provider without a passing record remains labelled `experimental` and cannot be claimed fully supported.

- [ ] **Step 1: Test Gemini stored-key model repair on vivo**

From BYOK settings, load models using the stored credential, explicitly choose a listed stable model, save, and send one bounded tutor request. Require one success event with provider/model/latency/token metadata and no key, prompt or response in evidence.

- [ ] **Step 2: Run one request for each remaining provider**

Execute OpenAI Responses, OpenRouter Chat Completions, Claude Messages and MaxPlus OpenAI-compatible one time each. Require configuration probe success followed by one tutor reply, no retry and correct provider/model usage metadata.

- [ ] **Step 3: Record provider results without sensitive payloads**

Each JSON file contains only:

```json
{
  "providerId": "openai",
  "status": "pass",
  "apkSha256": "30DEEF3CACDBF436148AC7BE7F4C4BF053551EFBA8A735D99CC12E4903C3837F",
  "recordedAtUtc": "2026-08-01T07:40:55Z",
  "evidenceRef": "private:provider-smoke/openai"
}
```

Use the actual APK SHA-256 and UTC of the executed build; the example above is valid only for the current nonrelease debug smoke. These files cannot satisfy the release gate.

- [ ] **Step 4: Gate provider claims**

This preflight proves only that the implementation can reach each provider. Keep Gemini, OpenAI, OpenRouter, Claude and MaxPlus labelled `experimental` until Task 6 recreates their records with the signed RC and every result is `pass`. Cointh remains Custom OpenAI-compatible/experimental until official protocol documentation and a real smoke exist.

---

### Task 5: Recover signing and build one immutable release candidate

**Files:**

- Read without printing secrets: owner keystore and signing properties
- Create: `build/field-release/lexiquest-1.0.1+2.apk`
- Create: `build/field-release/release-manifest.json`

**Interfaces:**

- Produces version `1.0.1+2`, subject to versionCode 2 being unused in the closed-testing track.
- Produces APK SHA-256 and signing-certificate SHA-256 used by every later gate.

- [ ] **Step 1: Verify owner-controlled signing inputs**

Confirm the legacy keystore path, alias, certificate and passwords without echoing their values. Compare its certificate SHA-256 with the previously distributed signed artifact. If any input is missing, record `signing/owner` and stop; do not generate a replacement certificate.

- [ ] **Step 2: Verify release version availability**

Check the closed-testing track. Use `versionName 1.0.1` and `versionCode 2` only if code 2 is unused. A used versionCode is classified `release-version/owner` and packaging stops before modifying version files.

- [ ] **Step 3: Package and verify the signed RC**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/package-field-release.ps1 -Version 1.0.1+2
Get-FileHash -Algorithm SHA256 build/field-release/lexiquest-1.0.1+2.apk
```

Verify certificate, package name, version, model hash and commit SHA against `build/field-release/release-manifest.json`.

- [ ] **Step 4: Lock the artifact**

Copy the signed artifact to read-only owner release storage. All later evidence must reference this exact SHA-256. Rebuilding, resigning or modifying one byte creates a new RC and invalidates downstream evidence.

---

### Task 6: Re-run provider smokes and close P8-E 14/14 on vivo V2041

**Files:**

- Create: timestamped JSON under `field/evidence/devices/` using `mid-$([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')).json`
- Create: `field/evidence/providers/gemini.json`
- Create: `field/evidence/providers/openai.json`
- Create: `field/evidence/providers/openrouter.json`
- Create: `field/evidence/providers/claude.json`
- Create: `field/evidence/providers/maxPlus.json`
- Create: private evidence references for each journey

**Interfaces:**

- Produces 14 passing journey records and 30-minute endurance for the signed RC hash.

- [ ] **Step 1: Re-run all five provider smokes on the signed RC**

Repeat Gemini, OpenAI, OpenRouter, Claude and MaxPlus using the signed RC. Replace the debug-only records with metadata-only records in `field/evidence/providers/`; each record must contain the signed RC SHA-256. Any provider without a passing signed-RC record remains experimental and blocks a claim of complete first-class support.

- [ ] **Step 2: Run upgrade install first**

Install the prior signed release, create known Guest vocabulary/progress, then install `1.0.1+2` without uninstalling. Require preserved data, successful Drift migration, restored Guest route, same certificate and no authentication reset.

- [ ] **Step 3: Run clean install on a dedicated profile/device**

Do not clear owner data on the current phone. Use a dedicated Android user or test device to prove consent → Guest startup, default database creation and first-launch Login behavior.

- [ ] **Step 4: Execute all 14 journeys**

Require pass for `consentGuestStartup`, `offlineVocabulary`, `learningCore`, `offlineRestartSync`, `accountLifecycle`, `modelLifecycle`, `cameraScanner`, `speechTtsPronunciation`, `geminiByok`, `cleanInstall`, `upgradeInstall`, `rebootForegroundBackground`, `cloudKillSwitch` and `dataExport`.

`accountLifecycle` includes Guest→Authenticated with a real test account. `geminiByok` includes one real successful response using an explicitly selected model.

- [ ] **Step 5: Run 30-minute endurance**

Exercise learning, speech, AI request/cancellation, background/resume and offline transitions. Require crashCount 0, anrCount 0, no data loss and no unbounded memory growth. Record RSS, battery and temperature without recording content.

- [ ] **Step 6: Validate mid-tier evidence**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/collect-android-field-evidence.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-field-release.ps1 -EvidencePath field/evidence/release-evidence.json
```

Expected: the mid device has 14/14 pass and every artifact field matches the RC manifest. P8-F fields may remain incomplete until Task 7.

---

### Task 7: Close P8-F device matrix and cloud readiness

**Files:**

- Create: timestamped low-tier JSON under `field/evidence/devices/`
- Reuse: the signed-RC mid-tier JSON created by Task 6
- Create: timestamped high-tier JSON under `field/evidence/devices/`
- Create/update: `field/evidence/release-evidence.json`

**Interfaces:**

- Produces 14/14 on low, mid and high physical devices using the same RC hash.
- Produces valid App Check, cloud kill switch, budget mode and private-reference evidence.

- [ ] **Step 1: Run the same 14 journeys on low and high devices**

Each device must cover cold start, background/resume, process recreation, microphone, TTS, cancellation, offline/slow network/provider errors, Guest persistence, account conversion, migration, upgrade install and key lifecycle. Require crash/ANR/data-loss count 0.

- [ ] **Step 2: Verify App Check before enforcement**

Observe valid RC traffic while enforcement is disabled. Record the private console reference and confirm debug tokens are not accepted as production evidence.

- [ ] **Step 3: Enable and verify App Check enforcement**

```powershell
node tool/cli/configure-firebase-app-check.cjs
node tool/cli/set-firebase-app-check-enforcement.cjs enable
```

Require valid signed-RC traffic to pass and invalid traffic to be rejected. Roll back enforcement if valid traffic fails.

- [ ] **Step 4: Verify cloud kill switch and budget controls**

```powershell
node tool/cli/set-firebase-cloud-policy.cjs disable
node tool/cli/set-firebase-cloud-policy.cjs enable
node tool/cli/configure-firebase-budget.cjs
```

When the cloud path is disabled, offline learning must continue. Record either configured budget alerts or explicit no-billing-account mode.

- [ ] **Step 5: Assemble private references**

Set non-empty owner environment variables:

```powershell
$env:LEXIQUEST_FEEDBACK_REF
$env:LEXIQUEST_SUPPORT_REF
$env:LEXIQUEST_RESEARCH_REF
```

They must point to the actual private feedback channel, support channel and approved research protocol. They must not contain credentials.

- [ ] **Step 6: Assemble and verify P8-F evidence**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/new-field-release-evidence.ps1 -FeedbackChannelRef $env:LEXIQUEST_FEEDBACK_REF -SupportChannelRef $env:LEXIQUEST_SUPPORT_REF -ResearchProtocolRef $env:LEXIQUEST_RESEARCH_REF -AppCheckConfigured -AppCheckValidTrafficObserved -AppCheckEnforced -BudgetAlertsConfigured -CloudKillSwitchVerified
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-field-release.ps1 -EvidencePath field/evidence/release-evidence.json
```

Expected: all three physical-device records, five provider smokes, cloud controls and private references pass on the same RC hash.

---

### Task 8: Close P8-G owner smoke and controlled rollout

**Files:**

- Update: `field/evidence/release-evidence.json`
- Create: private rollout record per stage

**Interfaces:**

- Produces owner approval and controlled rollout stages 3% → 10% → 30% → 100%.

- [ ] **Step 1: Run owner smoke on clean and upgraded installs**

Verify consent/Guest, learning core, account conversion, TTS/STT/cancellation, every first-class provider, export, migration, background/resume and cloud kill switch. Owner records approval against the exact RC SHA-256.

- [ ] **Step 2: Validate final evidence before upload**

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-field-release.ps1 -EvidencePath field/evidence/release-evidence.json
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/record-gate-result.ps1 -Gate release -Command "verify-field-release.ps1" -Result pass -ApkSha256 ((Get-FileHash -Algorithm SHA256 build/field-release/lexiquest-1.0.1+2.apk).Hash)
```

Expected: release gate passes with owner approval and no partial evidence.

- [ ] **Step 3: Roll out 3%, 10%, 30% and 100%**

At each stage record version, commit SHA, dependency-lock SHA-256, APK/AAB SHA-256, start/end UTC, participant count, crash/ANR, authentication failures, migration failures, provider error rate, data-loss signals and approver.

- [ ] **Step 4: Apply stop and rollback rules**

Stop immediately when crash/ANR increases abnormally, authentication or migration fails, provider errors spike, a secret leaks or any data loss occurs. Rollback uses an artifact signed by the same certificate and compatible with the current database; never destructively downgrade schema.

---

### Task 9: Separate public-production backend proxy project

**Files:**

- New project scope; no P8 source edit during closed rollout

**Interfaces:**

- Consumes the stable provider-neutral app contracts.
- Produces server-side provider credential isolation, authenticated request mediation, quotas, abuse controls and audit-safe metadata.

- [ ] **Step 1: Keep the current release controlled/closed**

Do not expose direct client-side BYOK as unrestricted public production. P8-G completion authorizes only the controlled rollout defined above.

- [ ] **Step 2: Start a separate architecture/design cycle after P8-G**

The new design must cover server-held provider credentials, per-user authorization, App Check verification, rate/cost quotas, cancellation, provider routing consent, redacted telemetry and incident rollback. It receives its own specification, implementation plan and release gate so P8 source certification is not invalidated.

---

## Completion criteria

- Branch contains no untracked production source and the RC source commit is immutable.
- Stored active key can load models and replace only the model without exposing the key to UI.
- Gemini, OpenAI, OpenRouter, Claude and MaxPlus have signed-RC real-key smoke evidence.
- Analyzer, Flutter tests, backend/policy tests, evidence contract tests and changed-file secret scan pass.
- Signed RC uses the legacy certificate and passes prior-release → RC upgrade without data loss.
- P8-E passes 14/14 and 30-minute endurance on vivo V2041.
- P8-F passes 14/14 on low, mid and high physical devices with one RC hash.
- App Check, cloud kill switch, budget mode and private support/research references pass.
- P8-G owner smoke and 3% → 10% → 30% → 100% controlled rollout pass.
- No release blocker, secret leak, crash/ANR regression, consent bypass or data loss remains.

## Plan self-review

- Coverage: source hygiene, stored-key repair, all providers, signing, upgrade, account conversion, clean install, endurance, device matrix, App Check, private references and rollout each have an owned task.
- Collision control: source-editing packages finish before immutable RC/device work begins; evidence packages never edit source.
- Test-loop control: focused test → one integration gate → one signed RC → device/cloud/rollout gates.
- Type consistency: controller method names and signatures are identical in contract, use-case and widget-test steps.
- Scope: broad UI redesign remains deferred; public backend proxy is explicitly separated from the controlled P8 release.
