# PM8 composition oracle correction — final bounded review

Reviewed 2026-09-07 in `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`, branch `codex/pair-matching-pm0-pm8`, HEAD `94c1e97fea5097af144b63adfdf9ab2e5f277bee`.

## Identity and scope

Verified raw SHA-256:

- Oracle-only diff: `4b71f135df7deb1e8f04cdc42583079733d02437da94d0470703b9d0e1b74cbe`.
- Twelve-file manifest: `a480d80738f5e443dfb35304c1da587399ac9cbf14ced6e306c6b5df339560d8`.
- Full twelve-file diff: `027c729e74003d5ff155a2eb024d8601e336caad55d1177609f22bc892a6c158`.
- New measurement test: `ca49536057f35c00415df000b1973917af8a75ca16cbfadb43c6e887f8499179`; saved before-file: `69b904a68e74e13b53692c4cca736da71aaf87b1f7256596407b6e3b3f3d39e4`.

All 12 current raw hashes match the new manifest. All prior 11 hashes are identical to the already approved packet. This review reads the complete measurement-test delta and its named policy, assigned-state provider, projection rebuilder, event/decision receipt reader and unchanged Replay/no-research checks. The earlier report `.superpowers/sdd/pm8-composition-review.md` is preserved. No source/test/portable-document/Git writes or Flutter/Dart/pub/build/scanner commands were performed by this reviewer.

## Findings and resolution

**Resolved P2 — the measurement oracle conflated normal Pair learning with Practice Replay.** The post-normal-Pair SRS snapshot must still exactly equal the populated prior-recall baseline. Points now require the complete prior ledger plus precisely one canonical point per correct, protocol-eligible recognition attempt; exact IDs, owner, idempotency key, entry type, amount, source and occurrence timestamp are asserted. Wrong and guided attempts add no points. At least one eligible correct attempt is required, avoiding an empty-set success. This follows the unchanged canonical recognition `protocolControlled` XP policy and actual rebuilder behavior; it does not disable or replace production rewards.

The helper requires a validated existing source event and existing validated canonical decision receipt for every Pair attempt. Inspection of `requireExistingDecisionSetForAttempt` confirms that missing receipts throw before the code path capable of inserting one. The helper independently asserts recognition XP is protocol-controlled, guided XP denied, and mastery/SRS denied. It cannot manufacture a missing receipt to make the test pass.

**Resolved P2 — expired/denied Motivation participation incorrectly implied Legacy learning evidence.** The updated assertion checks the fixture's existing enforced declared evidence authority, protocol and experiment versions, exact assignment/cohort, research-consent version and engagement flag. It also excludes form/instrument identity from Pair answers. Motivation permit availability is separately denied in these cases; the tests retain immutable accepted configuration and zero Motivation runs/responses/opportunities/events plus actual default-off and enabled synthetic enqueue/claim checks. Production policy, consent, signatures and upload authority are unchanged.

The full `_primaryEffects` equality immediately before versus after the actual Practice Replay action remains unchanged, including learning/economy/progress/configuration/assessment and research effects. The legitimate normal Pair delta is captured before that baseline, so Replay still cannot create additional primary effects. No assertions were replaced with skip, broad allowance or unchecked subset matching.

## Verdict and verification limits

**Spec: PASS. Quality: PASS. No open actionable findings in the combined frozen 12-file composition correction.** The prior 11-file approval remains applicable, and the separate measurement P2 follow-up is now closed by this delta.

Focused measurement-file `git diff --check` exited 0 (only Git's existing LF-to-CRLF notice). The root-owned 17-test measurement run `.superpowers/sdd/pm8-composition-measurement-20260907T043242631.log` was still running when inspected; its partial output was not treated as a final pass. Root owns completion metadata, analysis, the final source commit/fingerprint, full default/serial gates and APK. This bounded source verdict does not claim those pending checks passed or authorize rollout.
