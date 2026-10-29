# Study opening commit order and crash recovery

Verified on 2026-10-29 after `f66d771c` in the existing `cycle12-release`
worktree, branch `codex/remaining-system-readiness`. Schema is v16/34;
v17 remains unreserved.

The initial Host rendered Standard/Adventure before its opportunity INSERT
committed. A persisted unpresented opportunity was also reusable after restart,
although the previous process might already have shown its treatment. Four
actual behavioral RED cases reproduced both problems before implementation.

Host now prepares and acknowledges the durable opportunity before allowing
either target renderer. A synchronous marker records potential rendering
before setState. Only the same in-process opening can capture its first actual
frame. Fresh authority and the final visible binding still must pass; the
opening identity grants no collection permission. Route, owner, lifecycle,
rebind and disposal invalidate an unfinished opening.

A known pre-frame lost acknowledgement can reconcile its exact prepared fact.
After possible rendering, failure or restart makes an unresolved opening
unavailable. It cannot mint a replacement, backfill Presented, substitute an
index or infer that no exposure occurred. A committed Presented fact can be
reconciled without another event. SQLite is never held across a UI frame.

Independent review additionally found that a public Runtime action could
inherit an external transaction and return before its outer commit. All public
Runtime writes now use the shared actual-executor probe before changing the
opening map or capture phase. Actual outer-transaction regressions verify zero
opening/render permission and zero premature Study-start sync notifications.
The optional learning observer keeps its existing nested savepoint behavior.

Actual focused checks pass all117 cases: Runtime55, Host19, two real
LocalStudyRuntime UI flows, six opening-order cases and35 authority cases.
All19 prior Host regressions and exact canonical learning/reward/outbox facts
remain covered. Analysis reports no issues after adding four required brace
blocks; formatting changes no files. Independent review accepted the code,
transaction correction, migrated callers and actual117-pass log.

Logs in the existing evidence directory include
`study-opening-order-behavior-red.log`,
`study-opening-authority-first-green.log`, `study-opening-analysis.log`
and `study-opening-analysis-clean.log`. Expanded integration passes all1147
Research, learning, identity, bootstrap/runtime, ChooseMode and Settings cases
on the final source, logged in `study-opening-expanded-integration.log`.

This unit activates no production factory, enrollment, upload or switching UI.
PresentationChanged and Assessment evidence isolation remain engineering work.
Latest full-suite/APK evidence remains `e0771624` (Flutter2869, analysis0,
CLI23 and normal debug APK). No new full-suite, build or physical UAT claim.
