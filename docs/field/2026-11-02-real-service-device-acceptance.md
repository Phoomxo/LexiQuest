# Real-service and physical-device acceptance

Worktree: cycle12-release/LexiQuest. Branch: codex/remaining-system-readiness.
Starting source: c4ede833. Cloud A and Cloud Billing remain excluded. No public
rollout, real payment, enrollment, participant upload or ambient recording.

## Frame and evidence

The acceptance predicate requires actual configured provider/store responses,
physical-device behavior and genuine Research authority. Local fixtures cannot
establish those facts. The owner reply repeated the requested input categories
without a path, service identity or approved document. No provider/Play/Research
release input was established by that reply. Relevant process environment names
were absent; the bounded repository configuration discovery found examples only.
This does not prove that inputs do not exist elsewhere.

Current contracts are documented in billing-readiness.md and
research-transport-readiness.md. Store acceptance needs actual product/base-plan
IDs, authorized tester/track, registered identity and server verification. Research
needs approved instruments/consent and trusted issuer documents; engineering
cannot grant ethics approval or invent validated instruments. Keep these paths off.

## Physical baseline

Connected V2041/API33 has TalkBack and Google TTS. The official app was version18.
Root updated in place to the previously verified offline20 APK without clearing
data. Installed SHA256 matches
`d3220b4959534618183a2277360b23100aa257869f80206be532808b407189a0`.
The streamed install was slow but completed once; no duplicate install was issued.

Launch and guest entry work on the physical device. A bounded TalkBack probe
enabled its installed service, confirmed touchExplorationEnabled=true and that
LexiQuest remained focused, then restored enabled services=null and enabled=0.
This is service coexistence evidence, not complete screen-reader navigation or
audible-quality acceptance. No microphone or ambient recording was started.

The local vocabulary was empty. Root created the explicitly synthetic category
QA33-Synthetic for voice testing. Test data is not Research and must not be
silently deleted with existing user data. Physical captures may include the
device's unrelated picture-in-picture overlay; it is not application content and
was not acted on. Treat captures as local evidence, not publication assets.

## Confirmed defects and corrections

1. Native TTS ignored plugin rejection acknowledgements. FlutterTts4.2.5 returns
   numeric0 for rejected configuration or speak; the old adapter discarded it
   and the provider reported success. The real adapter/MethodChannel regression
   produced21PASS/6FAIL before correction. One shared check now rejects explicit0
   for all six operations. Existing safe failure and cancellation logic remain.
   Native1 and web speak null remain compatible. Speak still acknowledges start,
   not audio completion. Independent review ACCEPT. A corrected caller/voice
   suite passes416; an earlier command mistakenly included a nonexistent test
   directory, so that command is not a passing suite.
2. Add Category clipped its input/actions with a landscape keyboard on V2041.
   The844x390/IME230 regression reproduces a16pixel RenderFlex overflow.
   The first scrollable:true correction passed7 vocabulary journey tests but
   failed the later physical check below. It is superseded by final22.

The RED tests were committed before runtime corrections. Root owns serial Flutter
verification and physical actions. Model the Domain kept the existing plugin
acknowledgement shape; Prove It Works required actual plugin contracts, RED/GREEN
and device evidence. No schema, public interface or dependency was added.

## Integration status

Final regression and packaging results will be recorded in
`D:\LexiQuest-Storage\maintenance\2026-11-02\commercial-readiness\acceptance33`.
Do not infer that offline20 contains these new corrections. Source-level tests,
artifact evidence and human audible/device acceptance remain separate.

## Physical counterexample and correction, 2026-11-03

Source1aeeabae passed5572 tests with unchanged1350 inputs. Offline21 APK/AAB build,
signature/native/identity attestation and in-place Vivo installation passed. APK
SHA256 is b0727d93499c48ba378e695e3148923a8ffae588b46682fd5ab84448f2e3fc95.
Those facts did not establish layout usability: actual21 with the landscape IME
still exposed only18 physical pixels of the input. Fixed AlertDialog actions
reserved almost all vertical space. The earlier hitTestable assertion accepted
a visible sliver and therefore did not prove a readable field.

