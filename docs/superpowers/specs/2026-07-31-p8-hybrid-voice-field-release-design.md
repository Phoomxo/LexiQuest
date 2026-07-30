# LexiQuest P8 Hybrid Voice and Field Release Design

**Status:** DRAFT FOR OWNER REVIEW

**Date:** 2026-07-31

**Owner:** LexiQuest project owner

**Implementation:** Codex with local CLI; GLM is paused

**Target:** One release-signed Android APK suitable for a real, distributed
30-participant field trial

## สรุปสำหรับเจ้าของโครงการ

เอกสารนี้เป็นขอบเขตงานปัจจุบันเพียงฉบับเดียว งาน P0-P7 ถือว่าปิดเป็น
baseline แล้ว ส่วนที่ต้องพัฒนาต่อคือระบบเสียงแบบ Hybrid/VoxCPM และการรับรอง
APK ภาคสนาม P8

| ชุดงาน | ผลลัพธ์ที่ต้องได้ | สถานะเริ่มต้น |
|---|---|---|
| P8-A | สัญญากลางสำหรับ voice provider, policy, consent และ retention | รออนุมัติเอกสาร |
| P8-B | VoxCPM, audio pack, download/checksum และ Native TTS fallback | ยังไม่เริ่ม |
| P8-C | voice mirror ชั่วคราวต่อ session พร้อมลบข้อมูล | ยังไม่เริ่ม |
| P8-D | STT และคะแนน pronunciation จากหลักฐานจริง | ต้องเชื่อมกับ voice architecture ใหม่ |
| P8-E | ปิด journey ที่เหลือบน vivo V2041 | ผ่านแล้วบางส่วน |
| P8-F | ทดสอบมือถือ low/mid/high และ Cloud readiness | ขาดเครื่อง low/high และ App Check |
| P8-G | APK จริง เอกสารผู้เข้าร่วม owner smoke test และ rollout 3→10→30 คน | รอ P8-A ถึง P8-F |

หลักการทำงานคือทำทีละชุดตาม dependency ปิดด้วย focused test และรัน full
release gate เฉพาะ release candidate จึงไม่เกิด test loop ที่ดึงงานกลับไปมา
แต่ข้อผิดพลาดทุกข้อยังถูกบันทึกและ release blocker ต้องถูกแก้ครบก่อนแจก APK

GLM ถูกพักไว้และไม่อยู่ในเส้นทางพัฒนาปัจจุบัน

## 1. Document authority

This document is the only current scope and design reference for the work that
remains after P0-P7. It replaces the previous active execution plan dated
2026-07-30.

The accepted P0-P7 design and gate records remain historical evidence. They are
not reopened unless a P8 change causes a verified regression.

The implementation plan will be written only after the owner approves this
design. It will identify exact files, tests, CLI commands, checkpoints, and
commits for each work package.

## 2. Outcome

LexiQuest must be installable and usable by participants in different
provinces without requiring continuous connectivity or developer assistance.
Every enabled result must come from local evidence, a real device input, or a
real provider response.

The final release must provide:

- offline-first vocabulary, Quiz, SRS, reading, progress, and export;
- safe synchronization after connectivity returns;
- real camera, object inference, microphone, STT, TTS, and pronunciation
  journeys;
- optional VoxCPM target speech and session-only voice mirroring;
- Gemini BYOK without project-funded API usage;
- a verified signed APK, participant documents, and evidence from low-, mid-,
  and high-tier physical Android devices.

## 3. Accepted baseline

P0-P7 are accepted as the product baseline:

- Drift is the runtime source of truth.
- Firebase is reached through synchronization services, not screens.
- Vocabulary, learning evidence, SRS, reading, points, achievements, imports,
  outbox entries, conflicts, and exports use real persisted records.
- Guest ownership can migrate to an authenticated account.
- LiteRT model download, checksum verification, inference, and CPU-safe
  fallback are implemented.
