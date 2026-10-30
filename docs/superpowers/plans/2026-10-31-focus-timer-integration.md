# Focus Timer integration plan

Status: Completed local transient timer/P06 engineering slice at71a230a42ac767c956c0192eed6af01ee2521a59 under the user's continuing request. Actual current-source/full/build and independent artifact/source/log gates are accepted. f23 is Partial because typed dependency f24 remains Missing. No additional user approval gate is needed.

Predecessor: Wave21 sourcea54ac2e2 passed Flutter4461/analysis0/CLI23/offline390+one optional skip/normalAPK and independent source/artifact reviews; metadata863b6f4b is pushed. The immediate P3 Ghost fixture cleanup is committed as6cb74422741ff341fd67ce2856c572f2cc5e16fd and passes all24 cases in8s. Its log SHA is 6ace23126f3688107d3d59d435e931c6130769f960a4c648a7df11c04a026dea. Current Focus inputs below remain unchanged; Ghost only replaces duplicate closes with one memoized Future. Root starts Focus on this exact worktree and preserves existing untracked critiques/feedback images.

Grounding: focus-time-grounding.md SHA256 fdaad6ff048de6b64de65cf086700748bbef64a69f7732d885af2239265987a3. Current worktree C:/Users/Phet/.codex/worktrees/cycle12-release/LexiQuest, branch codex/remaining-system-readiness, observed HEAD a54ac2e2e1b569a3656cc3300e094f1391c45203 at 2026-10-30T17:14:08.350806+00:00. Earlier inspection began at c650a4f197646cae852c9bdd313aa1f89baa07dc while Root continued Wave21; the hashes below bind the inputs used for this draft. No new verification result is inferred from those commits.

## Outcome and authority

Deliver one optional P06 Focus Timer tool with configuration, start, pause, explicit resume, stop and finish. It owns a transient interval only. It creates no learning/session/attempt/reward/research/time-capture record, and does not alter any existing canonical learning API.

Keep f23 Partial at the completed card checkpoint. The typed catalog and its architecture test explicitly pin f23 to f24. f24 remains missing until its separate active-effort writer, idle/background policy and P23/P24 recorded-time readback are implemented and verified. A countdown, foreground interval or answer latency cannot satisfy f24 or prove learning efficacy.

No catalog/runtime-feature row is added or remapped. Neither f23 nor f24 currently has a runtimeFeatures mapping; studyPlanning belongs to other contract IDs. This card does not enable studyPlanning/research flags or treat that metadata as a timer store. The new optional normal-learning entry is bounded by the existing current-owner navigation scope.

No schema/dependencies/secure storage/shared preferences/preset persistence/OS alarm/notification/background service is added. Schema stays20/37; v21 remains unreserved. App exit and a fresh process produce a fresh default interval, never reconstructed elapsed credit. Research remains optional and real enrollment/upload default-off.

## Fixed six-file source/test write set

| Path | Purpose |
| --- | --- |
| New lib/features/focus/application/focus_timer.dart | Plain-Dart controller, immutable snapshot, explicit states, monotonic accounting and validation. Types and arithmetic stay together. |
| New lib/screens/focus_timer_screen.dart | Owner-bound tool, controls/copy, route/lifecycle pause, input/keyboard/accessibility, redraw ticker and disposal. |
| Existing lib/screens/choose_mode_screen.dart | Append one tools entry and extract the narrow shared independent-tool open path used by Review Center and Focus Timer. Preserve existing canonical/native paths. |
| New test/features/focus/focus_timer_test.dart | Deterministic fake-clock state/arithmetic/validation/idempotence tests. |
| New test/screens/focus_timer_screen_test.dart | Public-control, owner/lifecycle/route, layout/semantics and real all-table no-write tests using existing harnesses. |
| Existing test/screens/choose_mode_screen_test.dart | Real P06 entry, same stream/owner, independent failed-projection entry, stale entry/return coverage and existing assertions. |

No ProgressHostBinding, AppDependencies, AppNavigator, canonical writer, Score, Mastery, schema, policy, catalog or dependency edit belongs to this card. Reuse the existing harness rather than adding another test support file. Plan/checkpoint metadata, if later promoted by Root, is separate from this six-file application/test set.

