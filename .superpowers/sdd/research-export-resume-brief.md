# Resume bounded R4a owner lifecycle and export

Worktree: C:/Users/Phet/Documents/LexiQuest/.worktrees/research.
Read AGENTS.md (updated recovery rules). User explicitly resumed implementation.

Write scope: lib/features/export/**, lib/features/identity/domain/owner_lifecycle_manifest.dart,
lib/features/identity/data/drift_owner_upgrade_repository.dart,
test/features/export/research_lifecycle_export_test.dart,
test/features/identity/research_owner_upgrade_test.dart,
test/features/identity/research_lifecycle_fixtures.dart,
test/architecture/fitness_test.dart (only research inventory relevance),
.superpowers/sdd/research-export-resume-report.md. No commits.

Existing schema at v24 has exactly four research tables. Lifecycle manifest/deletion
order and typed owner-upgrade conflict implemented previously; export projections
are missing. Previous focused upgrade12passed; export5passed3failed.
Complete allowlisted personal exports for all four tables, including withdrawn and
tombstoned evidence where safe; coded responses only; reject malformed codes.
Keep motivation measurements, opportunity/behavior, retention, learning independent.
Never export signatures, issuer keys, consent/guardian/assent receipt references,
raw owner identifiers or guardian PII. Use existing archive patterns and manifest.
Deletion child-first opportunities/responses before runs/permits before assignment/
session/owner. Owner upgrades with signed research records must fail atomically with
typed conflict requiring explicit removal/re-enrollment; never silently delete or
rewrite cryptographic owner/assignment pins. Ordinary upgrade remains unchanged.
Read relevant SDS sections if needed: docs/adventure-motivation-mode/03-sds.md.

Shared worktree: crypto agent currently owns the Flutter/Dart test/analyzer slot.
You may inspect and prepare your bounded patch using known RED evidence, but ask
main for a test slot before starting any Flutter/Dart check. Do not invoke pub-get,
generators, full suites, repository-wide analysis or security scanners. Other agents
are editing research repositories; do not change those files or rely on WIP hooks.
Follow TDD/root-cause diagnosis and apply_patch. Complete focused regression after
slot grant, then release slot promptly. Record commands/results and exact changed
files in report; final under15lines.
