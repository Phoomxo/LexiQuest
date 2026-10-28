# Task 1 report — truthful Prototype feature contract

## Status and commit

- Status: implemented, committed, and locally verified.
- Base: `45e83121adadfcbd1075a048501f57686db68bb7`.
- Commits:
  - `6bee6143d384603565ba4696694fadb9a8e73f6f`
    (`docs: freeze the prototype feature contract`);
  - `ae0b8c5399eff600fa75a2327ae8319decf25a7a`
    (`test: tighten prototype contract coverage`).
- Branch/worktree: `release/v0.1-complete-system` in the required isolated
  worktree.
- Feature source was not changed.

## Inventory coverage

The inventory contains exactly 63 feature rows:

- 8 typed account routes;
- 5 primary `NavigationBar` destinations;
- 3 drawer entries, including the policy-gated Shop;
- 20 learning/practice buttons from `ChooseModeScreen`;
- 9 settings/account actions (3 profile actions and 6 legacy-settings
  actions);
- 4 nested category/vocabulary-management entries;
- 8 nested practice entries;
- 6 hidden/unexposed legacy, research, admin, reading, and device entries.

It names all 43 unique production screen files currently derived from the
bounded route/menu source graph and its recursively constructed destinations.

The document:

- distinguishes 8 `AppRoute` typed routes from indexed destinations and direct
  `MaterialPageRoute` construction;
- records readiness as `ready`, `degraded`, `blocked`, or `not exposed`;
- records offline behavior, configuration/permission needs, truthful
  unavailable behavior, target phase, and source evidence;
- identifies direct screen imports: 6 Firebase screens, 1 HTTP screen, and 2
  plugin screens (SharedPreferences and speech recognition);
- treats curated vocabulary/questions/sentences/stories/equipment/export
  examples as product content rather than user history;
- treats default scores, dated weakness records, a fabricated past ghost
  snapshot, simulated device results, and fabricated speech measurements as
  debt;
- records the Object Scanner, legacy Firestore seed screen, thesis chart,
  associative reading screen, legacy Home wrapper, and legacy Result screen as
  not exposed.

## Rule and allowlist design

The allowlist has schema version 1 and exactly 18 unique `{path, rule}` pairs:

| Rule | Pair count | Design |
| --- | ---: | --- |
| `sample-user-history` | 3 | Detects sample/mock/fake user-history vocabulary plus the three confirmed default history constructions. It does not match statistical sample names or curated card/word packs. |
| `mock-production-provider` | 0 | Detects a mock provider/service/repository/gateway assigned or returned in production; does not match the declaration of the test-only mock ML service. |
| `simulated-device-result` | 2 | Detects simulated device-result identifiers/controls and the delayed fixed microphone input. |
| `random-fabricated-measurement` | 1 | Detects `Random().nextDouble()` measurement generation. Legitimate list shuffling, word scrambling, secure ID entropy, and suggestion selection are not matched. |
| `placeholder-transaction-feature` | 2 | Detects explicit placeholder/not-implemented production paths: Shop and unavailable ML labeling. |
| `canned-ai-response` | 1 | Detects the AI tutor canned fallback function and call sites. |
| `direct-screen-firebase-access` | 6 | Applies only to `lib/screens/` and matches Firebase/Firestore imports. |
| `direct-screen-http-access` | 1 | Applies only to `lib/screens/` and matches direct `package:http` imports. |
| `direct-screen-plugin-access` | 2 | Applies only to `lib/screens/` and matches capability/persistence plugins, including `speech_to_text` and `shared_preferences`; UI-only `fl_chart` and `flutter_speed_dial` are not classified as provider debt. |

Target phases are feature-owned:

- Phase 2: vocabulary, practice, and direct Firestore/HTTP paths;
- Phase 3: scanner, speech, device simulation, and fabricated speech
  measurements;
- Phase 4: canned AI;
- Phase 5: progress history and trusted economy.

The contract obtains candidates only through `git ls-files -- lib/`, filters
to Dart files, and scanned 196 tracked candidates. It never emits matched
source text, values, prompts, URLs, or credentials. Finding output is limited
to relative path, rule, target phase, and count, plus aggregate counts.

Before scanning, it validates JSON parseability, schema version, required
fields, relative forward-slash `lib/` paths, known rule names, target phases,
feature IDs, file existence, and duplicate pairs. It then enforces an exact
two-way comparison so new findings and stale entries both fail. The inventory
must contain every allowlisted feature ID and every source-derived reachable
screen path; the current derived count is 43.

