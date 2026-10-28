# Study-bound consent version

Source `2c94d4a34eb63c3a2b4b95fc49099df50f9b4b58`, pushed on
`codex/remaining-system-readiness` in
`C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`.
Schema remains v16/34 tables; no research enrollment or upload is enabled.

The consent use case binds one positive version, defaulting to the existing
version 1. Reads validate owner and returned version. Decisions validate the
requested owner/version before the repository's existing guarded write. Real
database checks prove withdrawing version 4 preserves version 1.

Settings displays the loaded version and rechecks owner, version, accepted state
and dependency identity after confirmation. Login/Register offer the existing
version-one notice only with a version-one use case, and pin that version when
recording a choice. A study-bound version 4 cannot relabel that notice or block
ordinary account access. Its approved notice/enrollment remains separate work.

Owner-change errors retain the exact existing cancellation contract consumed by
Export; a returned wrong version is unavailable. Two checks exercise the actual
use-case-to-Export path and prove neither data reader nor artifact store runs.

Five initial Settings failures exposed Future-returning `setState` callbacks
and failed status futures completing before FutureBuilder subscribed. Callbacks
now return void, and one read helper immediately observes the original future
while returning that same future to FutureBuilder. No fallback accepts consent
or replaces an error with old successful data. Withdrawal remains committed
when its later status read fails. All original failing assertions remain.

Current-source evidence: Settings 36 passed; consent/Settings/Login/Register/
Export integration 133 passed; consent/export/research/account/runtime integration
700 passed; analysis found no issues; format/diff checks passed. The change adds
23 cases and independent current-source review accepted it. Logs are under
`D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`, prefixed
`study-consent-`.

The latest full suite and normal APK remain source `4a4cbdd8`: 2728 tests and
the wave 8 artifact. They predate this bounded component; no new full-suite or
APK claim is made here. The next step integrates the frozen five-file final
visibility/Mission-event draft and runs its actual authority/linkage checks.
The study host, both presentations, assessment and upload remain engineering
work. Authentic authority, approved artifacts and physical UAT remain separate.

The two pre-existing critique documents remain untouched. Automatic approval
previously rejected the owned emulator/preview stop/delete command with
`blocked by policy`; it was not retried.