- Camera, STT/TTS, pronunciation, Gemini BYOK, progress, rewards, typed
  navigation, Material 3, account flows, and field-release automation have
  bounded local verification.

The current signed field artifact is:

| Field | Value |
|---|---|
| APK | `lexiquest-1.0.0+9.apk` |
| Version | `1.0.0` (`versionCode 9`) |
| Source commit | `6a42c9ade57243315607cd2492ed698f18824e1f` |
| APK SHA-256 | `FB9C39C5159566C8007878F0D2FAFDF415B2453B3AF235600F199DDEE1452C5E` |
| Model SHA-256 | `D3949E8A3556C79739CB675E0BE7476503BCCE76938031C6A1048E13E0CB7D8B` |

This artifact is a baseline, not the final VoxCPM-enabled release candidate.
Any product-code change requires a newly signed APK, a new hash, and new
evidence for affected journeys.

## 4. Remaining scope

Work is divided into seven dependency-ordered packages:

1. P8-A — voice architecture contract;
2. P8-B — hybrid voice and VoxCPM;
3. P8-C — temporary participant voice mirror;
4. P8-D — real speech and pronunciation integration;
5. P8-E — complete the mid-tier device journeys;
6. P8-F — low/high device matrix and Cloud readiness;
7. P8-G — final field release and staged rollout.

Packages close in this order. A later package cannot be declared complete while
an earlier dependency is open.

## 5. Voice architecture

### 5.1 Boundary

Screens and learning features request speech capabilities from a single
application-facing `VoiceOrchestrator`. They do not import VoxCPM, Android TTS,
HTTP, storage, or provider-specific SDKs.

The orchestrator resolves an engine through:

1. requested capability;
2. participant consent;
3. offline/online state;
4. privacy and retention policy;
5. device capability;
6. provider health and quota;
7. Cloud/provider kill switches;
8. cost policy.

### 5.2 Provider registry

Providers implement a stable adapter contract and declare capabilities:

- `nativeTts`;
- `standardTargetSpeech`;
- `dynamicTargetSpeech`;
- `sessionVoiceMirror`;
- `speechToText`;
- `pronunciationEvidence`.

Initial providers are:

- Android Native TTS — offline-safe fallback;
- VoxCPM standard voice — pre-generated target speech and optional dynamic
  target speech;
- VoxCPM session voice mirror — consented and temporary;
- the existing STT adapter — transcript evidence;
- the existing pronunciation adapter — only measurements supported by the
  selected engine.

VoxCPM is an adapter, not a core dependency. A future provider can replace it
without changing learning screens or persisted learning evidence.

### 5.3 Deployment

The full VoxCPM model is not bundled in the Android APK.

Standard vocabulary and lesson speech is generated before release and shipped
or downloaded as versioned audio packs. Dynamic AI Tutor speech and temporary
voice mirroring use the existing `backend/voice_api` boundary when enabled.

This produces three operating modes:

| Mode | Primary source | Fallback |
|---|---|---|
| Offline lesson | verified audio pack | Android Native TTS |
| Online dynamic text | VoxCPM API with bounded cache | Android Native TTS |
| Session voice mirror | transient VoxCPM worker | standard target voice |

Local learning remains usable if every remote voice service is disabled.

## 6. Standard audio packs

Each pack has a signed or trusted manifest containing:

- pack ID and semantic version;
- locale and voice ID;
- engine/model version and license reference;
- minimum app version;
- total byte size;
- per-file byte size and SHA-256;
- content ID and normalized text hash;
- generation timestamp.

Downloads use partial files, HTTP range resume, bounded retry, cancellation,
free-space checks, streaming checksum verification, and atomic activation.
Incomplete or corrupt bytes never become active.

Audio pack files may be cached across sessions because they contain only
standard voices and approved learning text. They are not participant data.

## 7. Dynamic VoxCPM speech