## Verification commands and outputs

### TDD red baseline

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/prototype-production-paths.tests.ps1
```

Observed before inventory/allowlist implementation:

```text
Prototype feature inventory is missing.
exit 1
```

This was the expected failure for the missing contract artifacts.

### Normal mode

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/prototype-production-paths.tests.ps1
```

Fresh output immediately before commit:

```text
path=lib/screens/add_vocab_screen.dart rule=direct-screen-http-access targetPhase=2 count=1
path=lib/screens/ai_tutor_screen.dart rule=canned-ai-response targetPhase=4 count=3
path=lib/screens/ai_tutor_screen.dart rule=simulated-device-result targetPhase=3 count=1
path=lib/screens/categories_page.dart rule=direct-screen-firebase-access targetPhase=2 count=2
path=lib/screens/categories_page.dart rule=direct-screen-plugin-access targetPhase=2 count=1
path=lib/screens/choose_mode_screen.dart rule=direct-screen-firebase-access targetPhase=2 count=1
path=lib/screens/ghost_shadow_duel_screen.dart rule=sample-user-history targetPhase=5 count=1
path=lib/screens/main_vocabulary.dart rule=direct-screen-firebase-access targetPhase=2 count=1
path=lib/screens/mastery_dashboard_screen.dart rule=sample-user-history targetPhase=5 count=1
path=lib/screens/object_scanner_screen.dart rule=simulated-device-result targetPhase=3 count=4
path=lib/screens/quiz_screen.dart rule=direct-screen-firebase-access targetPhase=2 count=2
path=lib/screens/select_category_for_quiz.dart rule=direct-screen-firebase-access targetPhase=2 count=2
path=lib/screens/select_wallpaper_screen.dart rule=direct-screen-firebase-access targetPhase=5 count=2
path=lib/screens/shadowing_challenge_screen.dart rule=random-fabricated-measurement targetPhase=3 count=2
path=lib/screens/shop_page.dart rule=placeholder-transaction-feature targetPhase=5 count=1
path=lib/screens/speak_to_text_screen.dart rule=direct-screen-plugin-access targetPhase=3 count=1
path=lib/screens/weakness_clinic_screen.dart rule=sample-user-history targetPhase=5 count=1
path=lib/services/ml_image_labeling_service.dart rule=placeholder-transaction-feature targetPhase=3 count=2
summary candidateFiles=196 knownDebt=18 matches=29 new=0 stale=0
```

Exit: `0`.

### Strict mode

