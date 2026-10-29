# Local Research authority adapters

Verified on 2026-10-29 after `ad6c695e` in the existing
`cycle12-release` worktree, branch `codex/remaining-system-readiness`.
Schema remains v16/34 tables; v17 is unreserved.

`LocalResearchAuthorityCache` implements the five existing permit, current-state,
participation-document, receipt and trusted-time ports. Only explicit refresh
can install a snapshot. All five reads use memory and a monotonic freshness
lease; they perform no SQLite or gateway IO inside a collection transaction.
Actual Ed25519/P256 signatures, owner/UID/auth generation, consent version,
protocol/instrument pins, revision monotonicity and immutable identities remain
checked. Failed refresh cannot restore the previous grant. Revocation,
withdrawal, owner changes, suspend intervals and clock regression deny capture.

The gateway is an explicit trust boundary, not an implementation of server
authority. It must independently authenticate current state and the request's
UTC/monotonic freshness mapping. No production gateway, issuer, lifecycle
composition, factory activation, enrollment or upload is supplied. A packet DTO
alone proves none of those prerequisites. Research stays default-off.

`DriftOwnerWriteCoordinator.hasAmbientTransaction()` uses Drift's supported
`runWithInterceptor` API and a read-only SELECT to inspect the actual executor.
Unknown/error states deny operations requiring their own committed boundary.
Refresh refuses an inherited transaction before gateway IO. The test gateway
uses an independent executor probe. This shared helper does not change owner
write, deletion-journal, schema or learning behavior.

Actual checks: 35 cache/real-runtime integration cases pass; the expanded
cache, owner-coordinator, deletion-fence and configured-quiz suite passes all
115 cases. Analysis reports no issues. Independent review accepted both the
adapters and the public transaction probe after reading installed Drift
2.34.3's executor/interceptor implementation. Logs are in the existing evidence
directory: `research-authority-adapters-final-green.log`,
`research-authority-owner-integration-green.log` and
`research-authority-public-guard-analysis.log`.

The initial integration failure was a fixture assumption: its helper answers
incorrectly, so it cannot prove rewards survive revocation. The strengthened
case answers correctly through canonical learning and checks the exact actual
point/SRS/one-coin facts while Research completion and post capture remain
denied. No reward implementation or assertion was weakened.

The separate initial-opening correction is still in progress. It must use the
shared transaction probe before a public Runtime command promises durable
pre-render preparation. These focused results do not attest that unfinished
path. Latest full-suite/APK evidence remains source `e0771624`: Flutter 2869,
analysis0, CLI23 and the normal debug APK. No new UAT or full-build claim.
