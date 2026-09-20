# E4.1 / F05 — speaking scenarios

Accepted local implementation from E3.3 `ddfc7ea18bb696591eff792f67463803c2ba44af`, branch `lexiquest/post-g83-e41`. Exact final commit is recorded in external `POST-G83-E41-accepted-handoff.json`. One writer, no subagents; authorized Engineering Spec V3 implementation and succession.

Personal sets now open three pinned object scenarios with explicit practice/assessment intent, owned microphone recognition, repeat/cancel/timeout handling, transcript confirmation, a visibly separate text fallback, and six bounded supplemental result revisions. Unconfirmed/partial/empty recognition receives no lexical penalty. Meaning/use/grammar describe the displayed sentence only; capitalization/punctuation do not reduce spoken feedback. No canonical correctness, SRS, rewards, pronunciation or general proficiency score is inferred.

Schema **33 / 57 named tables** adds immutable owner-local `speaking_practice_results`. Exact-operation retries, intent/content pins, restart, owner A–B–A, late-write rollback, guest transfer, redacted export, deletion and scoped restore are covered. Restore requires exact personal-set revisions first. Archive readers remain available with rollout off. Production defaults off; internal production composition and real set navigation are exercised.

| Stage / objective | Reason and tradeoff | Worked example / completion benchmark |
|---|---|---|
| Pin scenario and policy | Finite authored scope is reviewable; arbitrary valid responses stay uncertain | Three scenarios, 15 assessed oracle patterns and eight uncertain examples |
| Own recording | Cancellation must drain the captured handle and fence owner and attempt | Late owner-A results and permission completion after takeover cannot restore A's transcript |
| Preserve evidence meaning | Typed text and confirmed/uncertain ASR are different evidence | “i read a book” earns lexical dimensions without punctuation; unconfirmed “I drink a book” is unscored |
| Store and replay | Immutable revisions preserve interpretation | Lost ACK reuses the same operation; six turns, restart and restore retain exact pins |
| Verify composition | Local fixtures exercise code; devices establish native/acoustic behavior | 506 tests / 35 files pass; spoken and fallback journeys render at 320px/text200 |

[Acceptance](post-g83-e41/acceptance.json) · [Defects and review](post-g83-e41/defects-and-review.json) · [Rubric scope](post-g83-e41/rubric-review.json). Static analysis: zero errors/warnings, two inherited bootstrap infos. Test fingerprints are equal before/after; the recorded input closure was revalidated. Raw red/green logs and visual renders are retained under external `evidence/E4.1`.

Limits: source/AI-assisted review only; no independent human calibration. No Android device is attached. Physical microphone/acoustic, live-provider, native assistive, release and deployment evidence is not claimed. Runtime tier is unverified; Standard/default requested. E6 review/freeze and all E7/G8.4–G8.9 gates remain required. No unresolved required implementation defect is transferred. Next authorized slice: E4.2/F08.

Recovery remains mandatory: stop a failed method, discover actual paths, diagnose, correct and retest. Repeated engineering failures never alone justify stopping or releasing the writer as blocked. No weakened assertions, skipped defects or fabricated PASS.
