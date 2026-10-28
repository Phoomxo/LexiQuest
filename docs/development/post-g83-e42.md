# E4.2 / F08 audio lessons

Accepted local implementation from E4.1 `0e8098fe1197cacfd65b4345108ca14ccbeb146b`, branch `lexiquest/post-g83-e42`. Exact accepted SHA is recorded in external `POST-G83-E42-accepted-handoff.json` to avoid a self-referential commit. Implementation and sequential succession remain authorized by the external V3 authorization.

Personal sets now offer **Word and example** and **Short scenario** scripts for the three admitted object senses. The immutable script/transcript pins require exact set, sense and lexical artifact revisions. Review is original source/AI-assisted engineering review, not independent human calibration. The page provides owned segment playback, pause/stop, explicit resume, replay, cache deletion, text-only fallback and return to existing set practice.

Shared `VoiceUseCases`/`VoiceSession` and the provider routing/cache boundary own media. Only exact provider completion advances an immutable exposure checkpoint. Schema **34** adds `audio_lesson_checkpoints` (**58** named tables, **48** direct-owner descriptors). Reopen/restart, replay, scoped backup/restore with rollout off, guest upgrade, redacted export and deletion preserve identity. Listening creates no canonical assessment, SRS, reward or research event.

The ephemeral owner-generation cache is **20 MiB / 10 lessons**, aggregate across routed providers, with deterministic whole-lesson LRU and explicit revocation. Request keys include exact segment/content, engine/model, voice/language/speed. Owner changes and runtime disposal clear memory. Local-only requests avoid new remote-provider spending; provider capability can still be unavailable.

| Objective and rationale | Tradeoff and worked example | Completion benchmark |
|---|---|---|
| Preserve the meaning of a saved lesson | Versioned scripts cost storage; editing a set does not rewrite prior transcript pins | Exact replay/restart, format collision and archive tests pass |
| Own asynchronous playback and cleanup | Segment resume is less precise than seek: interrupt segment 2 after segment 1, then explicitly replay segment 2 from its start | Late completion, A→B→A, failed-drain retry and runtime retirement cannot advance a false checkpoint |
| Keep learning evidence honest | Listening is exposure; text fallback remains usable but is not audio completion proof | No answer/SRS/reward/event rows from listening; practice starts through the existing authority |

Verification: **564 tests / 35 targeted files PASS** through `tool/cli/verify-scope.ps1`; all **1,432** input hashes and **37** changed source/test hashes revalidated. Fingerprint `ef5d4e4c8a303efd0f7509e77fe48a545381785d4dcb656b91869d1dfb93a1cb`. Static analysis: zero errors/warnings, six inherited bootstrap/application-test infos. Default-off and internal production composition exercised; owner, both feature switches, route and background retirement checked. Playback and separately labeled fallback exercised at 320px/200% text, including return to existing practice.

- [Acceptance and source pins](post-g83-e42/acceptance.json)
- [Script review](post-g83-e42/script-review.json)
- [Defects, recovery and self-review](post-g83-e42/defects-and-review.json)
- Raw red/green logs, screenshots and analysis: external `full-system-orchestration/evidence/E4.2/`.

No required local implementation defect remains. Local gateway and routed byte-producing/cache fixtures are not acoustic proof. `adb devices -l` listed no device. Generic untagged native completion remains fail-closed; no exact seek, word alignment, provider timing, independent human content review, native assistive or physical/live-provider acceptance is claimed. These remain explicit E6/E7 gates. No deployment, cost or research activation; no full release claim. Standard/default requested, effective runtime tier unverified. Single writer; no subagents.

Next authorized slice: **E5.1 / F07**, only after exact committed source, durable handoff and writer release. E6 freeze/review/fixes and every E7/G8.4–G8.9 criterion remain intact. Recovery means stop the failed method, diagnose, correct and retest; recoverable errors never authorize abandoning the task or bypassing acceptance.
