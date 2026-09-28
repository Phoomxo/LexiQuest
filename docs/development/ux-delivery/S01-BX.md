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

Final commit/ref verification and writer release will be recorded in the immutable BX checkpoint and local post-push confirmation. No successor dispatch is authorized for BX.
