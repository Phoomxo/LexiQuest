# Non-paid trial implementation and acceptance

Worktree: cycle12-release/LexiQuest. Branch: codex/remaining-system-readiness.
Scope excludes real payments, Cloud A/Billing, public publication and real Research
enrollment/upload. Listening remains deferred by the owner. No microphone, speech
playback, TalkBack activation or camera capture was performed in this run.

## Implementation and review

`1bb6d3a4` introduces an explicit `offlineTrial` packaging profile and improves the
content-report Inbox. The profile uses a canonical three-field configuration and
source/config-bound build ID. Sync, billing, remote reports, Google sign-in,
account deletion/export authority and App Check debug are explicitly false; AI
and Voice service origins are empty. Existing connected/public profiles retain
their checks. Offline packaging does not establish connected or Research acceptance.
The Inbox shows the existing target kind and device-local date/time. Exact UTC
and the immutable original JSON remain available through deliberate expansion.
No report payload, owner boundary, transport or retry identity changed.

Actual packaging exposed a nested-object failure that the initial fixtures missed.
The shallow manifest cast left its configuration as an OrderedDictionary while
the validator required parsed JSON. `be5e7668` fixes the final validation boundary
by reading the actual written manifest through the existing strict JSON parser.
The regression executes the real packager validation expression against that
nested shape. It failed before the fix and passed afterward. No validation was
weakened. The first generated package/log are retained as failed-run evidence;
only final-package is the accepted deliverable. Independent reviews ACCEPT both
UI/profile implementation and the serialization correction.

Correction to the preceding status answer: an empty remote catalog does not mean
no bundled content. The existing12-word starter pack was already composed into
the catalog and tested. This run reuses and verifies it, without duplicating it
or claiming editorial/CEFR certification. Its review-pending disclosure remains.

## Verification lineage

- Focused Inbox/starter tests: 28 passed. Static analysis: no issues.
- Full Flutter on `1bb6d3a4`: 5575 passed, 0 failed. All1350 inputs were unchanged.
- Final source `be5e7668bfdf564c72d933c409b648e7c593e5a3` changes only the packager
  and its CLI test. Independent hash/Git comparison confirms1348 other inputs,
  including all1005 Dart files, unchanged. Original full receipt is not relabelled.
- Final configuration suite:150 passed on PS5 and PS7. Root retained PS5 log.
  Existing field-release suite:237 passed. No backend runtime change occurred.
- Actual normal APK/AAB builds and final package command pass. Independent
  artifact checks accept exact build identity, trusted signature, native pins,
  configuration and source/test lineage. JarFile/signed payload coverage passes;
  JarInputStream is not attested because the AAB manifest is last. Warnings remain.

Version: `1.0.0+23`. APK SHA256:
`e2f90e28a4f76509472fb1dbcf069976e18d0ee82a3eb8a5c9ad061d3ac5f5a0`.
AAB SHA256:
`5dd148b89673f471c7b1b3c6d4dbfac5b0f08f8c4e5295ec68e28e8ca61d213c`.

Evidence root: `D:\LexiQuest-Storage\maintenance\2026-11-03\nonpaid-trial34`.
Accepted artifacts: `final-package\lexiquest-1.0.0+23`.
Key receipts: full-flutter-result.json, test-lineage.json,
artifact-review/artifact-attestation.json, device22-result.json,
reminder22-result.json and the final device/installation receipts.

Reproduce packaging from a clean relevant source snapshot with owner signing:

```powershell
./tool/cli/package-field-release.ps1 -ReleaseProfile offlineTrial -Version 1.0.0+23 -OutputPath <fresh-output-directory>
```

This command does not deploy or publish. ConfigurationPath is rejected for this
profile; supplying connected service settings cannot silently enable them.

## Bounded physical checks before update

Version22 on Vivo V2041 passed starter12 installation, one-question Definition
completion, 1/1 History readback, Android CSV save/readback and cancelled export.
The saved2831-byte CSV has the same SHA256 on device and local readback. Tab/Enter
opened the menu and History. Notification permission denial preserved disabled
settings; leaving and reopening discarded the draft time/zone. Permission flags
were restored to their initial ungranted state. No notification was scheduled by
a successful enabled setting. Delivery/reboot/battery-policy acceptance is separate.

The model panel reports its installed model ready. This is not fresh camera or
inference acceptance. Camera/microphone remain ungranted. A synthetic local report
marked QA34-synthetic-test-only is queued with sending disabled. A Matching round
was deliberately left at2/4 acknowledged pairs for the update/resume check.
The starter words, synthetic answers/report and exported CSV are retained;
existing QA33 data was not cleared. Captures are local evidence only because an
unrelated picture-in-picture overlay appears on the device.

## Installed version23 acceptance

Accepted version23 was installed in place over22 on Vivo V2041/API33. The
installed APK hash equals the accepted package; no application data was cleared.
The original Matching round resumed at2/4, completed at4/4 and displayed100%,
4 correct and0 wrong. History retained the same07:52 start, recorded completion
at08:07, preserved Definition1/1 and the older unfinished Shadowing record.
Home now reports zero resumable rounds instead of one. Existing categories and
the installed starter pack remain present.

The pre-update synthetic report retains its identifier, comment and source
snapshot. Inbox shows `03/11/2026 07:35` as device time and the source-kind label;
expanded details retain `2026-11-03T00:35:36.710Z` and the original manual hello
snapshot at revision1. Both sending and receipt checks remain disabled. Visual
inspection confirms the changed content is readable at the existing settings;
this is not complete accessibility acceptance. Accessibility remains disabled
with no enabled services. See install23-result.json and device23-result.json.

## Remaining acceptance, not fabricated completion

| Area | Disposition |
| --- | --- |
| Real provider and BYOK | Interfaces/tests exist; no approved endpoint/key location was supplied or found in bounded repo/environment discovery. No live generation is claimed. |
| Native voice/TalkBack | Listening deferred by owner; full navigation/audio/recognition still unverified. Do not start recording without readiness. |
| GPU Voice | Existing secure runtime guard stays intact; no approved compatible runtime or real model acceptance is invented. Native TTS remains the ordinary fallback. |
| Notification delivery | Denial/restoration verified; enabled delivery, reboot, timezone/clock changes and battery policy still need device acceptance. |
| Native destinations | CSV save/readback/cancel verified; PDF/Anki destinations and external share recipient delivery are not newly certified. No message was sent to another person. |
| Camera/stylus/accessibility | Model-ready UI and keyboard navigation are bounded evidence; camera inference, physical stylus/palm behavior, complete TalkBack/contrast/large-text UAT remain. |
| Connected account/sync/reports | Deliberately disabled in offlineTrial. If included later, use genuine approved services and synthetic end-to-end acceptance; Cloud A is not implicitly resumed. |
| Research | Engineering contracts remain; actual protocol/instrument/consent/issuer and rollout authority are absent. Optional/default-off, with no ordinary-learning dependency. |
| Content/UX | Starter content exists with honest provenance; editorial validation, broader licensed curriculum and user comprehension remain separate. Existing English/Thai mixed copy and ladder density are observations, not certified usability. |

All44 catalog capabilities remain connected locally. This report does not turn
bounded checks into all-device/all-service acceptance or a percentage of readiness.
