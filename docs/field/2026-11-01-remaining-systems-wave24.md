# Wave24: completion program in progress

User instruction: implement every remaining audited LexiQuest feature, including
the commercial billing gap. The program is active, not complete. Worktree is
`C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest`, branch
`codex/remaining-system-readiness`, baseline HEAD `7c2a02393bb4fd600f2968c5996ce8cdf7773c2f`.
Source changes are currently uncommitted. Preserve the two pre-existing critique
notes and `test/screens/failures/`. No live deployment, purchase, enrollment or
Research upload was performed.

The active task graph is in the opening section of
`docs/superpowers/plans/2026-10-30-remaining-feature-sequence.md`. The frozen8/44
catalog is unchanged. Its published16 Connected/18 Partial/10 Missing matrix is
not promoted from focused tests alone.

## Implemented units and current evidence

| Unit | Current implementation | Observed checks |
| --- | --- | --- |
| R1 controlled Study archive | One-cycle issued archive, two current instrument export receipts, current owner/consent/participation, canonical index and Assessment linkage, privacy allowlist, detached bytes and picker/staging revalidation. Optional bootstrap factory and actual Export Center/Study archive screen. | `study-archive-focused.log`22PASS before hardening. `wave24-archive-profile.log`48PASS covers the expanded archive plus profile owner lifecycle and screen ports. Actual SQLite-to-screen-to-archive bytes test separately1PASS. |
| P1 learning profile | One owner-keyed profile for optional onboarding, editable goal/civil date/countdown/minutes/interests. Exact immutable retry/CAS, owner ABA/fence, Profile/Settings/Today entries independent of Progress success. | `profile-ui-focused.log`19PASS, including actual SQLite editor/save/close/reopen and320px/200-percent/IME Light/Dark. Owner merge target-wins/source-only and personal export2PASS, then full touched lifecycle in the48PASS bracket. |
| Schema22 | One additive learning_profiles table, inventory41. Genuine v21 capture has40tables/67syntheticrows and retains all old facts. Export/purge inventory and merge rule included. | `tool/capture_schema_v21_test.dart`1PASS before reservation. Genuine populated21-to22 migration/reopen1PASS. Old migration tests now assert current22/41 while preserving historical fixtures. |
| A1 calendar | Month/seven-day ordinary answer/correct/session projections and independent validated recorded-time totals. End-observation UTC range extends the existing time authority. Actual Mastery entry uses captured owner. | `calendar-focused-final.log`41PASS. More than50sessions, all-table pure reads, Study/Assessment exclusion, real midnight/reversed-UTC duration, unavailable-time UI, owner/lifecycle and real-font320px/200-percent/IME Light/Dark. Actual Mastery/SQLite caller passes in `profile-calendar-callers-fixed.log`11PASS. |
| B1 backend | Real Play subscriptions v2 verification/ack recovery, owner-bound fingerprint, Firestore refresh CAS/quota/uncertain-operation states, registered Firebase identity, actual HTTP routes/provider gate, authenticated RTDN and owner export/purge. Default-off. | Current AI backend273PASS after transactional per-owner verification budget. Independent earlier58focusedPASS. Four actual Firestore emulator cases deny client access to all server billing namespaces. No live Play/Firestore billing transaction tested. |
| B1 Flutter | Actual SDK allowlisted plan/offer selection, HTTP boundary, registered-owner binding, purchase/restore screen, optional bootstrap factory and Settings caller. Pinned in_app_purchase3.3.1 and in_app_purchase_android0.5.5 add four packages without existing upgrades. | `billing-flutter-bounded.log`48PASS including four independent native-effect/scope canaries. Bootstrap enabled/dispose and default-off cases separately2PASS. No real native purchase or store UAT. |
| B1 managed content | Existing managed Sentence Scramble/Cloze HTTP path sends immutable operation identity, preserves it on auth/manual retry, closes redirects and rechecks owner/caller around token/network awaits. Typed quota/payment/uncertain failures reach actual mode entry UI. | `wave24-content-boundaries.log`104PASS combines49managed-content cases and55pack-codec cases. Old native/runtime/UI regression and full integration remain pending. |
| C1 pack codec | Bounded immutable package, canonical payload and whole-file digests, provenance, rich lexical/contrastive data and validated embedded PNG/JPEG. No storage, catalog or installation yet. | Current codec55PASS, including semantic duplicate-key rejection with legitimate Unicode escapes, UTF16 canonical word limits and bounded media/depth/size. |

Evidence root is `D:/LexiQuest-Storage/maintenance/2026-11-01/`. These are overlapping
focused brackets, not additive totals and not a full current-source acceptance.

