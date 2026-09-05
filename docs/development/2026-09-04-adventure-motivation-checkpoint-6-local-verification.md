# Adventure Motivation — Checkpoint 6 Local Verification Evidence

Date: 2026-09-04; performance and completion addenda 2026-09-05 (Asia/Bangkok)

Scope: Task 6.3 local engineering verification for the approved Android/shared
Adventure Motivation delivery, including the Task 3.2-3.3 production closure
and Task 6.2 automated-accessibility addendum below. This record is **local
engineering evidence only**. It is not formal device
accessibility/performance certification, UAT or rollout approval, research/MDS
authorization, or Pair prototype authorization.

## Reproducible environment

- Branch: `feature/adventure-motivation-plan`
- Evidence source before this document:
  `be2ef6dbb3423e794fbf0921c0c22073614f69ba`
- Task 3.2-3.3 implementation source:
  `f8a5f8bbf2bc90fd21b3b365f8f9e109dff1a0bc`
- Exact recovery/pinned-read hardening source:
  `703aabe4d8c38343f53bc72ecdc264097fd2180c`
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
| BG-03 | `flutter test --no-pub --exclude-tags release-excluded --reporter compact` | PASS — 3,542 tests, 3m20s. |
| BG-03 | Same suite with `--concurrency=1` | PASS — 3,542 tests, 10m50s. |
| BG-04 | Adventure/Learning/bootstrap/navigation/scenario/architecture authorities | PASS — 391 tests. |
| BG-04 | Preferences/Sync/Identity/Export authorities | PASS — 387 tests. |
| BG-04 | Fresh schema/migration/cardinality/architecture focus | PASS — 40 tests. |
| BG-04/BG-12 | Fresh Adventure entry/bridge, runtime kill-switch, navigation, quiz, production contract and delivery-cardinality focus | PASS — 91 tests. |
| BG-05 | AI API / Voice API CPU-only / LexiQuest LM | PASS — 76 / 55 / 75 tests. Optional external Voice E2E/GPU execution remains excluded as declared below. |
| BG-06 | Firestore Rules / Firebase Auth emulator suites | PASS — 85 / 3 tests. |
| BG-07 | `gitleaks git . --redact --no-banner` | PASS — 780 commits, approximately 116.21 MB, no leaks. One historical fixed non-secret preference-lease fixture is allowed only by exact path and exact value regex in `.gitleaks.toml`. |
| BG-08 | `tool/cli/verify-osv-locks.ps1` | PASS for all six scanned scopes under the approved Android/shared policy; no unapproved or expired release-scope finding. |
| BG-09 | Android manifest security and smoke-script contract suites | PASS — 15 manifest assertions plus the bounded Android smoke contract. |
| BG-09 | `flutter build apk --debug --no-pub` | PASS — `build/app/outputs/flutter-apk/app-debug.apk`, 223,102,333 bytes; SHA-256 `951F53BC5551E0DCDA631346F89015F31EDA52BAB01A48F9C9C2691BAFE7E64A`. |
| BG-10 | LiteRT physical field model | EXCLUDED/BLOCKED — three explicitly tagged fixture/runtime checks; not counted as passing. |
| BG-11 | `dart run build_runner build --delete-conflicting-outputs`, blob comparison and `git diff --check` | PASS — generator completed; tracked generated database blobs equal the index; no generated/native drift or whitespace error. The current build_runner reports that `--delete-conflicting-outputs` is obsolete and ignores it without affecting the successful generation. |
| BG-12 | Standard/Adventure command equivalence, feature-off, emergency-off and exact product-cardinality contracts | PASS in the focused and complete Flutter suites; Adventure remains presentation-only and Standard output/evidence authority is unchanged. |

## Task 6.2 Android performance rehearsal addendum — 2026-09-05

The source-gated profile runner is implemented at
`tool/cli/run-adventure-performance-profile.ps1`, with the production profile
at `integration_test/adventure_performance_profile_test.dart` and 187 runner
contract assertions. Fresh verification from committed source
`85b17755a81592ed276aa4c9e1a04d456f6fc8fd` produced
`emulator_rehearsal` / `not_certified` evidence on an Android 15 Pixel 6 AVD
at 1080 x 2400 px, 420 dpi, and 60 Hz using the NVIDIA RTX 3050 host renderer.

