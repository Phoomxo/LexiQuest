# P3 Learning Core Gate Record

> **Historical gate record.** Results below remain the accepted P3 automated
> evidence. Current field status and later physical-device evidence are
> reconciled in
> `docs/superpowers/specs/2026-07-31-p8-hybrid-voice-field-release-design.md`,
> section 3.1.

**Date:** 2026-07-30

**Result:** PASS

**Scope:** Local learning evidence, deterministic projections, synchronization,
Firestore policy, participant learning screens, and Android debug packaging.

## Accepted behavior

- Quiz reads active owner-scoped vocabulary from Drift and persists an answer
  before advancing.
- Sessions, attempts, response time, score, SRS, points, achievements, reading
  events, and reading progress survive process restart.
- Attempt and reading events enter the outbox and synchronize with
  create-or-identical replay semantics.
- Pulled immutable evidence rebuilds SRS, achievements, and reading projections
  in canonical event order.
- Deleted vocabulary can retain historical evidence without allowing
  cross-owner references.
- Malformed or conflicting immutable cloud evidence does not advance the pull
  checkpoint or overwrite local evidence.
- Guest ownership migration includes pending attempt and reading-event outbox
  operations.
- Empty accounts show sample size zero instead of participant-facing sample
  results.

## Defects resolved during review

The P3 review found and the implementation corrected:

1. incomplete upgrades from schema version 1;
2. blocked pulls for historical attempts whose word was deleted;
3. different local and remote SRS event ordering;
4. projections not repaired by identical event replay;
5. reading timestamps that could regress;
6. learning-session lookup without owner isolation;
7. different local and Firestore evidence limits;
8. missing provider provenance in immutable replay equality; and
9. order-dependent achievement source events.

The follow-up review found no remaining Critical or Important issue in the P3
diff.

## Bounded verification

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-learning-core.ps1
```

Recorded result:

- CLI gate contract: PASS
- Dart format, 47 scoped files: PASS
- `flutter analyze`: PASS, no issues
- Focused Flutter suite: PASS, 88 tests
- Firestore emulator policy suite: PASS, 23 tests
- Android debug APK build: PASS
- `git diff --check`: PASS

Artifact:

- Path: `build/app/outputs/flutter-apk/app-debug.apk`
- Size: 226,979,497 bytes
- SHA-256:
  `5FED5486C9BCA21141B70338D7D7CE6856651DDC09BA2F5109A74B06438484F5`

## Deferred device evidence

The following items require real Android hardware and remain part of field
certification rather than being simulated in P3:

- WorkManager execution after force-stop, restart, and reconnect;
- camera, microphone, TTS, STT, LiteRT, XNNPACK, and GPU-delegate acceptance;
- low-, mid-, and high-tier latency, memory, battery, and thermal measurements;
- 30-minute continuous-use stability; and
- release signing, upgrade installation, and owner smoke test.

The debug APK proves packaging only. It is not the participant release APK.
