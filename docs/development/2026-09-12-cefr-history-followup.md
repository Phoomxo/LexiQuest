# Truthful CEFR history metadata implementation plan and handoff

Worktree `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`.

Goal: show a truthful generic CEFR activity name for canonical local reading history without asserting a saved passage title/level or approved published pack identity.

Architecture approved by root: a separate immutable presentation on LearningHistoryEntry, eligible only for an unpinned canonical CEFR configuration and no assessment. The current pack resolver and replay authority remain unchanged. Do not join mutable live vocabulary or infer the current reading-catalog revision as historical content.

Tech stack: existing Dart history read model and Drift in-memory integration tests. No database schema, evidence, event, source assets, research or live-service changes.

- [x] Inspect AGENTS, R12 and unattended checkpoint gap, current configuration/reader/replay/UI.
- [x] Root approved conservative display design.
- [x] Write tests for eligible metadata, unavailable replay, unchanged source rows, foreign owner, unrelated modes, pinned/deleted pack, legacy unconfigured history and assessment exclusion.
- [x] Root ran RED focused test before production getter: missing getter, plus Drift/matcher isNotNull ambiguity; fixed import ambiguity.
- [x] Added minimal domain presentation/getter; root consumes in History UI title/detail only.
- [x] Root ran history GREEN: 37 tests passed. Scoped final diff inspected; root owns separate UI integration verification.

API: `entry.localCefrPresentation` returns nullable `LearningHistoryLocalCefrPresentation` with `titleThai` and `detailThai`. It is display-only and does not modify `packIdentity`, `packTitle`, `contentAvailability` or replay eligibility.

Root commands (serialized; this agent must not run Flutter/analyze/build):

```text
flutter test test/features/history/learning_history_reader_test.dart --plain-name "unpinned CEFR history has truthful metadata without replay or source writes"
flutter test test/features/history/learning_history_reader_test.dart test/features/history/learning_history_replay_test.dart
```

Implementation verified by root history GREEN 37 passed. No Flutter/analyze/build process was started by this agent. Scoped git diff --check passed (existing CRLF warnings only). Changed by this subtask: domain/learning_history_models.dart, learning_history_reader_test.dart and this report. Pre-existing reader quiz-carrier support and its tests remain intact; this subtask did not edit the reader or replay authority. No outstanding implementation issue in this bounded metadata subtask; root owns UI and wider integration.

## Follow-up assigned: Today–History Pair route integration tests

Root separately authorized this agent to edit only `test/screens/main_navigation_screen_test.dart` for route tests. Canonical fixture provisions the shipped starter assets with verified manifest bytes, completes a four-pair source, and navigates Today → History through UI. Expected checks: callback present, named `home/today/history/pair-replay` route, fresh canonical practiceReplay purpose/source ID, one answer without reward/points changes, and no new host/session when owner changes after History opens. Fixture database/internal-Pair/history overrides are explicit opt-ins with existing defaults preserved.

Root observed RED (callback null in both initial variants), implemented the two runtime screens, and reported GREEN 2/2. This agent read the two runtime changes and traced host/source admission and live gate; no actionable finding. Root then requested a third live-gate test: RuntimeFeatureRegistry disables Feature.quiz after History opens and before replay tap; it must create no host/session or rewards. Third variant written; root runs all three with the command below. No test process run by this agent. Test file frozen for integration.

```text
flutter test test/screens/main_navigation_screen_test.dart --plain-name "Today History packaged Pair replay owns route and practice boundary"
```

Root subsequently reported all three Pair variants passing in the broad navigation/history run (56 passed, one existing Today review journey failed). The failed completion assertion followed an offscreen `meaning-quiz-next` tap: the log reported Offset(400, 736) outside the 800×600 viewport after the answer example expanded the page. Added `ensureVisible` and `pumpAndSettle` before both next-button taps in that journey; all durable-session and answer-count assertions remain intact. This is a test interaction correction, with no runtime or fixture-default change. Focused rerun is delegated to root; no passing result for this correction is claimed yet. Scoped diff check passed; test and report are frozen for root verification.