Dynamic speech is limited to approved AI Tutor target text. Requests use
normalized text, locale, standard voice ID, model version, and a non-identifying
request ID.

The app must:

- reject unbounded input length;
- avoid direct personal identifiers;
- use a bounded timeout and cancellation;
- apply provider quota and a provider-specific kill switch;
- cache only standard-voice results;
- fall back to Native TTS without blocking the lesson.

No API key, authorization header, raw prompt, email, participant name, or
unredacted provider response may enter logs, Drift, Firebase, analytics, crash
messages, or exported research data.

## 8. Temporary participant voice mirror

### 8.1 Purpose

The feature generates an AI-synthesized example of the target phrase in a
voice resembling the participant. It is a learning guide, not proof that the
participant pronounced the phrase correctly.

The UI must label the result as AI-generated target speech and keep it separate
from actual transcript and pronunciation scores.

### 8.2 Consent

Voice-mirror consent is separate from research consent, microphone permission,
account consent, and Gemini BYOK consent.

Declining or withdrawing voice-mirror consent:

- deletes the active voice session;
- disables new mirror requests;
- preserves standard target speech and all offline learning;
- does not remove ordinary learning history.

### 8.3 Session lifetime

A voice-mirror session ends at the earliest of:

- 20 minutes after creation;
- leaving the voice-mirror activity;
- logout or account change;
- explicit end-session action;
- an ordinary app close that can send the end-session signal;
- more than 5 continuous minutes in the background.

Android cannot guarantee a final callback after a crash, force-stop, power
loss, or network loss. The server therefore uses a five-minute renewable lease
in addition to explicit deletion. If the app disappears without sending the
end-session signal, the server makes the session unusable and deletes its
temporary state no later than five minutes after the last valid heartbeat. The
next app startup deletes any remaining client files and stale session
references.

The client and server both enforce expiry. A client clock or missing callback
cannot extend server retention beyond the lease or the absolute 20-minute
limit.

### 8.4 Temporary data

The following data is temporary:

- raw enrollment audio;
- decoded audio buffers;
- voice embedding or clone state;
- generated mirror audio;
- participant-voice cache;
- request work files.

Temporary data is held in memory where practical. Required files use a
dedicated temporary directory, per-session encryption, an encryption key held
only in worker memory, and an expiry marker. They are never stored in Firebase,
research exports, backups, analytics, or general media storage.

Cleanup is staged by data type:

- enrollment audio is deleted immediately after the temporary voice state is
  created or the enrollment attempt fails;
- request work files are deleted after each completed or failed request;
- generated mirror audio is deleted after playback completes, playback is
  cancelled, or the session ends;
- the voice embedding/clone state is deleted when the session ends;
- when the app enters startup recovery;
- expired state is deleted when a backend worker starts and through a bounded
  server expiry sweep.

Cleanup is idempotent. A missing file is success; a failed deletion is recorded
without path, content, or participant identifiers and retried only through the
bounded cleanup policy.

### 8.5 Feature restrictions

Session voice mirror does not support:

- download or share;
- arbitrary free-text synthesis;
- permanent voice profiles;
- cross-device restoration;
- use by another account;
- research export of audio or voiceprints.

Safe operational metrics may record only capability availability, broad error
category, elapsed time, model version, and whether cleanup completed. They
cannot reconstruct a voice or identify a participant.

## 9. Speech and pronunciation evidence

STT and pronunciation remain separate from VoxCPM.

The pronunciation result may contain:

- target content ID;
- recognized transcript;
- locale;
- engine/model and algorithm versions;
- timestamp and duration;
- word/phoneme measurements actually returned by the engine;
- supported aggregate score;
- evidence sample size and unavailable reasons.

It must not invent pitch, phoneme, confidence, or accuracy values. Silence,
permission denial, cancellation, unavailable locale, and provider failure
produce typed unavailable/error states, not a zero or random score.

Raw microphone audio is deleted after processing unless a separately approved
protocol is introduced in the future. The current field trial does not retain
raw voice.

