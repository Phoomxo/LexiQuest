# LQ-06 I4d Source Voice — checkpoint

## สถานะและ custody

- 2026-10-23: **bounded local I4d engineering-complete**, awaiting root acceptance; **RETURN** sole production writer + serialized Flutter/test/analyze/format slot. No next-card execution is authorized by this handoff.
- Worktree `C:\Users\Phet\Documents\LexiQuest`; branch `feature/associative-reading-loop`; HEAD unchanged `f43aa0fff2155ca29d6a26f2695191dd44a2d6d1`.
- Authority: explicit root **I4d EXCLUSIVE IMPLEMENTATION TRANSFER NOW** dispatch after coordinator RETURN. Coordinator checkpoint `docs/field/2026-10-20-lq-00-wave-0-checkpoint.md`, SHA256 `3FB679BA04AFCD24336C8B3AC3EC4E18B3263B39108FB9F62E019C866F22A1F1`; its ready text alone was not treated as a grant.
- ADLC: approved intent/write set/acceptance → current-source grounding → TDD → independent read-only review → current-snapshot attestation. Integration acceptance remains root's next step.
- Dirty/untracked predecessor changes preserved. Source screen/test already existed and include accepted I4a/I4b/I4c work; tracked Speak diff also includes predecessor M1a changes. Do not treat the entire HEAD diff as I4d-only.
- No commit/merge/deploy/publish/cleanup/native/schema/dependency/authority changes. LQ-06 cap30/program250 unchanged; actual spend unavailable.

## Exact five-path write set

1. `lib/screens/source_practice_screen.dart`.
2. `lib/screens/speak_to_text_screen.dart`.
3. `test/screens/source_practice_screen_test.dart`.
4. `test/screens/speak_to_text_screen_voice_test.dart`.
5. This new `docs/field/2026-10-23-lq-06-i4d-source-voice-checkpoint.md`, after equivalent-file discovery and existence checks.

## ผลงานที่อยู่ในขอบเขต

- Source exposes `Voice: <first confirmed currently matched existing word>`. Preview/edit/confirmation creates no learning session/answer/reward/outbox. Explicit launch reuses `_validatedPreviewForLaunch`, existing launch serialization and `startSourcePracticeForWords(wordIds: [target.id], limit: 1)`.
- Revalidate after the session-start await; reject empty/wrong target/category/spelling, deleted word, changed owner, changed learning authority, pending edits and double launch. A session already created by an explicit launch is never given a fabricated answer or completion when later revalidation fails.
- Capture nonnull owner and learning before awaits, and pass those captured values into the route builder. A late Source review cannot clear the owner value in the builder and silently turn the page into standalone mode.
- Speak uses an explicit source mode through injected existing learning + owner/session/word. No new recorder, SRS/reward authority, domain/controller/gateway abstraction or persistence layer. Standalone speech keeps its existing Word Scramble behavior; Source finishes back to the original Source page instead.
- Microphone starts only on explicit action. Stop reference TTS before recognizer startup; check owner/lifecycle around asynchronous work. Existing speech generation guards reject empty/noMatch/cancelled/late/duplicate callbacks. Owner or source identity replacement invalidates the page permanently; target/transcript/assessment/saved success text and accessibility target labels do not leak into the invalid owner state.
- Freeze one final nonempty `RecordAnswerCommand` in memory: stable attempt ID, received UTC timestamp, elapsed duration, correctness, attempt number, owner/session/word and engine/locale/method provenance. Record only via existing `LearningUseCases.recordAnswer(promptMode: 'pronunciationTranscript')`; raw transcript/document/file/passage metadata is not persisted or forwarded as evidence.
- Failed/uncertain/lost-ack save retains that exact command; retry is explicit. Mic/conflicting persistence actions are locked while saving or after a final is frozen. Cancel/Back also fences Save/Finish while awaiting cleanup. Cleanup failure is visible and does not falsely claim safe exit or successful persistence.
- After acknowledged save, correct and incorrect assessments can explicitly Finish via existing `finishSession`. Failed/lost-ack Finish requires explicit idempotent retry; only acknowledged matching completed summary permits return. Back/cancel never invents completion or undoes an already committed answer.
- Voice services receive only the selected known word for reference speech, not file/passage/source metadata. Recognition audio uses the existing platform path. UI explicitly describes transcript similarity, not phoneme alignment, pitch or acoustic pronunciation accuracy; no offline-only claim.
- Existing Reading/Quiz/Flashcards/Ask Lexi, T1 owner-scoped credential-only storage/per-launch explicit provider+summary activation, I5a modes/budgets and research defaults remain unchanged.

