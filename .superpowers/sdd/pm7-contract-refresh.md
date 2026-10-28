# PM7 contract refresh — current APIs, inspection only

Current binding overlay (2026-09-06): read pm7-integration-brief.md first after PM6 acceptance. The original inventory below predates PM6's actual host and remains historical API rationale. Final PM6 now supplies PairMatchingExperienceRuntime/Host and PairBoardDecoration. pm7-standard-entry-preflight.md confirms Standard does NOT call Adventure onStartMission; root authorizes the minimal optional contextualStandardActions factory in TodayExperienceHost to retain its exact captured snapshot/decision, with default callers unchanged. pm7-configured-withdrawal-preflight.md contains the final pending/committed/terminal disposition design. These focused updates supersede the older claims below that no Today source change is required or that PM6 APIs do not exist. No PM7 implementation/test acceptance is asserted by this overlay.

2026-09-05; worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`; branch
`codex/pair-matching-pm0-pm8`. This refresh reads the current PM5 handoff and
PM6 binding inventory. It does not treat PM6's not-yet-created board/host files
or signatures as real contracts. PM5 now owns purpose decoding and rejects
replay at collection, reconciliation, direct repository and upload boundaries;
PM7 must consume that result, not duplicate or broadly audit it.

## Existing binding points PM7 must use
- `TodayExperienceHost.onStartMission(AdventureMissionLaunchContext)` is the
  contextual launch seam (`today_experience_host.dart:28-40,42-77`). The exact
  context carries `mission`, the already-loaded `TodayHubSnapshot`, entry
  decision (including its entry attempt/permit decision) and reward ownership.
  `AdventureMissionSheet` only serializes the tap and invokes `onStart`
  (`adventure_mission_sheet.dart:22-39,62-72`). PM7 must derive the Pair launch
  from this captured snapshot once; it must not reload Today or open research.
- The existing Today research path is already complete at its boundary:
  permitted openings call `prepare` then `open` with the same
  `entryAttemptId` and selected presentation
  (`today_experience_host.dart:207-237`), presentation exposure is recorded by
  the host (`:779`), and lifecycle/database changes call `reconcile`
  (`:472-485,487-539`). The optional before/post form is selected from the real
  run (`:415-433`) and binds `record`, complete, skip and withdraw
  (`:749-776`). `MotivationMeasurementForm` owns only UI retry/state; its caller
  owns persistence/run lifecycle (`motivation_measurement_form.dart:8-31`).
- `MotivationMeasurementUseCases.reconcile(ownerId)` observes canonical
  accepted sessions; it does not start/finish Pair (`motivation_measurement_use_cases.dart:104-109`).
  It authenticates persisted purpose (`:173-184`), requires an accepted pinned
  `SessionConfiguration` (`:185-219`), then attaches/completes through the
  existing opportunity (`:223-230`). A normal Pair must therefore use PM6's
  configured internal registration before mount; presentation cannot fabricate
  configuration or retrofit it after acceptance.
- PM5's strict purpose reader exposes `allowsLearningAuthority`
  (`pair_matching_session_purpose.dart:9-29`). PM7 does not add a presentation
  boolean for research eligibility. Existing neutral event payloads and frozen
  EvidenceContext/EventEnvelopeV2 remain unchanged.
- The current coordinator is the sole command/evidence/timer/close authority:
  typed `dispatch` (`pair_matching_session_coordinator.dart:294-327`), exact
  retry (`:432-435`), durable `flush` (`:461-480`), pause/resume (`:516-539`),
  timeout decision (`:542-555`), terminal finish and three-receipt path
  (`:675-719`). Adventure chrome must never call the engine/evidence/reward or
  research writers itself.
- Existing Standard/Adventure Today switching uses
  `AdventureStandardSwitch` (`adventure_standard_switch.dart:5-44`) and changes
  the opportunity's effective presentation through the current host path.
  This entry switch is distinct from in-session renderer fallback.

## Minimal later source ownership
1. Create `lib/features/adventure/presentation/adventure_pair_renderer.dart`.
   It is a presentation adapter over PM6's same immutable board model, command
   callbacks and Standard board child. It may add only Playful Quest theme,
   companion/narrative chrome and return target. No composer, engine, timer,
   repair/star/reward/evidence/research authority belongs here.
2. No change is required in `today_experience_host.dart`, measurement use cases,
   repositories, sync authorizer, schema or frozen contracts for the normal
   linkage. Extend `test/features/adventure/presentation/today_experience_host_test.dart`
   to drive its real launch and optional measurement UI. Extend PM5 research
   tests only if a missing assertion is demonstrated after ownership transfer.
3. Create `test/features/adventure/adventure_pair_renderer_parity_test.dart` and
   `test/features/learning/pair_matching/pair_measurement_boundary_test.dart`.
   Reuse `test/support/motivation_research_fixture.dart` and
   `test/support/pair_purpose_fixture.dart`; do not create a second fake research
   authority.
4. The actual app callback that converts `AdventureMissionLaunchContext` into a
   PM6 accepted Pair host is not present yet. After PM6 lands, root must name
   that concrete composition file before PM7 edits it. Do not guess a runtime
   factory or change `choose_mode_screen.dart`/production navigation.

## Deferred PM6 API requirements (names/signatures intentionally unspecified)
- Supply one session-owning host instance with the same accepted start
  operation, plan, coordinator, checkpoint and shell lifecycle while its
  presentation changes between Standard and Adventure. PM7 must not reconstruct
  or restart the session on fallback.
- Expose the immutable board/ViewModel and identical typed command callbacks to
  both renderers, plus read-only operational status/timer availability from the
  coordinator. Rendering/querying must allocate no IDs, acquire no lease and
  write nothing; dispatch revalidates races.
- Expose a host-owned presentation replacement operation that preserves pending
  answer/append, accepted close, repair state, active timer, extension
  entitlement, operation identity and exact recovery. It must remain available
  inside the accepted-session lease after Adventure is disabled, while refusing
  new sessions when Pair or parent Quiz is disabled.
- Separate gates: Adventure-off selects Standard for the exact accepted Pair;
  Pair-off/Quiz-off prevents new v6 starts and uses PM6/PM8 reader-first
  resume/retire behavior. Never reinterpret Adventure-off as Pair-off.
- Provide a bounded decoration-failure contract. Catching a `WidgetBuilder`
  call only covers a synchronous throw while returning the child; Flutter builds
  descendants later, so that catch cannot recover an arbitrary late child-build
  exception. Support both (a) synchronous Adventure decoration construction
  failure and (b) an explicit typed late/async decoration-health callback owned
  by Adventure chrome/assets. Both request Standard replacement on the exact
  host. Do not install a global `FlutterError.onError`, swallow board/domain/
  persistence failures, or claim arbitrary descendant build recovery.
- Preserve PM6's accessibility hierarchy, focus, keyboard/semantic commands,
  feedback placement and result component. Companion decoration emits no
  answer, learning-time, reward or research fact. Diagnostics use only existing
  enum counters (`adventure_diagnostics.dart:16-99,101-200`), contain no raw
  lexical/owner/guardian/error text, and are replaced on owner/disposal.

## Real integration acceptance fixtures
### Normal configured Pair: before → accepted learning → after
- Use `MotivationResearchFixture` with its signed synthetic active permit and
  real `AdventureResearchRuntime`; mount `TodayExperienceHost`, answer the
  baseline form, enter the assigned presentation, and record Presented. Capture
  the exact `AdventureMissionLaunchContext`; use its existing Today snapshot to
  create one PM6 configured normal-learning Pair operation through the real
  policy/internal registration in EN→TH and TH→EN.
- Complete through the real PM6 host/coordinator, including a wrong→repair path,
  finish/close retry and one rebuild/restart reconciliation. Return to Today (or
  trigger its canonical observer), let `reconcile` attach/complete, then assert
  the post form appears within the existing 30-minute window
  (`today_experience_host.dart:425-431`). Submit it through real callbacks.
- Query the database: one opportunity keeps the original entry attempt and
  configured session identity; exactly one mission-start and one
  mission-complete event attach to that opportunity; repeated reconciliation
  adds neither denominator nor duplicate event; the run has baseline and post.
  Run this fixture for Standard and Adventure. Existing research parity precedent
  is `motivation_measurement_use_cases_test.dart:159-194`; upgrade it here from a
  seeded generic session to the real configured Pair host path.

### Nonparticipant zero research rows, ordinary Pair intact
- Mount Today with `research: null`, and separately with denied/expired/
  withdrawn synthetic authority. Launch and complete the same configured normal
  Pair through PM6. Assert canonical learning session/checkpoints/answers and
  result still exist, while `motivation_measurement_runs`,
  `motivation_responses`, `measurement_opportunities`, research event types and
  research outbox/upload requests remain zero. Do not assert the global outbox
  is zero because ordinary sync bookkeeping may exist. Use the real database and
  authorizer fixture; the existing denial baseline is
  `research_sync_authorizer_test.dart:1262-1287`.

### Standard/Adventure normalized parity and fallback
- Feed the same accepted plan and semantic input script to the two real PM6
  surfaces. Capture typed commands before dispatch and compare command class,
  payload, ordering, expected revision and identity relationships. Query durable
  attempts/roles, repair tickets, timer decisions, stars, evidence rows and
  terminal outcome. Normalize generated session/operation/evidence IDs and UTC
  values only; retain ordinals, ordering, checksum/revision, purpose/config pins
  and cross-row references. Cover 4/6 pairs, both directions, OFF/60/90/120,
  wrong→repair, guided confirmation, support and retry.
- Inject synchronous decoration failure and explicit late decoration-health
  failure, then Adventure-off, during pending evidence, timeout choice and close
  retry. Assert Standard replaces presentation on the same host/checkpoint,
  accepted operations finish once, reward/evidence counts do not duplicate, and
  Pair-off still denies a new start. A test that catches only a throwing builder
  is insufficient.

## Minimal later checks
```powershell
flutter test --no-pub test/features/adventure/adventure_pair_renderer_parity_test.dart --reporter expanded
flutter test --no-pub test/features/learning/pair_matching/pair_measurement_boundary_test.dart --reporter expanded
flutter test --no-pub test/features/adventure/presentation/today_experience_host_test.dart test/features/research/motivation_measurement_use_cases_test.dart test/features/research/measurement_opportunity_repository_test.dart test/features/research/research_sync_authorizer_test.dart --reporter expanded
```

No Flutter/Dart/test/build/scan command was run for this refresh. External
TalkBack/Switch Access/device UAT, production enrollment/upload and efficacy
evidence remain outside PM7 engineering proof.
# PM6-era provider clarification for PM7 acceptance

Root read actual providers on 2026-09-06 while PM6 runs: PersistedEvidencePolicyRolloutModeProvider in lib/features/research/application/assigned_learning_event_context_provider.dart resolves absent/invalid/withdrawn persisted assignment/consent to Legacy for a new capture. PersistedSessionConfigurationProtocolProvider in lib/features/learning/application/session_configuration_policy.dart then returns its real catalog.baseline for Legacy. Use this actual composition in ordinary/nonparticipant Pair UI tests; do not manufacture fake limits or drop a previously accepted configuration after a revalidation error. Current Pair host accepts an optional real protocol provider. Genuine configured research state must still match its exact catalog binding; setup/recovery error is not permission to silently rewrite accepted pins. This is read-only clarification, not a reported defect or test pass.

Follow-up preflight found a distinct confirmed gap for **previously accepted research-configured Pair after withdrawal**; read pm7-configured-withdrawal-preflight.md. Revalidation correctly rejects old research pins against the current baseline, but preaccepted attachment preservation leaves an active durable session that conflicts with a fresh ordinary start. PM7 must cover this actual sequence, not only fresh nonparticipant controls. A bounded explicit owner-validated disposition can use canonical abandonment with retained timestamp after safe exact pending reconciliation; a planned/unattached controller's abandonAtCutoff alone does not update the loaded persisted session. Preserve all consent/signature/configuration checks and accepted evidence; never force pending research through revoked authority or fabricate successful completion. Refresh final PM6 shell/host before naming minimal source deltas. This is a required PM7 integration follow-up, not permission to edit concurrently with PM6 or a completed test claim.