## 10. Failure handling

Voice failures use stable categories:

- permission denied or permanently denied;
- offline;
- provider disabled;
- quota/rate limit;
- timeout;
- cancellation;
- provider outage;
- invalid or corrupt audio;
- unsupported locale/capability;
- insufficient storage;
- checksum mismatch;
- session expired;
- consent missing or withdrawn;
- cleanup incomplete;
- internal error.

Every category defines:

- participant-safe Thai copy;
- whether retry is allowed;
- maximum retry count;
- fallback behavior;
- privacy-safe diagnostic fields.

No automatic path retries indefinitely. The same request is not repeated
without a state change or bounded backoff. Local learning never waits for
remote voice recovery.

## 11. Cost policy

Development and automated tests use local fixtures, fake transports, Firebase
emulators, and the local voice API boundary.

Cost controls are:

- pre-generate reusable standard audio once;
- do not ship the multi-gigabyte VoxCPM model in the APK;
- enable dynamic generation only when required;
- deduplicate standard speech by normalized text hash;
- cap text length, request concurrency, retry count, and per-session use;
- default to Native TTS when Cloud/provider work is unavailable;
- keep GPU optional and measured, never assumed;
- require an explicit field-acceptance reason for paid provider calls.

The temporary voice-mirror cache is never reused across sessions even if reuse
would reduce cost; privacy takes priority over cache savings.

## 12. Work packages and exit criteria

### P8-A — Voice architecture contract

Deliver:

- orchestrator, provider, capability, policy, and error contracts;
- retention and consent contracts;
- persistence boundary and logging rules;
- exact test matrix.

Exit:

- no screen or learning use case depends directly on VoxCPM;
- standard, dynamic, mirror, STT, and pronunciation capabilities are distinct;
- all data lifetimes are explicit.

### P8-B — Hybrid voice and VoxCPM

Deliver:

- VoxCPM adapter behind `backend/voice_api`;
- standard audio-pack builder and manifest;
- resumable verified pack download;
- dynamic standard-voice endpoint;
- Native TTS fallback and provider kill switch.

Exit:

- offline and provider-down journeys continue;
- checksum corruption is rejected;
- cache and quota behavior is deterministic;
- no secret or personal text is logged.

### P8-C — Temporary voice mirror

Deliver:

- separate consent journey;
- session manager on client and server;
- enrollment, synthesis, expiry, and cleanup;
- startup/crash recovery cleanup;
- restrictions on sharing, export, and free text.

Exit:

- raw audio, embedding, generated audio, and temporary files are absent after
  every expiry path;
- another session/account cannot access the result;
- withdrawal immediately stops use and initiates deletion.

### P8-D — Real speech and pronunciation

Deliver:

- real microphone/STT evidence path;
- supported pronunciation measurements and provenance;
- Shadowing and Weakness SRS integration;
- removal of any remaining synthetic scores.

Exit:

- no audio input produces no score;
- real results persist through the local repository and outbox;
- unsupported measurements display as unavailable.

### P8-E — Mid-tier completion

Use the existing physical vivo V2041 evidence record. Complete:

- consent and Guest startup;
- learning core;
- account lifecycle;
- real speech/TTS/pronunciation and voice mirror;
- Gemini BYOK;
- reboot/foreground/background;
- exact Cloud kill-switch journey;
- data export.

The existing 30.44-minute endurance result is retained only if profiling shows
the voice changes do not materially alter sustained resource use. Otherwise,
rerun endurance for the new APK.

Exit:

- every mandatory mid-tier journey references genuine evidence for the exact
  signed APK;
- no crash, ANR, data loss, or unbounded retry occurs.

### P8-F — Device matrix and Cloud readiness

Complete the same mandatory matrix on:

- one low-tier physical Android device;
- the accepted mid-tier device;
- one high-tier physical Android device.

