# S01-CD — fresh isolated native draft attempt

## Outcome

Obtain native synthetic draft/restart evidence for the existing D01–D05 contract on physical V2041/API33 using a new debug-only package identity. Preserve CB's two uncertain install attempts as historical uncertainty; never reclassify them as a single attempt. Keep the CB APK and seven earlier APK files/packages intact.

## Sequence and acceptance

1. Add a `nativeDraftCd` debug identity and separate Gradle output. Reuse the CB test-only activity, integration fixture and contract with explicit CB/CD identity validation. Production application identity and normal build behavior must remain unchanged. A source test must fail before implementation and pass after it.
2. Extend the runner to accept the CD identity only when explicitly selected, and preserve fresh-output collision, package collision, APK manifest isolation, seven protected metadata checks, install journal, at-most-one install per run, failure receipt and forbidden-command safeguards. Stub `adb/aapt` must cover CD success and transport failure without a device.
3. Run bounded host/CLI gates, focused analyzer, build the new isolated APK in its own directory, and record source/APK/prior-artifact hashes. Recheck transport and package absence read-only before any native write. Do not proceed if transport changes or integrity checks fail.
4. Run at most one native CD attempt with one install command and immutable output. If transport fails, preserve the failure receipt and stop native work. If it passes, validate the two phase receipts, actual process restart and protected package metadata; report only the scope actually observed.

No research activation, real participant data, external service, app deployment, real user trial, visual/IME/TalkBack claim, cleanup or changes to owner/schema/scoring/SRS/reward/route/gates. The CB uncertainty remains unresolved and cannot be used as CD acceptance evidence. No successor is dispatched from this package.
