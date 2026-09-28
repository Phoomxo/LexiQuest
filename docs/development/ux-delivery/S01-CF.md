# S01-CF — stale route and content revision rejection

Canonical checkout: `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`, branch `codex/ux-current-after-s01-bc`, HEAD `c3a69c5fea4a5a9f08be06e2ea5717a937edc34d`.

## Acceptance contract and result

**PASS_NATIVE_SYNTHETIC_STALE_ROUTE_CONTENT_REVISION_REJECTION.** A retained ordinary meaning option callback from the restored QuizScreen must be rejected after a covering route makes that route noncurrent. An exact recovery request must reject a content revision increase even when the spelling and meaning stay the same. Wrong owner/session also reject. Rejection must not append checkpoint, answer, scoring, SRS, reward, achievement, outbox or research rows, mutate the existing owner data, or call external services. The test's one intentional synthetic `vocabulary_words.content_revision` update is the drift stimulus; all 58 table digests are equal immediately before and after the recovery rejection. Host source additionally checks feature and dependency drift at the actual Today route.

The CF debug-only package `com.lexiquest.app.nativeStaleCf` was built in a separate output and installed once on physical V2041/API33 after read-only preflight. Actual AppBootstrap/Today restored the exact draft after PID `9649 → absent → 10228`. CF01–CF05 receipts PASS. The retained callback after a covering route changed no table; after the intentional revision update, `OrdinaryMeaningRecovery.load` rejected and changed no table. Wrong owner and session rejected. The fixture observed zero answer/scoring/SRS/reward/achievement/research/outbox and external operations. Nine protected installed packages and 14 earlier APK files remained unchanged. CB's historical install count remains `UNVERIFIED_UP_TO_TWO_ATTEMPTS`.

The built APK SHA256 is `5f2aa68130d87eaec57ffa90e40df22a12ea382046333153178b1e743f718e9c`. The 850-file build-time source manifest SHA256 is `66cbf8f0f913958f4dcc1156aab8f8c4f47be5e39f7b65749da3fff51253727b`; post-build and post-native source drift were zero. Read-only preflight proved CF absent, matching APK ID, debug flag, one harness activity, and no forbidden permission/component. The runner journal records one install command and one CF force-stop. No CE/CD/CB package, APK or receipt was reinstalled, reseeded, overwritten or removed.

Focused gates on current source: four BV owner/content/revision/route host tests PASS; two CF fixture host tests PASS; nine actual Today resume stages PASS, including feature/dependency/route; CF CLI source/runner contract PASS; five-file analyzer clean; isolated Gradle debug build PASS. The first Gradle command failed only because PowerShell split `-Ptarget`; corrected quoting produced the successful build before any install. No production `lib`, schema, scoring, SRS, reward, route, feature gate or research source changed in CF. `evidence/S01-CF-validation.json` and immutable `evidence/S01-CF-checkpoint.json` pin commands, artifacts and receipts.

CF-scoped `git diff --check` passed. Repository-wide `git diff --check` still reports CRLF-related trailing-whitespace errors in the pre-existing BY changes to `lib/features/learning/application/learning_use_cases.dart`; CF did not edit that file. The full regression/release verifier was not run on this dirty, unfrozen checkout.

## Remaining scope

This closes only the bounded native synthetic stale-route/content-revision authority boundary. N05 visual/IME/TalkBack, actual-user participation/trials and frozen-source release remain **NOT_RUN/DEFERRED/OPEN**. Field dailyContinuity remains hidden. Retain CF and every prior installed package/APK without reinstall or reseed. Writer released; no successor dispatched.
