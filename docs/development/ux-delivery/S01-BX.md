# S01-BX — recoverable engineering source snapshot

Canonical checkout: `C:/Users/Phet/.codex/worktrees/lexiquest-current/LexiQuest`; branch `codex/ux-current-after-s01-bc`. Controller: `01a0ce9e-23a6-7931-88e6-6390da748f39`.

## Scope and recovery

BD–BW source, tests, active documents and original checkpoint/evidence bytes are inventoried in `evidence/S01-BX-included-inventory.json`. Ignored BD–BW logs are explicitly included. Receipt paths have scoped `-text` attributes so original hash pins survive checkout. Git-normalized source blobs and original worktree SHA256 are recorded separately; normalization does not alter the existing local files.

`evidence/S01-BX-local-only-inventory.json` records paths, sizes and SHA256 of ignored artifacts retained in this canonical checkout. These bytes are **not on GitHub**. They include pinned BM/BW APKs, verification outputs, build intermediates, caches and local runtime configuration. No file is deleted, moved, archived, or copied into another checkout/ZIP. Recover a local-only artifact from its exact canonical path and verify SHA256 before use; rebuildable caches can be regenerated but do not substitute for the pinned historical APK/evidence. If this disk is lost, Git cannot recover those local-only bytes.

To inspect the source snapshot without changing any checkout, use `git ls-tree -r <snapshot-ref>` and `git show <snapshot-ref>:<relative-path>`. For a future full recovery, fetch the named backup ref into a separate authorized destination, then verify Git blob IDs against the snapshot tree. Recover original raw source bytes from the retained canonical checkout when a raw-byte hash differs from the normalized Git blob. Do not restore caches or overwrite active work as part of inspection.

The earlier `codex/backup/ux-v5-through-s01-bc-20260926` ref and its local overlay remain intact. This snapshot does not absorb old transfer archives or pretend that the old overlay is uploaded.

## Integrity and limitations

BW immutable checkpoint: 850 hash pins checked, zero mismatches before BX metadata changes. The previous state/README pins describe revision 149; new BX coordination metadata deliberately supersedes those active documents, never the old receipts. Secret scan and adjudication: `evidence/S01-BX-secret-review.json`. All 179 raw findings are SHA256 `commandKey` verification identities; no scan rule was weakened. Binary images are synthetic host test renders, not proof of native visual acceptance.

Only snapshot integrity checks are run here. Prior BW 11 host tests, 29 CLI checks and native committed-feedback resume PASS remain historical scoped evidence, not newly executed BX tests. No full Flutter regression, Android build, release verifier, native interaction, participant trial, provider call or deployment is run.

S01, UX-D01–25, native full Today/bootstrap, additional native resume cases, visual/IME/TalkBack, actual-user/learning trials and release acceptance remain open. Research and field gates are unchanged. No new app implementation, schema, scoring, SRS, reward, owner, route or deep-link change is introduced by BX.

Jev: no fresh billing; deterministic current-model fallback, Standard/default requested but runtime tier unverified. No Fast/probe/login/paid operation, quota reset or USD5 ledger change.

Source commit: `18f7fd6d5a2ad9e15e328f1018cba241438c81ef`; source tree: `41285465304aa804dba15fc961b86dd249775ee7`. Origin is `https://github.com/Phoomxo/LexiQuest.git`; canonical remote source ref was read back at that commit. The final coordination commit adds this report/state and immutable BX release receipt, and both canonical branch and `codex/backup/ux-v5-through-s01-bw-s01-bx-20260928` identify that exact final commit. Its hash cannot be embedded in its own tree; the local immutable `build/S01-BX/remote-confirmation.json` records the final commit/tree, both observed remote hashes and read-only restore checks. The backup ref is created once, without force, after the coordination commit.

Inventory: 693 content-bearing candidate files (40,376,226 bytes), plus 7 generated files whose changes were line-ending-only and were not manufactured into a source diff. Included inventory totals 700 paths. Local-only pre-existing inventory: 5,751 files / 3,594,793,522 bytes, including both pinned historical APKs. The first source commit changes 701 paths including new BX audit metadata. No staged archive, APK, keystore or user database; largest staged file is below 5 MiB. Git index and worktree were clean after source commit. All selected evidence bytes match their index blobs.

`git diff --cached --check` reports preserved historical whitespace/CRLF in immutable logs/patches; it is not a clean check and those records were not rewritten. With `core.whitespace=cr-at-eol`, historical whitespace remains (139 diagnostic lines). The focused BX documentation/attributes check passes. Additional generated metadata scans have zero findings. Source/application tests were not rerun because BX changes only checkpoint metadata.

Writer `01a0e634-e153-7953-a19d-0f29cbd8762c` releases sole-writing authority through `evidence/S01-BX-checkpoint.json` (state revision 150). Final publication consists only of committing/pushing coordination metadata and writing its one-time local confirmation; no application source writes follow release. Controller receives the final report in this chat; no successor dispatch.
