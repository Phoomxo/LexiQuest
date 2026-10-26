# Firebase Test Lab physical matrix — release 1.0.0+17

Date: 2026-10-26 (Asia/Bangkok)

Branch: `codex/cycle12-release`

Artifact source commit: `613ee5ef4cea7e795380af1c08ab815528147159`

Disposition: **PHYSICAL HARDWARE SMOKE ACCEPTED; PRODUCTION CLOUD REJECTED**

This checkpoint records a bounded Android Robo run on four physical Firebase
Test Lab devices. It does not authorize Play rollout, App Check enforcement,
production research, or participant enrollment/upload.

## Matrix identity

- Matrix: `matrix-1moy2xtonupzw`
- State/outcome: `FINISHED` / `SUCCESS`
- Console: [Firebase Test Lab result](https://console.firebase.google.com/project/vocab-learning-app-219ef/testlab/histories/bh.599e8b0d28d6d045/matrices/8715911413109364770)
- APK SHA-256:
  `26725A599BBB061D986B90E73CB8C5E6BCD0C767B3DC4828390F6276222A516E`
- Upload certificate SHA-256:
  `E1B00E17896BFB73FE0DC42429768B966465213D49A8A5165DE06688CC8FDC1F`
- Downloaded evidence: 174 files, 200,114,465 bytes
- Evidence manifest:
  `field/evidence/lexiquest-1.0.0+17/firebase-test-lab/matrix-1moy2xtonupzw/evidence-manifest.json`
- Evidence-manifest SHA-256:
  `35083263B08996C4D6C55ABBD4E434DFAF3E7E59862A73C8C0CC6C44FF8E3B7D`

Test Lab used its synthetic auto Google account. No personal owner account was
selected and this run did not enroll a research participant.

## Physical device result

| Class | Physical device | Android / resolution | Robo evidence | Result |
| --- | --- | --- | --- | --- |
| Low phone | realme RMX3231 | API 30 / 720x1600 | 89 events, 32 screens | completed |
| High phone | Samsung SC-51E | API 36 / 1080x2340 | 147 events, 40 screens | completed; one swipe and one dismiss tap were non-blocking Robo action failures |
| Fold | Pixel Fold `felix` | API 34 / 2208x1840 | 123 events, 42 screens | completed; adaptive navigation rail rendered |
| Tablet | Lenovo TB370FU | API 35 / 1840x2944 | 112 events, 35 screens | completed; wide reward grid rendered |

The aggregate result and action traces show that all four crawler executions
reached application content and completed result processing. The two SC-51E
action failures were crawler interactions; the matrix continued and no crash
or infrastructure failure was reported.

## Log and visual review

Exact log scans across all four `logcat` files returned zero matches for:

- `FATAL EXCEPTION` and AndroidRuntime error priority;
- unhandled Dart/Flutter errors;
- RenderFlex overflow;
- `database is locked`;
- package ANR;
- SIGABRT and SIGSEGV.

Representative Login, activity catalog, vocabulary, camera, AI Tutor, reward
store, Fold rail, and tablet-grid screenshots were inspected. No sampled
Flutter error screen, overlapping control, clipped primary action, or
horizontal overflow was found. This sampled review is not an assertion that
every one of the downloaded screenshots was manually certified.

## Production-cloud finding

The Test Lab headline `SUCCESS` is not a production-cloud pass. Every device
logged the following twice after Play Integrity activity:

```text
Error getting App Check token; using placeholder token instead.
Error: ... Too many attempts.
```

The Android App Check SDK's `RetryManager` emits `Too many attempts` only after
an earlier token-exchange failure has put the client into backoff. Firestore
requests in the same runs were rejected with `PERMISSION_DENIED`. The release
certificate, Firebase Android app/package, and off-Play Play Integrity
configuration were re-read and match the signed artifact, but the first
exchange response is not present in the Test Lab logs. Its exact rejection
reason therefore remains unverified.

Required disposition:

- App Check enforcement stays `UNENFORCED`.
- Do not treat placeholder/invalid traffic as valid release evidence.
- The next source snapshot must preflight token availability fail-closed before
  composing cloud account/sync gateways, expose no research path by default,
  and retain ordinary local learning when cloud attestation is unavailable.
- A new signed artifact invalidates this matrix as final-source evidence. Reuse
  it only as `+17` hardware and regression evidence.

## What this matrix does not prove

- hinge posture changes (cover/book/tabletop) on the Fold;
- landscape acceptance on every device;
- 200% text and manual TalkBack spoken order on these four devices;
- human/stakeholder UAT;
- valid App Check traffic, App Check enforcement/rollback, or production
  Firestore rollout;
- Play Console acceptance of the exact AAB;
- production account-deletion infrastructure or research authority.

The connected Vivo remains the physical manual-test device. Human TalkBack
listening and owner/stakeholder judgments cannot be manufactured by an
automated crawler and remain separate evidence.
