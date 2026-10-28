# P6 Gemini BYOK Gate Record

> **Historical gate record.** Results below remain the accepted P6 automated
> evidence. Current live-provider acceptance status is reconciled in
> `docs/superpowers/specs/2026-07-31-p8-hybrid-voice-field-release-design.md`,
> section 3.1.

**Date:** 2026-07-30

**Result:** PASS

**Scope:** User-supplied Gemini key lifecycle, secure storage, REST transport,
consent, local learning context, AI Tutor, speech input, and Android packaging.

## Accepted behavior

- A participant can add, validate, replace, and remove a Gemini API key.
- A replacement is validated before the existing key is overwritten.
- The key is stored outside Drift and cloud data through
  `flutter_secure_storage` 10.3.1. Android uses an isolated namespace and an
  AES-GCM key held by Android Keystore; application backup remains disabled.
- The key field is permanently obscured. There is no reveal control that could
  expose plaintext in an Android recent-app task snapshot.
- The key is sent only in the `x-goog-api-key` request header. It is never put
  in a URL, request body, exception message, application log, analytics event,
  or learning record.
- Key validation uses the model metadata endpoint and does not spend an
  inference request.
- Tutor generation uses one candidate, a maximum of 120 output tokens, no
  automatic retry, and the cost-oriented `gemini-2.5-flash-lite` model.
- Connect and response work have a bounded timeout and a real HTTP abort
  trigger. User cancellation, offline/network failure, invalid key, quota,
  provider outage, blocked content, and malformed responses remain distinct.
- Typed or recognized speech is sent only after explicit provider consent.
- Learning context is omitted by default. Optional consent sends only bounded
  aggregates and at most three weakness words; it excludes owner IDs, email,
  raw answers, transcripts, and account data.
- Consent/key transitions are serialized with validation and generation.
  Revocation is queued before later requests, cancels active work, and prevents
  a request racing revocation from using the previous consent or key.
- Opening Gemini settings stops microphone recognition and TTS before the
  settings route covers AI Tutor.
- AI Tutor has no canned successful response, simulated microphone text, or
  fabricated grammar score. Provider failures remain explicit while local
  learning continues.
- Application shutdown cancels and awaits Gemini work before closing its HTTP
  client and local database.

## Defects resolved during review

The P6 review found and the implementation corrected:

1. consent/key revocation racing a newly started provider request;
2. speech recognition continuing behind the Gemini settings route;
3. a key reveal control exposing plaintext to task snapshots;
4. asynchronous settings completion touching a disposed text controller; and
5. a delayed provider reply restarting TTS behind the settings route.

The follow-up review found no remaining Critical or Important issue in the P6
diff.

## Bounded verification

Run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/verify-gemini-byok.ps1
```

Recorded result:

- P6 CLI, secret-storage, presentation, and no-log contracts: PASS
- Dart format, 15 scoped paths: PASS
- `flutter analyze`: PASS, no issues
- Focused Flutter suite: PASS, 37 tests
- Invalid-key, quota, offline, timeout, outage, malformed-response, cancellation,
  replacement, removal, revocation-race, consent, and lifecycle regressions:
  PASS
- Android debug APK build: PASS
- Exact APK model-runtime integrity: PASS
- `git diff --check`: PASS
- Follow-up read-only code review: PASS

Artifact:

- Path: `build/app/outputs/flutter-apk/app-debug.apk`
- Size: 239,641,272 bytes
- SHA-256:
  `7D4D19C3040D27A30519BBD1255F0C267F4CCF5BDBDCA8CCC28A4F14F960316A`

## Field-test boundary

No participant Gemini key is available on the development host. P8 retains the
real-service Android journey for key creation, validation, generation, quota,
offline, timeout, removal, process restart, and budget-cap evidence.

Secure storage protects a BYOK key at rest; it cannot make a key used by a
mobile client impossible to extract at runtime. This implementation is
therefore bounded to the controlled field prototype. A broadly distributed
production application should replace direct client-side Gemini authentication
with a controlled backend proxy and short-lived authorization.

References used to freeze the implementation:

- Google Gemini API key and client-side security guidance:
  <https://ai.google.dev/gemini-api/docs/api-key>
- Google Gemini REST text generation:
  <https://ai.google.dev/gemini-api/docs/text-generation>
- Google Gemini error and retry guidance:
  <https://ai.google.dev/gemini-api/docs/troubleshooting>
- Secure-storage Android cipher and backup guidance:
  <https://pub.dev/packages/flutter_secure_storage>

The debug APK proves implementation and packaging only. It is not the
participant release APK.