Append the tool after the existing Choose activities rather than reordering current cards. Keep existing visible recommendations, Review Center and native activity navigation behavior. Do not silently update or weaken existing goldens; an actual mismatch must be reviewed against the intended placement before any write-set extension.

## Plain-Dart API sketch

The values below are implementation choices for this card, not claims of research validation. Whole-minute input is bounded1..180, default25. A 25-minute starting value is familiar and quickly editable; a three-hour maximum prevents accidental enormous intervals and keeps input/arithmetic bounded. No preset store is needed.

```dart
typedef FocusMonotonicMicros = int Function();

enum FocusTimerState { configured, running, paused, stopped, finished }
enum FocusFinishReason { elapsed, manual }

final class FocusTimerSnapshot {
  // Constructed only inside this file.
  final int minutes;
  final FocusTimerState state;
  final Duration elapsed;
  final Duration remaining;
  final FocusFinishReason? finishReason;
  final int revision;
}

final class FocusTimer {
  static const minimumMinutes = 1;
  static const maximumMinutes = 180;
  static const defaultMinutes = 25;

  FocusTimer({
    required FocusMonotonicMicros monotonicMicros,
    int minutes = defaultMinutes,
  });

  FocusTimerSnapshot? get snapshot;
  bool configureMinutes(int minutes);
  void start();
  void pause();
  void resume();
  void stop();
  void finish();
  void poll();
  void dispose();
}
```

This is a signature sketch, not a compiling implementation. The actual immutable snapshot has a private constructor and derives/validates its invariants through the controller. No ChangeNotifier, StreamController, scheduler port, persistence interface or application singleton is required in this plain-Dart file.

Snapshot is nonnull until dispose, then null. All post-dispose commands are no-ops; configureMinutes returns false. Dispose is idempotent and clears the controller's captured accumulated duration/anchor/snapshot. It does not claim secure erasure of already-returned immutable values.

Invariant: configured duration equals minutes in1..180; elapsed and remaining are nonnegative, elapsed is capped at configured duration, and elapsed+remaining equals configured duration. finishReason is present exactly in finished. Its elapsed reason requires zero remaining. revision changes on a real control transition/configuration change/zero expiry, not on each elapsed redraw; it rejects stale control intents without invalidating every running-frame callback.

Production screen owns a Stopwatch started once and injects elapsedMicroseconds. Unit/widget tests inject an advancing monotonic integer clock. UTC/DateTime.now never computes this interval. Polling a running interval uses accumulated active interval time plus current monotonic delta from its running anchor, then clamps at the configured duration. Pause stops accumulating; resume starts a new anchor while retaining accumulated time. A delayed frame/poll therefore does not drift or count paused time. This is focus interval time, including foreground time without interaction; no active-effort or idle-policy claim is made.

Invalid constructor minutes throws ArgumentError. Invalid configureMinutes returns false before changing any state; the UI keeps the last valid configuration. Valid commands poll before applying the resulting legal-state transition. Repeated commands do not reset a running anchor or duplicate a terminal transition, although normal elapsed time can advance when a command polls.

## Exact transitions

| Command | Effective source state | Result |
| --- | --- | --- |
| Constructor | none | configured, default25 or validated initial minutes, elapsed0, remaining full, revision0. |
| configureMinutes(valid) | configured, stopped, finished | configured with that duration and elapsed0. Configuring the identical value while already configured is an accepted no-op. Reconfiguring a terminal interval deliberately prepares a new interval. |
| configureMinutes(invalid), configure while running/paused | any invalid input; active interval | false, no configuration reset. Controls disable active edits. |
| start | configured, stopped | running from elapsed0 using the current configured duration and a new monotonic anchor. |
| start | running, paused, finished | no phase/anchor reset. Paused requires Resume. Finished requires the explicit new-interval/configuration action. |
| pause | running before expiry | paused with its exact accumulated elapsed/remaining duration. |
| pause | configured, paused, stopped, finished | no control transition. |
| resume | paused | running with the same elapsed/remaining duration and a new anchor. |
| resume | all other states | no control transition. |
| stop | running, paused before expiry | stopped, accumulated elapsed discarded, remaining reset to the configured full duration. No completion summary/reward. Start may begin a new interval. |
| stop | configured, stopped, finished | no control transition. It does not overwrite a completed result. |
| finish | running, paused before expiry | finished, reason manual; retain the actual elapsed and remaining duration for this local interval summary. It may finish early. |
| finish | configured, stopped, finished | no control transition. |
| poll reaches configured duration | running | finished, reason elapsed, elapsed exactly configured duration, remaining0. One transition only. |
| dispose | any alive state | snapshot null and commands inert. A fresh screen creates a fresh interval. |