Integration checkpoint at04:05UTC: analysis0 issues; actual old native/runtime/
Settings/Profile/Export/ChooseMode plus new billing/pack/caller bracket325PASS.
Offline backend477PASS/one existing real-service opt-in skip, all98backend files
unchanged before/after. CLI23suites executed: initial22PASS/one typed-navigation
failure, then the product-completion suite passes after all four callers migrate
to existing AppNavigator. Full Flutter is active against1137frozen inputs,
including831Dart files. It has exposed stale schema expectations and fixture
filters, which are being diagnosed without weakening migration or authority
assertions. This checkpoint does not yet have a passing full run or current APK.

The completed first full run is4886PASS/26FAIL in11m44s, exit1, with all1137inputs
unchanged. All26failures were inspected latest-schema/table expectations. The
surgical correction retains historical pins, old-row/DDL equality and the profile
table in unchanged-data proofs. Corrected migration/identity/time/review cases plus
profile/caller tests194PASS; analysis0 after that correction. Independent review
then proved profile hydration/reload defects: two valid RED cases became GREEN,
and a third failed-reload case retains its original uncertain save command after
the two premature reset statements are removed. Final profile/caller bracket14PASS.
The initial invalid lifecycle fixture and all negative logs are retained.

The whole44-feature program continues in Wave25. Full re-attestation, current APK
and catalog promotion remain pending; no Wave24 green full-suite claim is made.

## Review dispositions and recoveries

- Historical Study pins originally failed after schema migration. The measurement
  repository now offers an explicit SELECT-only archive inspection for enumerated
  compatible schemas while collection inspection remains exact-current. Returned
  metadata preserves the stored schema pin. Genuine v21-DDL baseline subset with
  original schema19 pins exports without changing rows. Unknown/future schema and
  current-collection rejection are covered in the expanded archive tests.
- The first historical fixture was legitimately fenced and contained unrelated
  pending/storage-only facts. Its cache rejection was not counted as the intended
  RED. The corrected historical fixture reaches the archive read before the fix.
- Initial index evidence review was accepted. Canonical accepted-quiz/index readers
  plus existing attempt validation now reject corrupt index time/mission facts.
- An abandoned Assessment class/duration review claim was rejected after reading
  the existing AssessmentOutcomeEvidence factory. Its strict shape/time guards
  already run for every state. Regression now proves valid abandoned facts remain
  exportable and corrupted class/duration fails, without another validator.
- Calendar fixture initially loaded a genuine synthetic deletion fence. Runtime
  correctly refused it. The test now proves that rejection before clearing only
  the in-memory synthetic fence to exercise ordinary calendar filtering.
- Compile/import/form-layout failures remain in tool output and earlier logs.
  They were corrected locally; no assertions or authority checks were removed.
- First generation overlapped unrelated new Dart files. Writers were paused and
  generation repeated successfully with3196skipped inputs and no further outputs.
- Actual dependency replacement canary proved an open profile editor could save
  into its retired runtime. It now retires permanently on scope replacement;
  actual caller plus prior editor tests11PASS after the observed RED.
- Independent billing canaries proved synchronous observer invalidation could
  still reach native buy/restore/complete and an old subscription route could
  launch a purchase. Captured account/caller checks now run immediately before
  every external effect; four canaries pass after RED.
- Two earlier billing widget brackets stalled in fixture pumping after40/44
  passing cases. Only verified task-owned test processes were stopped. Bounded
  state predicates and pumping the actual disposal Future corrected the fixture;
  the complete48-case billing folder subsequently exits0. Negative logs remain.
- Compact raw-JSON comparison rejected valid escaped packages. A bounded
  semantic key scan now rejects duplicate decoded keys before jsonDecode while
  accepting ordinary Unicode escapes. All media and size guards remain.

## Remaining integration and program work

The focused review findings and actual optional archive/bootstrap, billing and
profile/calendar callers above are implemented. All writers are paused for
current-source analysis, touched regressions, full Flutter/policy/backend/CLI/build
at the integration checkpoint. No focused bracket alone establishes completion.
Do not reuse Wave23 full4717/APK evidence for the changed source.

Remaining program cards include packs/content, shared lesson/native resume and
configuration, explanations/hints/Definition Quiz, Quest periods/recovery/rewards
and one streak authority, companion/share, report transport and reminders,
Research authority/upload, Today aggregation and accessibility closure. Matching
follows the approved Research engineering prerequisite. External merchant/product
configuration, trusted Research artifacts, physical-device/store UAT and explicit
rollout remain distinct from local implementation. No historical evidence is an
approval to collect real data or money.
