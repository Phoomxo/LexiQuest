# E3.1 / F03 guided repair

Accepted locally: **366 tests / 13 bounded targets passed**. [Acceptance](post-g83-e31/acceptance.json) · [review and defects](post-g83-e31/defects-and-review.json) · [rendered preview](post-g83-e31/repair.png).

Committed incorrect lexical feedback now opens reviewed explanation/context, up to two hints and three assisted answers. A separate immutable operation history preserves assistance and the original answer; it never updates SRS, XP or coins. Reopening uses exact content/source validation, and unavailable content offers an exit. Optional consented AI help consumes a persisted hint and falls back to authored content on timeout; generated text never determines correctness.

The tradeoff is deliberate: a bounded authored repair is auditable and works offline, while provider help is optional display text. Example: an incorrect “station” answer followed by one hint and a correct spelling retains the incorrect original plus a guided-practice repair. Two hints/three attempts are engineering limits, not proven learning constants.

Schema31 adds owner-scoped repair operations with exact retry, immutable payloads and revision conflict checks. Checks cover a real SQLite close/reopen, guest transfer, owner export/delete, scoped history restore, future archive rejection, migration interruption/rollback, cancelled commit and research-off invariants. The lesson controller exposes acknowledged feedback without creating another answer. The 320px/200%-text preview uses real Thai fonts; device and screen-reader checks remain separate.

New files analyze cleanly; two inherited bootstrap informational notices remain. Generated-code audit: 11 new declarations, none removed, 581 unchanged, 12 expected database/owner/answer relation changes. Review is writer self-review, without an independent reviewer claim.

Completion benchmark is met for E3.1 only. Original12 scored admission remains; editorial5500 is not approved. Backup covers repair history and requires its canonical origin; it is not a full database restore. Rollback can omit the optional repair composition while retaining schema31/readers. Live provider/device/camera evidence is not claimed. Standard/default requested, effective tier unverified. Continue E3.2 next; retain E6 and every E7/G8.4–G8.9 gate.
