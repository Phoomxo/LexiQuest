# E2.1 / F01 — personal vocabulary sets

## Checkpoint C01 — crosswalk foundation (2026-09-20)

**E2.1 remains incomplete.** This checkpoint adds a versioned `SenseRef` and a strict `SenseCrosswalk` decoder/admission policy. It does not add a user-facing set feature or approve a production sense corpus.

- Exact corpus, word, sense revision and lexical artifact hashes remain distinct from historical word SRS identity. Draft crosswalks can resolve references but cannot admit scored activities.
- Scored admission checks reviewed crosswalk bytes, current approved/published packaged vocabulary, category availability, exact lexical manifest identity/hash and the existing strict lexical decoder. Ambiguous duplicate bindings, changed versions, retired content and forged verified wrappers fail closed.
- Local self-review found two gaps (duplicate semantic identity with different artifact hashes; checksum-valid malformed lexical JSON). New failing tests demonstrated both before fixes. No independent/subagent review.

Verification: **37 tests passed across four bounded targets**, including 13 new crosswalk cases; equal pre/post verifier fingerprint. Targeted Dart analysis reports no issues. Structured evidence: [C01 receipt](post-g83-e21/crosswalk-checkpoint.json). No full suite, build, device, live provider or release verification was run.

## Remaining E2.1 work

1. Wire a real, versioned crosswalk source and reviewed subset through existing content authority. The test fixture is synthetic, not production approval. Preserve original corpus pins; editorial AI-review does not confer scored admission. Bind saved revisions to the exact crosswalk artifact as well as sense refs; retain old crosswalk readers and reject changed mappings under an existing immutable identity.
2. Add owner-scoped immutable personal set revisions/members, expected-revision save, durable operation identity/payload collision checks, archive and exact revision reads. Recheck schema 28 before assigning the next migration.
3. Integrate owner lifecycle manifest/export/delete, transactional guest upgrade, coherent restore/idempotency and the complete migration matrix. Discover actual restore capabilities rather than assuming the export archive is restorable.
4. Connect real accessible list/edit/preview/activity UI through `lib/screens/learning_pack_catalog_screen.dart` and `lib/screens/study_planning_hub_screen.dart`. Existing planning presentation is under `lib/screens`, not a feature-local presentation directory.
5. Launch an admitted subset through canonical learning/session authority with pinned revisions and no direct SRS/reward/history mutations. Check owner changes at durable/async boundaries. Run fixture, lifecycle, restart, navigation and accessibility regressions and review before accepting E2.1.

Continue **E2.1**, not E2.2. All E6 integration and E7 G8.4–G8.9 obligations remain. Application implementation and one-at-a-time continuation are authorized by the external `post-g83-v3-implementation-authorization.json`, superseding historical analysis-only statements in E0/E1.
