# Android production rollback playbook

Owner: LexiQuest release owner

Current local database: schema v10

Strategy: halt rollout and forward-fix; never downgrade the database or uninstall user data.

## Trigger

Start rollback when a staged build causes crashes/ANRs, owner-data corruption, authentication or sync rejection, material performance regression, or unexpected provider cost.

## Immediate containment

1. Halt the Play staged rollout. Do not promote the affected version.
2. If Cloud is involved, set the server cloud policy to disabled. Preserve Drift and the outbox.
3. If App Check is the cause, return Firestore enforcement to `UNENFORCED` while retaining evidence of the rejected build.
4. Do not uninstall the app, clear data, lower versionCode, or change `schemaVersion` to an older value.
5. Record the affected versionCode, APK/AAB hash, source commit, device and first failing journey.

## Forward-fix

1. Reproduce the failure against a copy of the affected schema v10 database.
2. Add a failing regression test before changing production code.
3. Preserve every existing migration and implement the smallest repair. A schema change requires the next ledger reservation and migration tests.
4. Build with a versionCode greater than every uploaded Play artifact.
5. Verify upgrade-in-place from the affected build, offline learning, restart, outbox recovery, account export/deletion and the original failing journey.
6. Release to an internal track, then a bounded staged percentage. Resume promotion only after the monitoring window passes.

## Cloud and rules recovery

- App Check rollback: disable enforcement, verify signed valid traffic, repair registration/configuration, then re-enable with a negative invalid-build test.
- Firestore rules rollback: deploy the last known-good version-controlled ruleset and rerun the emulator suite before live smoke testing.
- Cloud kill switch: keep local learning, progress, rewards and export available; never delete pending outbox rows as part of containment.
- Provider cost: disable the affected provider path and preserve a truthful unavailable/degraded state in the app.

## Required evidence

- Before/after artifact hashes and source commits
- Schema v10 upgrade/restart results with retained owner data
- Crash/ANR and failing-journey logs
- App Check/rules/kill-switch state transitions
- Play internal-track acceptance of the forward-fix
- Human owner approval tied to the replacement hashes

Rollback is complete only after the forward-fix passes the same release profile as the failed build. A lower versionCode, schema downgrade or data-clearing reinstall is not a production recovery.