Verify CPU/XNNPACK, GPU only where allowlisted, camera, microphone, STT/TTS,
voice, Gemini, install/upgrade/reboot, background sync, RAM, battery, and
temperature.

Cloud readiness includes:

- Firebase Auth and Firestore policy/emulator gates;
- valid Play Integrity/App Check production traffic before enforcement;
- Cloud kill switch with uninterrupted offline learning;
- zero-billing boundary or documented alerts at 50%, 80%, and 100%;
- private support and research-protocol references.

Exit:

- all mandatory journeys pass on three tiers;
- App Check is enforced only after a valid production token is observed;
- GPU is enabled only for an exact tested allowlist.

### P8-G — Field release

Deliver:

- release-signed APK;
- APK, certificate, source, and model hashes;
- installation/update guide;
- privacy and versioned consent documents;
- data export/deletion guide;
- support/feedback channel;
- known limitations and recovery steps;
- owner smoke-test record.

Rollout:

1. owner smoke test;
2. three-participant pilot;
3. one bounded evidence/crash/data review;
4. expansion to ten participants;
5. expansion to thirty participants.

Exit:

- the final gate passes for the distributed APK hash;
- the owner explicitly approves distribution;
- no unresolved release blocker remains.

## 13. Verification without test loops

Each package has one bounded cycle:

1. inspect the affected baseline;
2. write focused failing contracts;
3. implement the complete package slice;
4. run focused unit/integration tests;
5. correct failures attributable to the package;
6. run one package regression gate;
7. review and lock the package.

The full release suite runs only for a release candidate and after a
release-blocking correction that changes the APK.

Failures are classified as:

- current-package defect;
- verified regression;
- pre-existing unrelated defect;
- environment/external dependency.

No defect is hidden, ignored, converted into a fake success, or removed from
the release record. Unrelated lower-priority defects do not interrupt the
current package, but every release blocker must close before P8-G.

Priority is:

1. data loss, ownership crossover, consent, voice retention, or secret leak;
2. crash, startup, migration, or unusable offline journey;
3. sync duplication/conflict failure;
4. incorrect learning/pronunciation/research evidence;
5. provider/device journey failure;
6. accessibility or field-usage blocker;
7. cosmetic defect.

A retry loop, repeated filesystem error, or ten minutes without measurable
progress stops the current operation and produces a blocker report.

## 14. Current evidence and open dependencies

The mid-tier vivo V2041 currently passes:

- offline vocabulary persistence;
- offline force-stop/cold-start/online synchronization;
- real LiteRT model lifecycle;
- real camera inference;
- clean install and version 8 to 9 upgrade;
- CPU/XNNPACK benchmark;
- 30.44-minute endurance without crash or ANR.

CPU median latency was 33.7 ms and XNNPACK median latency was 43.2 ms in the
recorded comparison. Production therefore prefers CPU on this exact device.
GPU remains not allowlisted.

Still required:

- the remaining mid-tier journeys listed in P8-E;
- one low-tier and one high-tier physical device;
- valid Gemini owner acceptance;
- Play Console/Firebase linkage that produces a valid App Check token;
- private support and approved research-protocol references;
- owner smoke approval.

The earlier App Check enforcement attempt returned an invalid/unknown token and
was rolled back to unenforced. This is an open production-control dependency,
not a passed result.

## 15. Definition of field-test ready

LexiQuest is ready for the 30-participant trial only when:

- all enabled journeys work with intermittent or absent connectivity;
- local data survives process death, restart, upgrade, and Guest conversion;
- synchronization is idempotent and conflict behavior is verified;
- voice outputs and scores originate from real providers or evidence;
- temporary voice data is deleted under every session termination path;
- unsupported functionality has an honest unavailable state;
- the three-tier physical-device matrix passes;
- the signed APK, evidence manifest, and participant documents reconcile;
- the owner approves the exact APK hash for distribution.

Until these conditions pass, the project may be a valid development or pilot
candidate but is not described as field-test ready.
