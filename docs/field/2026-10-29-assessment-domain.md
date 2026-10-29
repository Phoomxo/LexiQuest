# Assessment domain component

Verified on 2026-10-29 after `02695b00` in
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`, branch
`codex/remaining-system-readiness`. This is a domain-only component, not an
active Assessment feature. Schema remains v16/34 tables; v17 is unreserved.

Three new domain files define immutable run/version pins, terminal exact replay
and conflict behavior, a score-free presentation, controlled instrument scoring
and repository ports. Supplied form authority must acknowledge the exact content
identity; returned length, SHA-256 and complete bytes must match the catalog's
controlled form semantics. Catalog review flags alone do not grant content
authority. No approved instrument, validity or efficacy evidence is invented.

The outcome DTO intentionally carries raw read facts. Later comparison must
reject owner/session/class/pin mismatches and incomplete pairs instead of
treating construction as verified outcome authority. Presentation option order
must remain deterministic when the future use case adapts canonical form data.

Actual checks: 79 domain cases pass; 125 combined domain/frozen-context,
eligibility, metadata and sync-contract cases pass; analysis finds no issues;
format/diff and independent review are accepted. The initial 78-pass/1-failure
run exposed a new fixture clearing fixed-length `utf8.encode` bytes. Mutating a
byte now proves the intended deep copy; all immutability assertions remain.
Logs are in the existing evidence directory, prefixed `assessment-domain-`.

Under the user's existing obsolete-file cleanup instruction, the unreachable
`lib/screens/thesis_chart_screen.dart` and its own smoke test were removed.
They used default52/88.5 scores, sample latency and fixed labels even for other
inputs. Connected-source search found no runtime caller; the old full suite
already passed, so removal was not used to obtain green tests. Exact paths were
validated inside this worktree and both files remain recoverable from pushed
`e0771624`. No participant data or dependency was deleted; `fl_chart` is retained.

No writer, UI, database migration, evidence-policy activation or Assessment
upload was added. Ordinary ingress still rejects assessment/research pins.
Evidence admission and byte-for-byte SRS/reward/Quest/Streak isolation must be
implemented before accepting assessment writes. Current runtime coverage stays
10 connected/19 partial/15 missing.

Latest full-suite/APK evidence is still `e0771624` (2869 tests, analysis0,
CLI23 and normal debug APK), predating this component. A newly grounded initial
opening ordering/crash gap is being corrected separately before presentation
switch capture; default production Research remains disabled. Local authority
adapter drafts are also separate. No new full-suite/APK/UAT claim is made here.

Automatic approval previously rejected owned disposable emulator/preview
stop/delete with `blocked by policy`; no retry was made. This component's two
source deletions succeeded and do not alter that retained-artifact disposition.