If a command arrives at/after expiry, its preliminary poll performs the elapsed finish first. Stop/Finish cannot then replace that completion or restart it. A paused interval does not expire while paused. Manual Finish with zero accumulated duration is allowed and displays zero local interval time without any recorded-time claim.

Stop is destructive only to this transient local interval; its label must say it clears this interval. Finish retains a local terminal display. Neither means an acknowledged canonical learning completion. New interval/configure explicitly resets the terminal display; there is no automatic restart or repeat loop.

## Screen constructor and binding

```dart
const FocusTimerScreen({
  super.key,
  required this.expectedOwnerId,
  required this.ownerChanges,
  this.monotonicMicros,
  this.languageCode = 'th',
});

final String expectedOwnerId;
final Stream<String?> ownerChanges;
final FocusMonotonicMicros? monotonicMicros; // Deterministic test seam.
final String languageCode;
```

The screen receives the exact captured actual owner stream from Choose. It does not resolve a different stream or create an owner. Required expectedOwnerId must be nonblank and exactly match the observed owner. No timer is authorized/displayed from an ownerless synthetic fallback. A pending initial owner remains pending; mismatch/null/error/done makes this screen permanently unavailable.

Subscribe to the required ownerChanges synchronously in initState or the first didChangeDependencies before the child handoff completes. Do not defer the subscription to a post-frame callback. The parent launch lease and the child's active subscription must overlap, so an A-null-A event between first mount and the first frame cannot disappear before the child starts observing. Clear owner state immediately on invalidation; defer only a rendering notification when necessary.

Resolve AppDependenciesScope identity once for invalidation only. Replacing that scope, expected owner, stream instance or injected clock invalidates this open tool. This constructor does not require another progress/learning service. Same-owner repeated matching events do not reset the interval. A null/mismatch followed by the same ID cannot revive it.

Use separate transient lifetimes:

- Owner/context generation is sticky for this screen. Owner null/A-B-A/error/done, dependency/stream/clock replacement and disposal increment it, clear the controller/display/input/captured actions and cancel the ticker. That screen requires a fresh open; it does not transparently adopt a new owner.
- Visible-action epoch changes when the current route/pane/foreground is lost or a control transition makes an old callback stale. Captured controls require both the current owner generation and current visibility. Owner invalidation clears private state synchronously; defer only the rendering notification when a framework build is in progress.
- The timer controller's revision identifies a control state. Check the captured revision after an up-to-date poll, so an old Start/Pause/Resume/Finish callback cannot control a replacement interval or override natural expiry. If polling expires it, render the finished state and reject the stale command.

A current owner and current route/pane in AppLifecycleState.resumed are required for controls. Use ModalRoute.isCurrentOf and Visibility.of observation; checking a route name is insufficient.

On background/inactive/hidden pane/foreign route cover, immediately poll+pause an actually running interval, cancel its redraw ticker and invalidate visible callbacks. Keep the same-owner paused interval. While hidden/covered, render only a generic unavailable/paused message and remove the private minute draft and elapsed/remaining values from the presentation; only the transient controller retains the paused interval. Returning visible offers explicit Resume with the same remaining duration; it never resumes automatically. Further covers while already covered do not restore actions or add time. Owner/dependency invalidation is still observed while hidden and clears the interval instead of merely pausing.

A one-second Timer.periodic in the screen is only a redraw/poll trigger while running and visible. It is cancelled on pause/terminal/hide/disposal. Render remaining seconds using a ceiling so a running subsecond remainder is not displayed as completed00:00. Every valid command polls first; correctness does not depend on the ticker firing exactly on time.

App-bar Back and the visible untimed action may pop only this exact current route. Leaving discards the transient interval; cancel/clear before pop. An old Back/untimed callback cannot pop a foreign top route. No route result is converted into learning evidence.

Back and the untimed exit remain available while the owner is pending or permanently invalidated. These exits require this exact route to be current, the app to be foreground and the pane to be visible. They do not require an owner lease or a live timer snapshot. Owner authorization gates timer commands, so losing the owner cannot trap the user on the unavailable page.