The replacement regression uses the production M3 theme/NotoSansThai font,
2408x1080 pixels at2.75 density, top77/left66/right182 padding and bottom643 IME.
Both Save and Cancel cases require at least48 logical pixels of visible field,
the full input text line, and reachable actions above the keyboard. Before the
second correction both fail with only10.909 logical pixels visible. The fixed
actions now sit inside the existing scrollable content with the field. Title,
PopScope, validation, pending-save guards and callbacks remain. The entire
vocabulary journey suite passes8. Final22 source/artifact/device evidence is
recorded separately under acceptance33/final22;21 is not relabelled as a UI pass.

The owner is currently unavailable for audible testing. No further speech playback,
TalkBack activation or microphone capture will be started in this run. The earlier
TalkBack service probe is explicitly version20 evidence. Device rotation was
temporarily set to landscape for the21 reproduction and restored to user_rotation0
and accelerometer_rotation1. The synthetic category contains hello/synthetic/
interjection; ordinary vocabulary remains separate from Research.

## Final22 integration and silent-device acceptance

Frozen implementation source: `4a77d81ad88310ebb5762313eaa2ec2f918a1cf7`.
Version `1.0.0+22`; build ID is that full source hash followed by `-offline22`.
Full Flutter5573PASS/0FAIL, with1350 inputs/1005 Dart files unchanged; analysis
reports no issues. Full log SHA256:
`6558430b2ee842d907a3b0ffe8be0992446367decd229c0e3e162074362d3958`.
Independent code review accepts the shared TTS boundary and the final category
dialog correction. No schema, dependency or frozen Research contract changed.

Both normal release builds completed. Independent bounded artifact attestation
accepts exact embedded identity, signatures and native pins across3 ABIs.
APK123238191 bytes, SHA256:
`3042856b6bbf8ea653da49461f4fe847b471c34233469ef87d00f0b0ef44f4f0`.
AAB109044575 bytes, SHA256:
`eb8f18ee1068cf98cc86fd893f997a81596fb66cccf94a44d6941d743a19da92`.
AAB JarFile and signed central payload coverage pass; manifest-last ordering
means JarInputStream is explicitly not attested. Original warnings are retained.
Offline feature switches are recorded in the build receipt; they are not inferred
from native metadata. No artifact was published.

The Vivo update completed once, preserved application data, and its installed APK
hash matches the retained artifact. Silent device acceptance then passed:

- Guest entry and the retained QA33-Synthetic/hello/synthetic/interjection data.
- Landscape keyboard input is readable. Actual swipes inside the dialog reveal
  both48dp-high actions above the still-open keyboard; no keyboard dismissal was
  used to obtain a passing result.
- Cancel with QA33-Cancelled22 creates no visible category. Save creates exactly
  one visible QA33-Keyboard22 category. These are bounded UI observations, backed
  by the regression's repository-write assertions, not a device database export.
- Rotation restored to accelerometer1/user0. Accessibility remains services=null,
  enabled0. No additional audio playback, TalkBack activation or microphone capture.

Evidence root:
`D:\LexiQuest-Storage\maintenance\2026-11-02\commercial-readiness\acceptance33\final22`.
Receipts: full-flutter-result.json, offline-release-build-result.json,
artifact-review/actual/artifact-attestation.json, install-receipt.json and
native-ui-result.json. Captures remain local because an unrelated overlay appears
on the device. The two synthetic categories are retained, not silently cleaned up.

## Remaining external acceptance and next executable steps

The authenticated Play Console opened its developer-account creation page at
`https://play.google.com/console/signup`, not an app/test-track console. This is
limited to the current signed-in browser account. No account creation, payment,
upload or account switch occurred; personal email is omitted from the receipt.
Provider configuration, approved Play track/tester/products and Research
protocol/consent/trusted issuer have not been supplied or found in the bounded
discovery. Do not fabricate them or describe fixture checks as real acceptance.

When genuine inputs become available, run the existing provider/Play acceptance
against their approved test environment, then bind its results to the artifact.
When the owner is available, resume human listening and full TalkBack navigation;
obtain microphone readiness before any recording. Research remains default-off
until its authority and rollout conditions are met. Cloud A and Cloud Billing
remain excluded. No public traffic, real charges or real enrollment was enabled.