Command:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/prototype-production-paths.tests.ps1 -Strict
```

Fresh output contained the same 18 finding lines and summary:

```text
summary candidateFiles=196 knownDebt=18 matches=29 new=0 stale=0
Strict mode: knownDebt=18
```

Exit: `1`. The exact comparison had zero new/stale findings; the only strict
failure reason was the documented non-zero known-debt count.

Combined verification gate:

```text
verification normalExit=0 strictExit=1 diffCheckExit=0
```

## Files changed

- `README.md` — links the active prototype inventory from Current prototype
  direction.
- `docs/prototype/feature-inventory.md` — 63-row truthful feature contract.
- `tool/cli/prototype-production-paths.allowlist.json` — 18 exact debt pairs.
- `tool/cli/tests/prototype-production-paths.tests.ps1` — bounded contract.

Initial commit statistics: 4 files changed, 580 insertions. Follow-up commit
statistics: 3 files changed, 194 insertions, 18 deletions.

## Self-review

- Recounted inventory rows: 63.
- Recounted allowlist pairs: 18; duplicate pairs: 0.
- Recounted rule distribution: `1/6/1/2/2/1/3/2` across the eight active
  debt rules, with zero mock-production-provider findings.
- Re-read every allowlisted production path and the bounded route/menu source
  used for inventory evidence.
- Confirmed the checker only reads tracked `lib/` Dart files and does not
  enumerate build output, `.dart_tool`, Gradle caches, or unrelated history.
- Confirmed output never includes regex match text or source values.
- Confirmed curated export cards, CEFR/starter packs, legitimate quiz/word
  shuffling, secure randomness, statistical sample terms, and the test-only
  mock ML implementation are not allowlisted.
- Confirmed the source-derived reachable production screen paths (currently 43)
  and all allowlisted feature IDs are asserted against the inventory.
- Confirmed `git diff --check` exits 0 and the committed worktree is clean.
- An independent focused diff review was requested after commit, but was
  stopped without findings when the parent requested immediate final handoff.
  The bounded self-review and task-gate evidence above are the completed review
  record for this task.

## Reviewer follow-up evidence

The later focused review reported one Important and one Minor finding. Both
were closed in `ae0b8c5`.

### SharedPreferences boundary

RED: the exact `categories_page.dart / direct-screen-plugin-access` allowlist
pair was added before changing the scanner. Normal mode failed as intended:

```text
Stale entry: lib/screens/categories_page.dart / direct-screen-plugin-access / targetPhase=2 / count=0
exit 1
```

GREEN: `shared_preferences` was added to the direct-screen plugin rule, and a
synthetic rule probe now fails the contract if that package is removed from the
rule. Normal mode then reported:

```text
path=lib/screens/categories_page.dart rule=direct-screen-plugin-access targetPhase=2 count=1
summary candidateFiles=196 knownDebt=18 matches=29 new=0 stale=0
exit 0
```

The allowlist now has 18 exact pairs, with
`direct-screen-plugin-access=2`. The inventory still has 63 rows and now
records the SharedPreferences boundary in the `library.categories` row and
direct-boundary summary.

### Markdown table coverage

RED: a synthetic inventory fixture mentioned a required ID and path only in
prose, while its sole real table row used different values. The first run
failed because the required table-parser API did not exist:

```text
The term 'ConvertFrom-PrototypeInventoryTable' is not recognized
exit 1
```

GREEN: the contract now:

- locates the exact 10-column inventory header and separator;
- parses only real table rows;
- reads feature IDs only from column 1;
- extracts paths only from the Evidence column;
- runs the prose-only synthetic fixture on every invocation;
- rejects malformed rows and duplicate feature IDs;
- uses the parsed-row coverage helper for the real allowlisted features and the
  source-derived reachable screens.

No tracked source is mutated by these self-tests.

### Final source-graph correction

The earlier literal 43-path test list is no longer an authority. The contract
now loads only tracked Dart sources and walks constructor edges recursively from
`app_router.dart`, `main_navigation_screen.dart`, `choose_mode_screen.dart`,
`profile_settings_screen.dart`, and `setting_screen.dart`. It resolves relative
imports plus this application's own `package:vocab_learning_app/` imports,
requires a public class declared by an imported screen file to be constructed by the current
source, and compares the resulting screen set with paths parsed from actual
inventory table-row Evidence cells.

No manual exclusion set is used. Hidden legacy/research/device screens remain
outside the reachable set because the bounded roots have no constructor path to
them. An in-memory graph fixture adds a constructed child destination while its
inventory row is absent and proves the coverage check emits exactly that
missing-screen error. The fixture matrix uses `ConsumerWidget`, `HookWidget`,
and an arbitrary project-base class, proving reachability is not coupled to
widget inheritance. The current source-derived count remains 43.

### Fresh follow-up gate

Commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/prototype-production-paths.tests.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tool/cli/tests/prototype-production-paths.tests.ps1 -Strict
git diff --check
```

Results:

```text
summary candidateFiles=196 knownDebt=18 matches=29 new=0 stale=0
normal exit 0

summary candidateFiles=196 knownDebt=18 matches=29 new=0 stale=0
Strict mode: knownDebt=18
Strict exit 1

verification inventoryRows=63 allowlistPairs=18 duplicatePairs=0 normalExit=0 strictExit=1 diffCheckExit=0
```

Follow-up self-review confirmed that the rule probe contains no emitted source
text, the table probe is entirely synthetic, actual coverage no longer uses
raw inventory substring checks, all 18 pairs are unique, and feature source
remains unchanged.

## Concerns

- Strict mode is intentionally red until all 18 documented debt pairs are
  removed in their target phases.
- Source-pattern contracts are deliberately conservative. A new flagged
  semantic marker requires review and either source remediation or a specific,
  justified allowlist pair; broad suppressions are not acceptable.
- Readiness is based on bounded source evidence at the Phase 0 baseline. It
  does not replace later emulator/physical-device, Firebase, Gemini, or signed
  APK acceptance evidence.
- One early `rg` command used a Windows-incompatible glob and failed once. It
  was corrected immediately by using a directory plus `--glob`; the error did
  not repeat and there was no retry loop or stalled progress.