UI skills retained incumbent Material controls/theme/SafeArea and added only the Source action, bounded state feedback and explicit retry/Finish/cancel controls. Tests cover portrait360x800 and landscape800x360 at2x, light/dark/reduced-animation Speak layouts, Source2x+IME reachability, labelled controls and ≥48dp primary targets. No new design system/framework/dependency/assets.

## TDD, recovery และ review

- Baseline whole Source/Speak files: **36/36,exit0,01:43**, before implementation.
- Source action RED: expected `start-source-voice`, found0; minimal launch then passed. Source Voice guard suite14/14 and actual Source→Speak→real save→Finish→original Source without Gemini passed before broader integration.
- Speak behavioral RED4: missing retry/Finish, TTS not stopped before permission, owner change during TTS stop still dispatched mic. Implemented source state/admission using existing authorities; whole Speak initially exposed an existing-startup regression caused by new foreground flag not rebuilding on resume. Instrumented synthetic state, fixed resume rebuild, removed diagnostic prints; legacy regression retained and passed.
- Independent review found Important2: Cancel cleanup could race persistence, and invalid-owner semantics retained the old target. Verified RED and fixed method/button guards + generic semantics label. Further RED covered old callback rebinding after widget source identity replacement, and saved-success text retained after owner invalidation; fixed view invalidation, not persisted evidence.
- Final primary review reproduced a deferred route-builder race: delayed Source review cleared mutable owner, actual route builder returned sourceOwnerId=null. Focused RED expected `local:owner-a`, actual null; owner/learning capture fix then focused1/1 passed. This was an in-scope correction, not an authority/write-set expansion.
- Test-harness recovery: Drift and domain both exported `LocalOwner` (fixed explicit `hide LocalOwner`); `pumpAndSettle` timed out on deliberately pending indeterminate save/finish (replaced with bounded condition pumping, preserving assertions); lazy widgets required bounded scrolling; semantics test needed merged-label matching and deterministic handle disposal. Atomic patch context mismatches were reconciled by reading actual files before correction. No test deletion/skip/assertion weakening.
- All Flutter/Dart commands serialized in I4d; no overlapping test/build/cache operations, process killing or DLL cleanup. Read-only review and unrelated test-file authoring did not alter inputs of a running check.
- Whole Source/Speak run **73/73,exit0,03:18** preceded the final owner-success clear, stronger Finish assertions and final route-builder test/fix. It is historical evidence, not a claim of a current74-case focused run.
- Whole Speak **31/31,exit0,00:06** after owner-success clear; final stronger real-Drift test **1/1,exit0,00:02** after explicit first-Finish comparisons; final route pin test **1/1,exit0,00:08** after capture fix. Previous connected682 runs passed but preceded the final Source pin correction; only the final connected command below attests the final four-file manifest.
- Reviewer `/root/i5a_review` refreshed all final deltas and hashes: **accepted,Critical0/Important0/Minor0**. Reviewer performed no Flutter/Dart/analyzer/formatter/scanner writes or executions; primary owns executable evidence below.

## Real Drift proof

The real in-memory Drift widget test uses synthetic voice/STT and a forwarding repository that commits then loses acknowledgement once at each boundary:

1. Final `CaT` recognition freezes one correct command; first save commits but throws a synthetic lost ack.
2. Explicit save retry reuses ID/time/duration/correctness/provenance and is accepted as replay. Entire attempts/SRS/XP/coin/outbox snapshot is unchanged: one attempt, one SRS projection, XP amount1, coin amount1, one logical attempt outbox and SRS-state outbox, no rewardTransaction transport operation under existing rules. No raw `CaT` transcript or research/event rows are stored.
3. First Finish commits then loses ack. Attempts/SRS/XP/coins are explicitly compared to pre-Finish values and remain unchanged. Explicit Finish retry leaves the entire post-Finish snapshot and endedAt timestamp unchanged, then returns. Finish may create the existing achievement/outbox effects once; it does not mint extra answer XP/coin or duplicate logical operations.

## Exact final verification commands

```powershell
flutter test --no-pub test/features/media_practice test/voice test/features/learning test/features/rewards test/features/identity test/features/account test/features/consent test/features/vocabulary test/features/gemini test/features/sync/reward_transaction_sync_test.dart test/screens/source_practice_screen_test.dart test/screens/speak_to_text_screen_voice_test.dart test/screens/ai_tutor_screen_test.dart test/screens/shadowing_challenge_screen_test.dart test/screens/ghost_shadow_duel_screen_test.dart test/screens/quiz_screen_test.dart test/screens/srs_flashcards_screen_test.dart test/screens/choose_mode_screen_test.dart test/screens/gemini_settings_screen_test.dart test/screens/word_scramble_screen_test.dart test/runtime/app_bootstrap_test.dart test/runtime/account_startup_restore_test.dart test/architecture --reporter expanded
```

