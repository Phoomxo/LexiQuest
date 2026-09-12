# System follow-up 1–6 implementation plan

User approved the proposed six tasks on 2026-09-12. Continue in existing worktree
`C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch codex/pair-matching-pm0-pm8.
No new permission gate, commit, production rollout or paid service is required.

**Goal:** close Today replay/history integration, verify combined use and UI,
evaluate camera models where autonomous evidence is possible, and deliver a
source-pinned debug APK preserving the current vivo fixture.

**Architecture:** use the existing Pair practice-replay host and canonical
admission; no new evidence/reward writer. Separate truthful local CEFR display
metadata from approved learning-pack authority. Reuse current Flutter theme and
accessibility semantics. Camera measurements compare identical existing inputs;
no model replacement without adequate evidence, no claimed physical scene test.

**Tech stack:** Flutter/Dart, Drift/SQLite, existing TFLite/Python tools, ADB.

- [x] Root: Today→History callback and owner/live-feature-safe Pair replay route.
  Reuse the shipped curated runtime and existing retry operation identity;
  never construct an allowlist by trusting arbitrary history presentation data.
  Tests prove navigation, stale owner/gates, practice-only/no duplicate rewards.
- [x] Agent one: history domain metadata/tests only; root consumes in History UI.
  Generic CEFR activity label when validated config identifies that activity,
  explicit unavailable original title/level; leave pack identity/replay unchanged.
- [x] Root: combined Matching4/6, Today, Focus, Quiz/SRS regression and device
  scenarios. Distinguish fixture writes caused by actual activity from browsing.
- [x] Agent two: inspect screenshots/source, return concrete UI/accessibility
  issues; disjoint UI repairs assigned after review. Human TalkBack is pending.
- [x] Agent three: existing-model/data audit, paired offline benchmark and vivo
  benchmark preparation. Root owns ADB and all Flutter execution. Keep model
  selection provisional if representative physical evidence is absent.
- [x] Freeze writers, current-source integration tests/analysis/build, APK asset
  and SHA audit, binary-safe update, start/restart/persistence, checkpoint.

Root alone edits main_navigation_screen.dart, pair_matching_learn_screen.dart,
learning_history_screen.dart and navigation/widget tests initially. Agent one
owns lib/features/history and test/features/history. Agent two initially writes
its audit report only. Agent three owns camera scratch/report only. All tests,
analysis, build and codegen are serialized by root. Preserve pre-existing edits,
frozen 8/44 contracts and source catalogs. No security-worker workflows.

Acceptance evidence must distinguish code/synthetic tests, physical UI/inference,
and missing human/live-service conditions. Items7–10 remain external acceptance:
human audio/TalkBack, paid/live AI settings, two-device cloud sync, real scene
camera capture and final model acceptance. Do not report those as passed.

## Checkpoint 2026-09-12 R14

826 combined tests and explicit source analysis passed; both debug APKs built
with stable source pins. Manual v23 R14 installed on vivo, all database tables
equal before/after update, installed SHA matches the computer APK. R13's real
UTC-microsecond replay rejection was fixed and R14 opens the old 6-pair board.
Camera: 40 paired held-out inputs and 12 vivo fresh-process timing runs complete;
retain baseline, no physical scene acceptance claimed.

All six autonomous tasks are complete. On the user's continuation instruction,
root resumed fresh device observations: Pair6 and Pair4 completed, all six
readings opened/back/reopened, one real CEFR exposure completed, verified baseline
downloaded through scanner and reopened ready. Restart preserved every learning
row; only the existing offline-cache verification timestamp refreshed. SRS's
physical empty-due case passed; due-card grading has automated evidence only.
Human speech/TalkBack, paid AI, two-device cloud, and physical scenes remain the
explicit external acceptance above, not a reason to pause these six tasks. See
`docs/development/2026-09-12-system-followup-r14-checkpoint.md` for exact evidence,
APK hashes, final database audit, and remaining external acceptance.