## P06 navigation and narrow helper reuse

Use route name learning/focus-timer and key focus-timer-entry. The entry requires an observed current owner and captured read epoch, not a successful unrelated Progress snapshot, ReviewCenterUseCases or LearningUseCases. A failed/pending Progress projection must not block the independent tool after owner observation.

Two actual callers now justify a private helper inside ChooseModeScreen. Keep the Review Center wrapper's existing dependency check and captured same LearningUseCases. Add the timer wrapper. Share only owner-bound entry capture, beginLaunch(requireSnapshot:false), own push/read clearing, return observation and fresh parent read.

Suggested private shape:

```dart
VoidCallback? _independentToolAction({
  required String routeName,
  required bool available,
  required Widget Function(
    String owner,
    Stream<String?> owners,
  ) destination,
});
```

The destination closure captures the exact dependencies it needs; the Review Center wrapper preserves its existing bindings. No public navigator/controller framework, registry, new feature flag, extra shared helper file or ProgressHostBinding change is required.

At tap, require current parent route, binding/dependency/stream identity, current captured readEpoch and an observed owner. Capture immutable owner/stream/dependencies, start the parent launch with requireSnapshot:false and clear its private Progress rows synchronously before push. Rapid repeated taps must open at most one child.

Do not make child validity depend on the parent's cleared readEpoch or on parent.route.isCurrent after push. Also distinguish the following two outcomes: a foreign cover or background burns the parent's return intent, while a same-owner timer child remains alive in its paused state and can explicitly resume after the cover returns. Reusing the existing conditional Review Center builder verbatim as a post-mount timer validity check would conflate those outcomes.

The helper must keep a sticky child owner/dependency lease separate from parent return eligibility. Validate it before the first child mount to reject an ABA between tap and build; after mount, the destination screen owns its actual stream/route/lifecycle policy. A small private per-launch capture with a subscription to that same actual stream is acceptable if needed to retain owner invalidation independently from parent launchGeneration. It must be cancelled in finally. Do not substitute a static Stream.value or another owner authority.

A foreign cover above the owned child must burn parent return intent even when Choose is already covered. It must not unmount/replace a same-owner timer simply because that parent return generation was burned. On dependency/owner loss, the child itself clears and becomes unavailable. Normal pop is not a foreign-cover bug; use exact route/currentness and actual tests, not the retracted lifecycle suspicion from Wave21.

On a valid own return, require the intended parent route current and call syncVisibility once to start a fresh read. Do not add an unconditional second refresh. On a foreign-burned return, reject old entry/row callbacks and use the normal visible fresh parent read; never revive the old return intent or auto-pop another route.

Existing Review Center entry/return tests and all same-owner/LearningUseCases assertions must remain intact after the helper extraction. Native/SRS/Quiz Score ownership is not part of this refactor.

## Product copy and accessibility

Use Thai/English labels for configure minutes, Start, Pause, Resume, Stop and clear, Finish this interval, New interval and Learn without a timer. Show a persistent concise explanation that this is a local focus interval and is not recorded learning time. On early/manual finish distinguish it from reaching the configured duration. Do not show XP, coins, streak credit, mastered words, Research acceptance or a saved/synced badge.

The minute field accepts trimmed whole-number input1..180; empty, decimal, negative and out-of-range values show an inline error and retain the last valid configuration. It is editable only in configured/stopped/finished. The keyboard must not cover validation or the primary action; use existing AdaptiveContentPane/scroll/Material components.

The untimed action clears/exits the tool to existing ordinary activity selection. It creates no lesson automatically and keeps normal untimed learning available. A timer overlay continuing through another lesson, shared session duration and idle capture are later work; this page does not imply they already exist.

Verify Thai/English320px at200-percent text scale with IME, portrait/landscape where current conventions require it, Light/Dark, keyboard Tab/Enter/Space and visible focus. Buttons and state have semantic names and non-color state. Announce state transitions, not every second of countdown. Reduced Motion uses the same controls and a readable static numeric countdown, with no animation required to understand completion.

Proposed stable keys: focus-minutes, focus-configure, focus-status, focus-remaining, focus-start, focus-pause, focus-resume, focus-stop, focus-finish, focus-new-interval, focus-untimed. Only controls valid for the displayed state are enabled.