Final current-source result: **683/683 passed,exit0,03:48**, session90884. Includes both whole unfiltered focused files (Source43 + Speak31 =74), plus connected voice/media/learning/reward/owner/account/consent/source/tutor/transport/architecture regression. All data/providers are synthetic/local doubles; real Drift proof is not live provider or device evidence. No production/test input changed after this run; only this checkpoint was finalized.

```powershell
flutter analyze --no-pub lib/screens/source_practice_screen.dart lib/screens/speak_to_text_screen.dart test/screens/source_practice_screen_test.dart test/screens/speak_to_text_screen_voice_test.dart
dart format --output=none --set-exit-if-changed lib/screens/source_practice_screen.dart lib/screens/speak_to_text_screen.dart test/screens/source_practice_screen_test.dart test/screens/speak_to_text_screen_voice_test.dart
git diff --check -- lib/screens/speak_to_text_screen.dart test/screens/speak_to_text_screen_voice_test.dart
```

- Final four-file analyzer after route capture fix: **No issues found,exit0,3.2s**. Earlier analyzer infos (two braces + explicit mounted guard) were corrected before final tests, not ignored.
- Final formatter:4 files/0 changed,exit0,0.14s. Scoped tracked diff check:exit0. Manual trailing-whitespace check:0 lines across all four files, including untracked Source files. Git's existing LF→CRLF warnings are not broad normalization changes.

## SHA-256 manifest

| Path | Before I4d | Final verified source/test |
| --- | --- | --- |
| `lib/screens/source_practice_screen.dart` | `8D5391641EF4765B0EBEC45082835127F5B08BD2109C0C4674216F80D1C9FAA4` | `AA9321F86F0D266186B6B8E6D4CCB8F6C2798A776538FCA0ADA38D954FF3C950` |
| `lib/screens/speak_to_text_screen.dart` | `12FF0685DD4C58A0DDAAF611C2FF33D2895FED9686AE061F827B26D75BC3F150` | `A2CD98DEA12892BC97C657C1D15EE28B8C2B98A4B250D6BE08360B6C756A620F` |
| `test/screens/source_practice_screen_test.dart` | `0EA56F8B31A5D827BFAC2269179D1793C0EF93C82DDF0381FDD5441652B0F293` | `2710D9C257D566E036FB4A6A003426C22D3202316110B40F34E717A0A73DA233` |
| `test/screens/speak_to_text_screen_voice_test.dart` | `E9834040D2FB6113E2F08F85B01E76ACAF10F2C9D5B118B7811BD3A85D63FF52` | `8E294FE12FD4B0F27B2D10EFB197A8D3D3642988C38EB80BB3A0DF2E07DDCFDB` |

Checkpoint SHA is returned separately to avoid a circular self-hash.

## Runtime, limits และ next step

```powershell
Get-CimInstance Win32_Process | Where-Object { $_.Name -match '^(dart|dartvm|dartaotruntime|flutter_tester|gen_snapshot)(\.exe)?$' } | Select-Object ProcessId,ParentProcessId,Name
```

Final runtime inventory: **0**, including dartvm.exe. No task-owned Flutter/Dart/test commands remain. Programmatic final hash reconciliation matched **4/4** against the reviewed manifest after all checks; branch/HEAD unchanged. No unresolved implementation/test/review blocker remains inside bounded I4d.

Not run: full-repository suite/analyze/APK, real device/physical microphone/TTS/provider/Cloud, native callback attribution, new screenshots/goldens/contrast measurement, comprehensive hardware accessibility/UAT or efficacy. M1a untagged native callback attribution and actual recognition/cleanup behavior remain explicit device limitations. Transcript similarity is not acoustic pronunciation validation or a guarantee of offline operation; response duration includes recognition startup/permission time, not calibrated fluency.

Retry identity/evidence is view-local; no durable crash/session resume, source history/provenance or schema was added. An explicitly started session may remain active after later invalidation/back/cancel; no fabricated completion or destructive cleanup is performed. Owner checks fence view actions and awaited results, not a new atomic owner/native transaction or rollback guarantee.

Full I4, research engineering/readiness and whole-app release remain open. S3a/v11 held/unreserved; 8/44 catalog and EvidenceContext/EventEnvelopeV2 untouched. No real enrollment/upload/deployment/publication/security worker/Claude401 retry. No live credentials or participant data used. T1 credential-only/per-launch activation policy unchanged.

Next executable step after RETURN: root independently reconcile final4/4 hashes + checkpoint SHA, read final disposition and current-source evidence, then accept bounded I4d or issue a concrete correction/next exact transfer. LQ-06 must not start another card automatically.
