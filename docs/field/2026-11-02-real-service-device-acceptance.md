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
   A single scrollable:true on that AlertDialog fixes it without changing save,
   owner or validation behavior. Existing vocabulary journey suite passes7.

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
