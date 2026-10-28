# LexiQuest P8-D Real Speech Evidence Implementation Plan

**Status:** READY FOR EXECUTION

**Scope:** Persist real microphone/STT evidence — recognized transcript, similarity
score, STT engine, similarity algorithm version, and typed unavailable reasons —
through the Drift local repository so pronunciation evidence no longer collapses
to a single boolean. Centralize provenance and make silence/failure typed states
rather than zero scores. Remove the unused cosine-similarity evaluator.

**Out of scope:** Cloud outbox/sync for speech evidence, weakness/SRS policy
extensions, acoustic pitch/phoneme measurement, real-device certification, and
production rollout. Those remain P8-E onward.

**Upstream:** P8-C through `022d03c`.

## Delivery rules

- Work one bounded file at a time and run the focused contract after each
  coherent slice.
- The real microphone is reached only through the existing authenticated
  `SpeechRecognitionGateway`; no new plugin boundary is introduced.
- Never fabricate pitch, phoneme, confidence, or accuracy values. Unsupported
  measurements display as an honest unavailable state (spec §9).
- Silence, permission denial, cancellation, unsupported locale, and provider
  failure produce a typed unavailable reason, never a zero or random score.
- Persisted speech evidence contains only the recognized transcript and derived
  metadata. No raw microphone audio is ever stored.
- The Drift migration is idempotent: `onCreate` creates all tables, and an
  upgrade from schema 6 to 7 only creates the missing speech-evidence table.
- Do not claim real acoustic quality, pitch, phoneme, or physical-device
  acceptance until those paths run with recorded evidence.

## Dependency order

1. Centralized provenance and typed unavailable states.
2. Drift `SpeechEvidence` table (schema version 7).
3. Speech evidence repository and use cases.
4. Wire Shadowing and Speak-to-Text to persist real evidence.
5. Remove the unused cosine-similarity evaluator.
6. Bounded P8-D gate and evidence.

## Task 1: Centralize pronunciation provenance and typed unavailability

**Files, one at a time:**

- Create `lib/features/media_practice/domain/speech_evidence_contract.dart`
- Modify `lib/features/media_practice/application/speech_practice_use_cases.dart`
- Create `test/features/media_practice/speech_evidence_contract_test.dart`
- Modify `test/features/media_practice/speech_practice_use_cases_test.dart`

Define a versioned `SpeechEvidenceProvenance` value type carrying the STT engine,
locale, and similarity method, plus a single `toProvenanceString()` builder so
every screen emits the same `engine|locale|method` shape. Define
`SpeechEvidenceUnavailable` (`silence`, `permissionDenied`, `cancelled`,
`unsupportedLocale`, `providerFailure`) and a typed result so `assess()` returns
an unavailable state instead of a zero score when the canonicalized target or
transcript is empty. Existing scoring for non-empty transcripts is unchanged.

**Commit:** `feat(speech): centralize pronunciation provenance`

## Task 2: Add the Drift speech evidence table

**Files, one at a time:**

- Create `lib/data/local/tables/speech_evidence_tables.dart`
- Modify `lib/data/local/app_database.dart`
- Run `dart run build_runner build`
- Create `test/data/local/speech_evidence_table_test.dart`

Create a `SpeechEvidence` table with columns: `id`, `ownerId`, `sessionId`,
`wordId`, `promptMode`, `targetContent`, `recognizedTranscript`, `locale`,
`sttEngine`, `similarityAlgorithm`, nullable `similarityScore`, `isExactMatch`,
nullable `recognitionConfidence`, `sampleSize`, nullable `unavailableReason`,
`occurredAtUtcMs`, nullable `durationMs`. Register it in `@DriftDatabase`,
bump `schemaVersion` from 6 to 7, and rely on idempotent `onCreate`/upgrade
helpers. The build_runner step regenerates `app_database.g.dart`.

**Commit:** `feat(data): add speech evidence table`

## Task 3: Add the speech evidence repository

**Files, one at a time:**

- Create `lib/features/media_practice/data/drift_speech_evidence_repository.dart`
- Create `lib/features/media_practice/domain/speech_evidence_use_cases.dart`
- Create `test/features/media_practice/drift_speech_evidence_repository_test.dart`

`DriftSpeechEvidenceRepository.recordSpeechEvidence(command)` resolves the active
owner, inserts one row, and returns the persisted id. `SpeechEvidenceUseCases`
resolves the owner and repository and exposes `record(...)`. No outbox row is
appended in this package (cloud sync remains P8-E onward).

**Commit:** `feat(speech): persist real pronunciation evidence`

## Task 4: Persist real evidence in the speech screens

**Files, one at a time:**

- Modify `lib/screens/shadowing_challenge_screen.dart`
- Modify `lib/screens/speak_to_text_screen.dart`
- Modify `test/screens/shadowing_challenge_screen_test.dart`
- Modify `test/screens/speak_to_text_screen_test.dart`

Both screens record a `SpeechEvidence` row carrying the real transcript, score,
engine, and method version alongside the existing `learning.recordAnswer(...)`
boolean used for SRS. They use the centralized provenance builder and treat a
typed `SpeechEvidenceUnavailable` result as "no score" rather than persisting a
zero. Silence/unavailable cases show a privacy-safe Thai message and never
fabricate an acoustic measurement.

**Commit:** `feat(speech): persist transcript evidence in speech screens`

## Task 5: Remove the unused cosine similarity evaluator

**Files, one at a time:**

- Delete `lib/services/cosine_similarity_evaluator_service.dart`
- Delete `test/services/cosine_similarity_evaluator_service_test.dart`

The evaluator is referenced only by its own test and is not wired into any
production scoring path. Remove it so the authoritative transcript-edit-distance
algorithm is unambiguous.

**Commit:** `chore(speech): remove unused cosine similarity evaluator`

## Task 6: Close the bounded P8-D gate

**Files, one at a time:**

- Create `tool/cli/tests/verify-real-speech-evidence.tests.ps1`
- Create `tool/cli/verify-real-speech-evidence.ps1`
- Create `docs/development/p8d-real-speech-evidence-gate-2026-07-31.md`
- Mark P8-D complete in the authoritative design only after PASS

The gate runs each phase once: format, analyze, focused speech/pronunciation/data
tests, a privacy scan (no raw audio, no fabricated scores, consistent provenance),
debug APK, and `git diff --check`. Evidence records exact commits, versions,
counts, APK hash, and explicit non-certifications.

**Commit:** `test(speech): close P8-D real speech evidence gate`

## P8-D completion boundary

P8-D is complete only after the accepted CLI gate proves that real STT evidence
transcript, score, and provenance is persisted locally, that silence and failure
produce typed unavailable states rather than scores, and that no synthetic score
remains. A fixture-backed gate does not certify real acoustic quality, real
microphone acceptance on a physical device, cloud sync of speech evidence, or a
release-signed APK.