| Rehearsal check | Result |
| --- | --- |
| Runner contracts | PASS — 187/187; malformed schema, scalar arrays, incomplete frame coverage, dirty source and pre/post-run commit drift all fail closed. |
| Focused analyzer | PASS — zero issues in the integration profile and driver. |
| Source binding | PASS — pre/post HEAD both `85b17755a81592ed276aa4c9e1a04d456f6fc8fd`; no staged, unstaged-content or untracked drift. |
| Entry / projection / first render p95 | PASS — 0.017 ms / 0.710 ms / 57.064 ms against 50 ms / 100 ms / 1,500 ms. |
| Paired Adventure-minus-Standard start overhead p95 | PASS — 0.181 ms against 150 ms; paired authority invariants are true. |
| Map/List frames | PASS — 20/20 transitions contributed real frames, minimum 6 each, 120 total; p95 4.290 ms, maximum 7.031 ms, zero frame over 100 ms. |
| Bounded timeline tasks | PASS — p95 0.701 ms, maximum 4.545 ms, zero task over 100 ms; 5,733 source events remain below the 100,000-event bound. |
| Untimed behavior | PASS — the production controller observed an injected monotonic advance of 601,000 ms, counted only 300,000 ms active effort, excluded 301,000 ms idle and remained active/operation-capable under the same `Timeout.none` policy used by the test. |
| Evidence integrity | PASS — integration JSON SHA-256 `fcf0df09c83abb1dae82bf21b042631caaa8bcf7752524f3499fdc4f121bb032`; no raw frame/timeline arrays are retained. |

The definitive ignored artifacts are
`build/adventure-performance/adventure-performance-20260904T183551631Z-85b17755a815-emulator-5556.evidence.json`
and its paired `.integration.json`. An earlier Android 15 SwiftShader rehearsal
missed the frame budget at 44.434 ms p95; it remains a recorded failure and is
not represented as passing. The host-GPU result closes local rehearsal only;
it does not replace the approved physical-device or assistive-technology
matrix.

The generated Final 8/44 Test Plan also passes its exact check at schema v23:
fingerprint
`70bbd0877b9ab465b85fa0ec07b049cd1d9baca27c201444421833cad72392d2`,
source `703aabe4d8c38343f53bc72ecdc264097fd2180c`.

## Task 3.2-3.3 and Task 6.2 automated completion addendum — 2026-09-05

Production source `f8a5f8bbf2bc90fd21b3b365f8f9e109dff1a0bc`, followed by
exact-recovery hardening source
`703aabe4d8c38343f53bc72ecdc264097fd2180c`, closes the mixed-review,
supportive-repair and restart-recovery path without changing the Standard
learning authority. Session pins are immutable before the first asynchronous
boundary, exact persisted checkpoint intent distinguishes flashcard skip from
exposure after restart, exact pinned reads freeze caller input before their
query boundary, active-owner configuration persistence is atomic, cached
terminal summaries are revalidated, and stale/ambiguous owner or session state
fails closed.

| Completion check | Result |
| --- | --- |
| Repair scheduling, flashcard reentrancy and immutable prompt-catalog snapshots | PASS — 37/37 focused tests. |
| Canonical restart and terminal-summary recovery | PASS — 26/26 focused tests. |
| Immutable pinned-session startup and Drift transaction fencing | PASS — 56/56 focused tests. |
| Atomic active-owner configuration persistence and production launch integration | PASS — 144/144 focused tests. |
| Corrective exact-intent restart, controller retry and frozen exact-pin-read focus | PASS — 96/96 tests across five controller/recovery/repository files. |
| Broad Adventure/Learning/bootstrap/navigation/runtime/architecture regression | PASS — 658/658 tests. |
| Complete Flutter inventory, default / `--concurrency=1` | PASS — 3,542/3,542 in each mode (3m20s / 10m50s). |
| `flutter analyze --no-pub lib test` | PASS — zero issues. |
| Local secret/dependency gates | PASS — Gitleaks scanned 780 commits with no leak; all six OSV lock scopes passed under the documented release policy. |
| Final Android debug APK | PASS — 223,102,333 bytes; SHA-256 `951F53BC5551E0DCDA631346F89015F31EDA52BAB01A48F9C9C2691BAFE7E64A`. |
| Exact 8/44 feature-map check | PASS — revision 1.3.0 and SHA-256 `41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4`. |
| Deterministic presentation goldens | PASS — four scenes cover Adventure typed recall, flashcard reveal at 200% text with reduced motion, dark/high-contrast support state, and recovered Standard state; all four were visually inspected. |
| Generated Final 8/44 Test Plan | PASS — schema-v23 fingerprint `70bbd0877b9ab465b85fa0ec07b049cd1d9baca27c201444421833cad72392d2`, source-pinned to the hardening commit above. |

The automated Task 6.2 scope is complete. Physical TalkBack, Switch Access,
keyboard traversal and certified-device performance evidence remain external
certification requirements and are not represented as passing here.

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
| TalkBack, Switch Access, keyboard traversal and certified-device performance | PENDING EXTERNAL CERTIFICATION; automated responsive/accessibility coverage, four deterministic golden scenes and a source-gated host-GPU emulator performance rehearsal are green, but none is a physical-device sign-off. | Run the approved physical device/profile matrix, archive p95/frame and assistive-technology measurements, and obtain Accessibility QA approval. | Accessibility QA Lead |
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
accepted: formal Task 6.2 physical-device accessibility/performance certification and
Task 6.4 UAT/rollout execution remain pending, while Task 5 research and the
Pair prototype remain blocked by their independent approvals.
