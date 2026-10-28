# Root integration inspection

All paths relative to this worktree only. These are source findings, not acceptance claims.

- Existing atomic start: LearningUseCases.startCheckpointedQuiz accepts exact PinnedQuizContent and an initialState callback. ExactPinnedLearningActivityRepository.startExactPinnedSessionWithCheckpoint revalidates uniquely active owner, nondeleted lexical revision/checksum and active-session conflict inside Drift transaction. It does not currently check contentQualityReports or a Pair delivery gate. The use-case allocates a fresh ID each call; Pair launch lost-ack needs frozen/recoverable operation identity rather than blindly calling it again.
- Existing matching checkpoint writes schemaVersion 5. MatchingModeAdapter reads 1–5. Repository checkpoint ceiling is 64 revisions and 64 KiB. Next Pair version candidate is 6 (recheck before reservation). Reader/writer rollout is independent of database schema v24.
- Review provenance: ReviewQueueItem.snapshot + provenance includes dueSrs, incorrectAnswer, reported, saved. TodayHubSnapshot.reviewWork owns those snapshots and optional recommendation. Preserve the supplied Today object; do not reload Today. Learn can merge canonical inputs. Reported lexical content must not become filler.
- Canonical Review derives needs from answerAttempts and existing projections; Pair must not write srs_states directly. A wrong repair must stay finite.
- SessionConfigurations is already an owner-scoped table keyed owner/mode storing bounded versioned stableSerialization. Its SessionConfiguration codec currently has exact keys, including itemCount but no Pair density provenance. LearnerPreferences has no Pair density column. Prefer a compatible extension of existing session configuration authority if persistence is necessary; no new table/schema migration or research-derived guardian policy.
- MatchingModeScreen remains the legacy wrapper and rollback target until internal Pair interfaces/gates pass. Legacy default is 120-second wall clock; new Pair default-off timer must be separate and must not silently rewrite accepted legacy state.
- Existing pub-get native registrant modifications are Git stat/line-ending noise (empty content diff). Preserve/exclude; do not reset another worktree.

Global constraints: 8/44; f10/LessonMode.matching/learning/matching; no f45/menu/star currency; EvidenceContext/EventEnvelopeV2 frozen; schema v24/48 tables; research off; no production activation or fabricated device/UAT/signatures. User authorized full implementation and bounded subagents, no repeat design approval.