## Acceptance and test seams

Unit tests use a fake monotonic integer and direct poll/commands, not sleeps or timer tick counts. Prove:

1. Bounds/default, invalid input without state loss, immutable snapshot invariants and exact transition table.
2. Accurate accumulation across multiple running segments; paused time excluded; delayed polling clamps correctly; UTC changes are irrelevant because no wall clock is read.
3. Repeated commands preserve the interval/anchor and terminal reason; zero expiry transitions once; manual finish and Stop differ; stopped restart starts0; finished never auto-restarts.
4. Revision changes only for control/terminal changes; dispose clears and all late commands are inert.

Widget tests inject monotonicMicros and drive real controls. Cover same-owner foreign/background/pane loss pause and explicit Resume preserving remaining, a second cover while already covered, old captured callbacks before redraw, actual owner A-null-A/A-B-A, owner stream error/done, dependency/stream/clock replacement, Back beneath foreign top route and disposal. Owner invalidation from a sibling build must clear state without setState-during-build errors.

Emit A-null-A after the child first mounts but before its first frame, then verify that the tool stays unavailable. Prove that Back and untimed exit work for both pending and invalidated owners on the current foreground visible route, and reject retained exit callbacks while a foreign route covers it.

P06 tests must use a real owner/harness, verify exact stream/expected owner and no default service creation, open with a failed/pending unrelated projection, reject retained entry after real owner ABA and after a prior open/return, and prove one child for rapid taps. The existing Review Center path must still receive its exact dependencies after helper reuse.

Use the existing ReviewCenterHarness and its real database/LearningUseCases. After permitted startup/owner initialization, compare all37 tables byte-for-byte around timer configure/start/pause/resume/stop/finish/close/fresh-open. No session, answer, SRS, ledger, reward, quest, streak, Research event/row or outbox change is allowed merely from timer operations. Fresh open shows default25/configured and never restores a completed/stopped/running interval. The same harness's ordinary canonical learning path must still create only its normal acknowledged evidence when explicitly invoked; timer code never invokes it.

Preserve the proven real-I/O subscription lifecycle: create and cancel actual database stream subscriptions in the harness/captured I/O zone through tester.runAsync as applicable, unmount and drain frames before closing the harness. Do not introduce Stream.value owners over a real runtime fixture, arbitrary waits, skipped tests or warnIfMissed:false. Scroll/tap actual hit-testable controls and wait only on bounded observable state.

## Execution and review order

1. Rebind current source/plan/schema and confirm these new paths still have no equivalent implementation. Freeze the six-file set and the precise API above, with any reviewer correction recorded before coding.
2. Write tests first. A new-type compile RED is an API check, not behavioral proof. Use a real missing P06 entry/control behavior as the old-source failure where possible; retain all existing tests/assertions.
3. Implement the plain-Dart timer and focused screen, then the bounded two-caller Choose extraction. One writer per C file; D drafts may remain disjoint. No runtime checks run in parallel against shared Flutter outputs.
4. Root runs focused unit/widget/Choose/Review Center entry checks, then affected canonical learning and accessibility/layout checks. Inspect any actual golden mismatch and preserve its evidence.
5. Independent connected review checks the same-owner paused child versus burned parent intent, all-table no-write proof and stale callbacks on the current hashes. Freeze writers before integration analysis/full regression/build as required by the parent release plan.
6. Attest actual outcomes and remaining f24 dependency. The f23 UI slice can be engineering-complete while f23 remains Partial. No deployment, physical UAT, learning efficacy or Research authority follows from unit/widget success.

The bounded six-file implementation is locally attested at71a230a4. Missing-entry/API failures, corrected boundary/IME failures and the validation-wrap RED remain preserved. Actual full4552/11m45s, exact analysis0/18.1s, CLI23, offline390/one existing skip, normal main/debug APK121.2s and independent artifact/source/log ACCEPT7a8171ae close this slice. This changes only f23 to Partial; it does not implement f24 or establish production/UAT/research efficacy.

Model the Domain shaped the explicit five-state snapshot and transition table. Prove It Works shaped the proposed fake-clock arithmetic, exact route behavior and all37-table readback. Test Behavior, Not Implementation shaped control/readback assertions rather than scheduler tick expectations.

## Wave22 completed local implementation checkpoint

