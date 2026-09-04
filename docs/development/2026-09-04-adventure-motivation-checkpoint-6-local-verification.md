# Adventure Motivation — Checkpoint 6 Local Verification Evidence

Date: 2026-09-04 (Asia/Bangkok)

Scope: Task 6.3 local engineering verification for the approved Android/shared
Adventure Motivation delivery. This record is **local engineering evidence
only**. It is not formal device accessibility/performance certification, UAT
or rollout approval, research/MDS authorization, or Pair prototype
authorization.

## Reproducible environment

- Branch: `feature/adventure-motivation-plan`
- Evidence source before this document:
  `be2ef6dbb3423e794fbf0921c0c22073614f69ba`
- Worktree:
  `C:\Users\Phet\Documents\LexiQuest\.worktrees\adventure-motivation-plan`
- Flutter: 3.44.7 stable, framework `84fc5cbb22`
- Dart: 3.12.2 stable on `windows_x64`
- Node.js / npm: 24.16.0 / 12.0.1
- Java: Temurin OpenJDK 25.0.3 LTS
- PowerShell: 7.6.5
- Gitleaks: 8.30.1
- OSV-Scanner: 2.4.0

## BG-01–BG-12 ledger

| Gate | Command/scope | Result |
| --- | --- | --- |
| BG-01 | `dart run tool/feature_contract/generate_feature_map.dart --check` | PASS — revision 1.3.0, exact 44-capability map, SHA-256 `41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4`. |
| BG-02 | `flutter analyze --no-pub lib test` | PASS — zero issues. |
| BG-03 | Initial full Flutter inventory, default and serial | Inventory recorded 3,400 pass / 7 fail in each mode. Three failures were stale generated/source-location contracts and were repaired; four were already-known platform/model gates classified below. Zero failure was left unclassified. |
| BG-03 | `flutter test --no-pub --exclude-tags release-excluded --reporter compact` | PASS — 3,403 tests, 3m33s. |
| BG-03 | Same suite with `--concurrency=1` | PASS — 3,403 tests, 11m05s. |
| BG-04 | Adventure/Learning/bootstrap/navigation/scenario/architecture authorities | PASS — 391 tests. |
| BG-04 | Preferences/Sync/Identity/Export authorities | PASS — 387 tests. |
| BG-04 | Fresh schema/migration/cardinality/architecture focus | PASS — 40 tests. |
| BG-04/BG-12 | Fresh Adventure entry/bridge, runtime kill-switch, navigation, quiz, production contract and delivery-cardinality focus | PASS — 91 tests. |
| BG-05 | AI API / Voice API CPU-only / LexiQuest LM | PASS — 76 / 55 / 75 tests. Optional external Voice E2E/GPU execution remains excluded as declared below. |
| BG-06 | Firestore Rules / Firebase Auth emulator suites | PASS — 85 / 3 tests. |
| BG-07 | `gitleaks git . --redact --no-banner` | PASS — 752 commits, approximately 115.36 MB, no leaks. One historical fixed non-secret preference-lease fixture is allowed only by exact path and exact value regex in `.gitleaks.toml`. |
| BG-08 | `tool/cli/verify-osv-locks.ps1` | PASS for all six scanned scopes under the approved Android/shared policy; no unapproved or expired release-scope finding. |
| BG-09 | Android manifest security and smoke-script contract suites | PASS — 15 manifest assertions plus the bounded Android smoke contract. |
| BG-09 | `flutter build apk --debug --no-pub` | PASS — `build/app/outputs/flutter-apk/app-debug.apk`; SHA-256 `5F4C48537C3F06FD33E219764C2A2E1A7C90A273D8DB0AAC877CE6898967D928`. |
| BG-10 | LiteRT physical field model | EXCLUDED/BLOCKED — three explicitly tagged fixture/runtime checks; not counted as passing. |
| BG-11 | `dart run build_runner build --delete-conflicting-outputs`, blob comparison and `git diff --check` | PASS — generator completed; tracked generated database blobs equal the index; no generated/native drift or whitespace error. The current build_runner reports that `--delete-conflicting-outputs` is obsolete and ignores it without affecting the successful generation. |
| BG-12 | Standard/Adventure command equivalence, feature-off, emergency-off and exact product-cardinality contracts | PASS in the focused and complete Flutter suites; Adventure remains presentation-only and Standard output/evidence authority is unchanged. |

The generated Final 8/44 Test Plan also passes its exact check at schema v23:
fingerprint
`ec068b590b05103e2c33f2dbcd51bd570e37262b15cf175f7a6826d3e19b9b81`,
source `c8784d0398ac762db6e1d322ffac2b2bed210b8f`. The source pin intentionally
precedes the documentation-only fingerprint refresh and the narrow Gitleaks
policy commit; neither changes the generated product/test catalog.

