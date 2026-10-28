# PM8 composition correction handoff (2026-09-07)

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`.
Branch: `codex/pair-matching-pm0-pm8`.
Base commit: `94c1e97fea5097af144b63adfdf9ab2e5f277bee`.
This report supplements the historical PM8 report; it does not assert whole-PM8
or release completion. Root owns Git, portable documentation and release gates.

## Scope and root cause

Pair host and unavailable-session recovery constructed fresh evidence adapters
from learning alone, bypassing caller-composed persisted providers and evidence
identity/time generators. Both now require the caller's adapter and reject a
different learning authority. The runtime passes that exact instance to normal
and unavailable recovery. Production constructor authority remains exactly one
declaration plus one bootstrap call; the architecture allowlist is unchanged.

The matching screen is a compatibility wrapper whose actual Legacy renderer was
already extracted. Its guard now verifies the explicit wrapper import,
delegation and evidence forwarding, checks bootstrap resolution in the actual
renderer, and prohibits authority constructors in both files.

All explicit callers now compose/reuse the adapter. Measurement uses actual
persisted rollout/research providers. The new actual-host test proves provider
calls and exact evidence ID/time; both constructors have mismatch rejection.

Enabling the intended persisted composition exposed eight stale measurement
expectations. Existing policy allows protocol-controlled recognition rewards;
SDS15.5 denies recall/SRS advancement, while Practice Replay denies all automatic
effects. The authorized twelfth file changes only these test oracles: retain exact
prior SRS, require every committed decision receipt without creating it, compare
the entire ledger against prior rows plus exact eligible-correct-answer rows,
and require enforced protocol/assignment/cohort/consent pins when Motivation
permit authority is denied/expired but evidence authority remains active.
Pair answers retain null assessment instrument/form fields. Actual Replay still
compares all primary/research effects byte-for-byte. No evidence/reward policy,
schema, production gate, permit or signature implementation changed.

## Retained evidence

- Root's full-default on base94c1e97f: 4848 pass, 2 architecture failures,
  0 skipped, native/gate exit1. Root owns that evidence.
- `pm8-composition-red-20260907T041931503.log` and metadata:
  `flutter test --no-pub --reporter expanded test/architecture/provider_composition_boundary_test.dart`;
  6 pass/2 same failures, exit1, 9.0142459s.
- `pm8-composition-focused-20260907T042357674.log` and metadata:
  `flutter test --no-pub --reporter expanded test/architecture/provider_composition_boundary_test.dart test/features/learning/pair_matching/pair_matching_experience_host_test.dart`;
  51 pass, exit0, 55.464505s, UTC04:23:57.6796620–04:24:53.1441670.
- `pm8-composition-affected-20260907T042539131.log` and metadata:
  `flutter test --no-pub --reporter expanded test/features/learning/pair_matching test/features/adventure/adventure_pair_renderer_parity_test.dart test/features/adventure/presentation/adventure_pair_experience_test.dart test/screens/matching_mode_screen_test.dart test/features/learning/matching_mode_adapter_test.dart test/features/learning/current_activity_evidence_test.dart test/runtime/app_bootstrap_test.dart test/architecture/provider_composition_boundary_test.dart`;
  624 pass/8 measurement-oracle failures, exit1, 220.5712959s,
  UTC04:25:39.5344490–04:29:20.1057449. All 1045 lib/test input hashes unchanged.
  Four failures assumed no protocol recognition points; four expected Legacy
  despite active enforced evidence authority. This failed run is retained.
- `pm8-composition-measurement-20260907T043242631.log` and metadata:
  `flutter test --no-pub --reporter expanded test/features/learning/pair_matching/pair_measurement_boundary_test.dart`;
  17 pass, exit0, 196.4454689s, UTC04:32:43.0245562–04:35:59.4700251.
  All 1045 lib/test input hashes unchanged on final twelve-file snapshot.
- `pm8-composition-analyzer-20260907T043620569.log` and metadata:
  `flutter analyze --no-pub lib test`; no issues, exit0, 15.3835672s,
  UTC04:36:20.9803480–04:36:36.3639152. All 1045 input hashes unchanged.
  Root explicitly requires no repeat of the prior covering suite solely for the
  twelfth test-oracle edit; final full default/serial remain root-owned.

Formatter logs/metadata preserve exact argv and native exit:
`pm8-composition-format-20260907T042344929` covered 11 files (6 changed);
`pm8-composition-format12-20260907T043225232` covered the twelfth file (1 changed).
The retained affected run emitted one Drift duplicate-AppDatabase warning;
this is recorded separately from its eight diagnosed assertion failures.
Read-only diagnosis had bounded path-discovery mistakes (PowerShell literal
wildcards to rg and a guessed reconciler path); corrected by bounded file
discovery, with no write/tool retry loop. Git read/diff checks emit existing
autocrlf notices; no claim of universally warning-free execution is made.

## Frozen source identity

Packet: `pm8-composition-correction12-20260907T0434.diff`.
Bounded extra test delta: `pm8-composition-correction12-20260907T0434.oracle-delta.diff`.
Manifest: `pm8-composition-correction12-20260907T0434.manifest.json` contains exact
before/current raw SHA256 and confirms prior eleven hashes unchanged.
All packet paths are under `.superpowers/sdd/`; the named timestamp is a packet
label, while manifest UTC is authoritative.

| Path | Final raw SHA256 |
| --- | --- |
| lib/features/learning/pair_matching/presentation/pair_matching_experience_host.dart | cf14a7ae8c0ace70a0982dc6c02c1cf801e661127cf948c186708fa1810d69d2 |
| lib/features/learning/pair_matching/application/pair_matching_unavailable_session.dart | 25f3a5d44102feecf791d550f38b0dbbeb764ed0e6fba6ae9456c7e02919d313 |
| test/architecture/provider_composition_boundary_test.dart | a42434626c1dc1f8e5f1787e8830019dc3acbcca98b0a432aac9e2324106561a |
| test/features/learning/pair_matching/pair_matching_experience_host_test.dart | 58ab9f86bfc4514c4066952133a2e64772da7c8b3db8280eaa2754306df21450 |
| test/features/adventure/presentation/adventure_pair_experience_test.dart | 5266a82308412d04baa7997149abe5c958e084711c0140a8e29a06e7a2a57ab3 |
| test/features/adventure/adventure_pair_renderer_parity_test.dart | 887ec3668ebe63f2e94e29571d4ab88769e7162c9853ae6de790452f0b958e6a |
| test/support/pair_measurement_fixture.dart | 1dc6101474354c495e10f0fa6d78931439092a01691addb5cf01bd1392a789b6 |
| test/features/learning/pair_matching/pair_matching_compatibility_rollout_test.dart | 438eea483f121d68abb553843c3a80f5baa7adec3b9e6732e73555e93e761bae |
| test/features/learning/pair_matching/pair_configured_disposition_test.dart | 2bcd6cba15938cfa947552128d4279eda2d1faa8e5718e66ff32922ee6d02dd3 |
| test/features/learning/pair_matching/pair_matching_owner_upgrade_test.dart | caea56b3e213b0ee56ce0910b9c8ed0acbe1e716f1978605c97ddf88db9f3d44 |
| test/features/learning/pair_matching/pair_matching_host_golden_test.dart | 0e87da4e812a014a86c364f93cd173ecfef62c761ce757469e19737d0b13d639 |
| test/features/learning/pair_matching/pair_measurement_boundary_test.dart | ca49536057f35c00415df000b1973917af8a75ca16cbfadb43c6e887f8499179 |

## Explicit handoff

At UTC2026-09-07T04:37:12.9906673, the final check
`pm8-composition-final-handoff-check.json` confirmed all twelve manifest hashes
match, HEAD remains the base commit, `git diff --check -- lib test` exits0,
and no Dart/dartaotruntime/flutter_tester processes exist. The seven native
generated-file M statuses remain present with empty actual diffs. No native
files were edited by this finalizer.

All source and serialized Flutter/Dart tools are explicitly released to root.
No further source edits or tool runs are planned by finalizer. Root may proceed
with its accepted-review/source-commit/full-release sequence. Final independent
review verdict is root-owned; this report is implementation evidence, not
self-approval or whole-PM8 completion. No full-default rerun, serial suite,
generator, dependency setup, build, scan, Git mutation, deployment or real
research operation was performed in this correction wave.