The optional transient Focus Timer/P06 slice is locally verified at application71a230a42ac767c956c0192eed6af01ee2521a59: full4552PASS/11:45, exact analysis0/18.1s, CLI23/23, offline backend390PASS/one existing opt-in skip and normal main/debug APK121.2s/native-provider0 with environment restored. All767Dart/54CLI/92backend exact inputs match before/after; independent actual-APK/source/log readback ACCEPT7a8171ae. Only f23 changes from Missing to Partial, giving14Connected/19Partial/11Missing; f24Missing, f22Connected and f21Partial remain. Timer elapsed creates no learning credit or Research/reward fact. See [Wave22](../../field/2026-10-31-remaining-systems-wave22.md).

Controller39/UI44/Choose41/existing Review Center entries2 give actual126 focused cases. The pre-wrap final126/22s, later actual English RenderParagraph clipping RED, errorMaxLines4 with assertions in all six existing layout cases, and post-wrap126/21s remain distinct. A later no-comments review accepted only one Choose narration deletion; there was no application-logic change before the final commit.

Source freeze wave22-frozen-dart-source-final.json SHAf709d645b3ee5a5dc20e11565f305bdda662c13536dac261c180d0f66f974db7 binds767 tracked Dart paths. lib tree1ad82b870d49f69c0e7588f9a1695ad7b62f4f19 and test tree41e5f702016bfd5ee40bf77dd1b8b3239d1e8fbe are actual. Root's actual-log/source review SHAd24b32801a8c0fe83f010262a9471bd869649e54e8e00ff670808f1b3fe2682c and independent readback SHA7a8171ae243db5d847abc441df1d932495cdbc7bc939ed4277fb410691562c96 preserve the raw CLI allLogsInspected=false field while separately recording all23 logs and3 backend logs/JUnits actually read.

The normal APK is252381649bytes, SHA58e6f96782a18aac0fade0ee54d4bb2793a386ec71f9992e6bee1065bae53637. All752 entry names are unique and CRC-valid. Its103094016-byte kernel SHA5501de6f0a96134b2f8fbff9cc8145d42081c125829726dc6b871dd6e62b5b42 contains actual71a230a4 at offset85878348. File time is inside the actual build window. Source inputs match before/after. No install or publication occurred.

Schema remains20/37 with v21+ unreserved, frozen8/44 unchanged. f24 automatic active-learning time and its authority/policy are separate next work. Grounding hashes below are retained historical API baselines, not the final freeze.

## Grounding input hashes

| Path | SHA-256 |
| --- | --- |
| lib/screens/choose_mode_screen.dart | 8caf82b00c9821eaa4abd960b129df3f3aeac0b9cc458976a1fe73c6507cdd24 |
| test/screens/choose_mode_screen_test.dart | d989f9d17b4c1a696eab25b694481b75f62b687c9c5a1f35debfd4039f44fbbb |
| lib/features/progress/presentation/progress_host_binding.dart | bf2fc951b5a9af30326d3815dadb44a636c85daf876f29895c2e79bde4542579 |
| lib/features/progress/application/progress_use_cases.dart | 852e1d7a4c27069386a76f0ad678512d5ae75814c08804c1b41a2935bd8848bc |
| lib/navigation/app_routes.dart | 54eaf7464bde4ea5150de8d86f1b0b24d822d48209b5c6a791ef5ef865e3408e |
| lib/runtime/app_dependencies.dart | fa8b93460da473ee9800e37e1e0781123ea821e3507ca8b54ce26c6b72890666 |
| lib/product/feature_contract/alltcas_idea_integration_catalog.dart | 626e4f123d531d4fbfcc7dba86e9b8420fdca242d67a3dc2e77cff7109492820 |
| test/architecture/alltcas_idea_feature_contract_test.dart | 5a79ae72a585a1afdc7aa44fcb638d0fe9f5991e89a340f42e4a340e5e5b4d92 |
| lib/data/local/app_database.dart | ef699163e99f561b5184c4f6b062b7b17e06ca073cb0479428de33ac495f91a4 |
| docs/database/schema_ledger.md | f064ae8af3360399837d0a3ba087c0707ea2a14ed69bbbd76b3dbf4e44c7d378 |
| test/support/review_center_harness.dart | 3dc706a2065124597ab713546f4f9191ddc3063585c9290761e1e66be1ba28ee |