## Full-inventory classification

| Initial failures | Count | Disposition |
| --- | ---: | --- |
| Stale Final 8/44 generated plan/review contracts | 2 | Fixed by regenerating schema-v23 artifacts; the dedicated 18-test contract pair and generator `--check` pass. |
| Stale Review Center source-location contract | 1 | Fixed to inspect `today_hub_view.dart` and the extracted `_todayActions()` region; the dedicated screen suite passes 17 tests. |
| iOS notification/CocoaPods contract | 1 | Explicit `release-excluded`; remains blocked for iOS enablement. |
| Physical field-model fixture/runtime checks | 3 | Explicit `release-excluded`; remain blocked for model enablement. |

The two accepted full runs exclude only tests carrying the executable
`release-excluded` tag. This tag does not turn an excluded surface into a pass.

## Explicit exclusion and pending-certification matrix

| Surface | Status | Enablement/completion condition | Owner |
| --- | --- | --- | --- |
| iOS notifications/release | EXCLUDED/BLOCKED; the repository has no `ios/Podfile`. | Restore or approve a replacement CocoaPods contract and complete iOS 13+ certification. | Mobile Platform Lead |
| Desktop | EXCLUDED/BLOCKED. | Define and pass a separate desktop platform gate. | Mobile Platform Lead |
| LiteRT field model | EXCLUDED/BLOCKED; approved model fixture and physical-device evidence are absent. | Supply checksum-pinned approved fixture and complete model/device certification before reachability. | ML/Field Lead |
| Remote AI Voice / OmniVoice GPU | EXCLUDED/BLOCKED; only the CPU service suite is counted. | Resolve or renew the optional GPU dependency disposition, then certify the compatible Torch/Torchaudio/OmniVoice/CUDA stack on physical GPU before separate enablement. | Voice/ML Lead |
| TalkBack, Switch Access, keyboard traversal and certified-device performance | PENDING EXTERNAL CERTIFICATION; automated responsive/accessibility coverage is green but is not a device sign-off. | Run the approved device/profile matrix, archive p95/frame measurements and obtain Accessibility QA approval. | Accessibility QA Lead |
| Research instrumentation / MDS | GOVERNANCE-BLOCKED; no research entities or capture were added. | Approve the protocol, instruments, response-code catalog, class-specific power calculations, analysis policy and privacy/ethics package. | Research / Privacy / Ethics owners |
| UAT and rollout | PENDING EXTERNAL EXECUTION. | Complete the approved adult/minor, accessibility and guardian–learner cohorts and record signed MS-08A/MS-08B decisions. | UAT and Release owners |
| Pair prototype PM0–PM8 | NOT AUTHORIZED. | Approve Pair ADR/SRS/SDS/RTM v1.2 and authorize its separate delivery flag. | Product / Architecture owners |

## Dependency and build-warning disposition

- OSV passes with the existing reviewed exception for
  `GHSA-w5hq-g745-h8pq` in `uuid@9.0.1`, reachable only through the optional
  Firebase Admin Storage path; the project uses Firestore, not Storage.
- Eight Torch advisories remain confined to the optional OmniVoice GPU
  research group. That capability is excluded and release-blocked; the CPU
  Voice suite is the only passing release-scope evidence.
- The Android build warns that `firebase_app_check`, `flutter_tts`,
  `speech_to_text` and `workmanager_android` still apply the Kotlin Gradle
  plugin conventionally. Migration to Gradle's built-in Kotlin support is a
  future toolchain-owner action; the current build succeeds.
- Android tooling also reports SDK XML version 4 while one component
  understands up to version 3. This is retained as a non-blocking local
  toolchain warning because manifest contracts and APK construction pass; it
  becomes blocking if a release build, manifest contract or certified device
  run fails.

## Packaged media budget

The `assets/` tree contains three files totalling 223,126 bytes. It contains
zero packaged visual bytes and zero packaged audio bytes; `pubspec.yaml`
packages only `assets/fonts/NotoSansThai-Variable.ttf`. The ≤5 MB packaged
visual requirement therefore passes locally, and no bundled audio can bypass
the separately downloadable-audio policy.

## Task 6.3 decision

**PASS for local Android/shared engineering scope.** BG-01–BG-12 have fresh,
classified evidence with zero unclassified failure. Checkpoint 6 is not yet
accepted: formal Task 6.2 device accessibility/performance certification and
Task 6.4 UAT/rollout execution remain pending, while Task 5 research and the
Pair prototype remain blocked by their independent approvals.
