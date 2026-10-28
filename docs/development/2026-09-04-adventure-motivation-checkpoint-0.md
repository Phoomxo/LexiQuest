# Adventure Motivation — Checkpoint 0 Baseline Evidence

Date: 2026-09-04 (Asia/Bangkok)

Scope: implementation-ready shared foundation and Android Pilot baseline for
the approved Adventure Motivation plan. Excluded platforms and optional
capabilities are recorded as blocked, never as passing.

## Reproducible environment

- Evidence checkout before this document: `71ae275efa4bcd20d4ded7464c8f0bd6351dcefe`
- Worktree: `C:\Users\Phet\Documents\LexiQuest\.worktrees\adventure-motivation-plan`
- Package config: `C:\Users\Phet\Documents\LexiQuest\.worktrees\adventure-motivation-plan\.dart_tool\package_config.json`
- Flutter: 3.44.7 stable, framework `84fc5cbb22`
- Dart: 3.12.2 stable on `windows_x64`
- Gitleaks: 8.30.1
- OSV-Scanner: 2.4.0
- `flutter pub get --offline`: exit 0; generated desktop registrar drift was
  reviewed and removed from the branch.

## Closed baseline defects

| ID | Closure | Verification |
| --- | --- | --- |
| BL-01 | Regenerated the final 8/44 plan through its generator; source `ae321f622448004faac6626ca30afc1b0722fd60`, fingerprint `27124f157c0d3f8e0000900afca86af7cd45440cfbeae38ee69249dc431ce3e5`. | Generator `--check` exit 0; contract/review tests 18 pass. |
| BL-05 | Historical schema guard now follows `AppDatabase.currentSchemaVersion`. | Phase -1/associative group 61 pass. |
| BL-06 | Reward-authority guard no longer treats handwriting coordinates as a second points ledger and retains a prohibited-alias negative fixture. | Phase -1/associative group 61 pass. |
| BL-07 | Bootstrap scenarios inject isolated application-support directories; restart tests use current dependency scope and retry identity. | Seven audited cases plus two related cases pass; bootstrap/offline suites 120 pass. |
| BL-08 | Associative Reading navigation uses stable route/glossary identity and Thai production copy. | Phase -1/associative group 61 pass. |
| Android smoke drift | Profile assertions use the navigation glossary and wait for the return transition before opening the drawer. | Physical Android-emulator core journey 1 pass, all 23 phases complete. |

## Fresh gate results

| Gate | Command/scope | Result |
| --- | --- | --- |
| BG-01 | Feature-map generator `--check` | PASS — revision 1.3.0, 44 capabilities, hash `41e15622e6d367ca706fef41a0b3e10b5dfcb56033b3fdf194594be458dd38d4`. |
| BG-02 | `flutter analyze --no-pub` | PASS — no issues. Three deprecated test APIs were migrated before this result. |
| BG-03 | Full Flutter inventory, default concurrency | 3,214 pass / 4 excluded failures / 0 unclassified failures, 3m00s. |
| BG-03 | Full Flutter inventory, `-j 1` | 3,214 pass / 4 excluded failures / 0 unclassified failures, 9m50s. |
| BG-04 | Learning, progress, rewards, Today Hub, time tracking and quest authority suites | PASS — 627 tests. |
| BG-05 | AI API / Voice API / LexiQuest LM | PASS — 76 / 55 / 75 tests; one Voice external E2E intentionally opt-in and skipped. |
| BG-06 | Firestore Rules / Firebase Auth emulators | PASS — 84 / 3 tests. |
| BG-07 | `gitleaks git . --redact --no-banner` | PASS — 713 commits, approximately 114.73 MB, no leaks. Fifteen immutable non-secret test fixtures are fingerprint-exact allowlist entries. |
| BG-08 | OSV over Flutter, npm, AI, Voice, LM and HF Space locks | PASS for Android/shared release scope. LM `datasets` is fixed at 5.0.1. npm has one approved exception until 2026-10-26. Voice has eight optional-GPU exceptions until 2026-09-11 and remains excluded/release-blocked. |
| BG-09 | `flutter build apk --debug --no-pub` | PASS — `app-debug.apk`, SHA-256 `B5C51BF4062E5B681439F16BF99B7771502DB231C302656F2FD194BA71583D9E`. |
| BG-09 | Bounded core smoke on `emulator-5554`, Android API 35 | PASS — 1 integration test, 23 traced phases. |
| BG-10 | Field model | EXCLUDED/BLOCKED as declared below; not counted as pass. |
| BG-11 | Focused diff and worktree status | PASS — only scoped commits; no generated/native registrar drift. |

## Explicit exclusion matrix

| Surface | Android Pilot v1 status | Enablement condition | Owner |
| --- | --- | --- | --- |
| iOS notifications/release | EXCLUDED/BLOCKED; `ios/Podfile` is absent and the iOS contract test remains red. | Restore or approve a replacement CocoaPods contract and run iOS 13+ evidence. | Mobile Platform Owner |
| Desktop | EXCLUDED/BLOCKED. | Define and pass a separate desktop platform gate. | Mobile Platform Owner |
| LiteRT field model | EXCLUDED/BLOCKED; the checksum-pinned model fixture is intentionally absent, accounting for three test failures. | Prepare the approved model fixture and complete device/model certification before making the capability reachable. | ML/Mobile Owner |
| Remote AI Voice / OmniVoice GPU | EXCLUDED/BLOCKED; eight Torch findings are filtered only by the time-bounded optional-research policy. | Upgrade and verify a compatible Torch/Torchaudio/OmniVoice/CUDA stack on physical GPU before 2026-09-11 or renew an approved disposition; then enable reachability separately. | Voice Backend Owner |

The four full-inventory failures are exactly one iOS Podfile contract and three
field-model fixture/certification checks. They are outside Android Pilot v1 and
remain red for their own enablement. No shared or Android failure is
unclassified.

## Decision

- `G0A`: PASS — Adventure implementation may begin.
- `G0B` Android Pilot baseline: PASS within the approved Android scope, with
  the exclusions above remaining blocked and not represented as green.
