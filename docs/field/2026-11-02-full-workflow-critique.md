# LexiQuest full feature and workflow critique

Method: design review only (detector not applicable, native platform)

Baseline: `0b7d7f53`, `codex/remaining-system-readiness`. Target: `lib` and its
connected backend/test contracts. Android Operate mode. Root inspected four
committed compact large-text renders and their current test definitions; three
disjoint source reviews cover all44 features. This is not a physical-device or
all-screen visual acceptance certificate. Cloud A and Cloud Billing are excluded.

## Feature coverage

- [f01-f16: catalog and learning](2026-11-02-critique-f01-f16.md).
- [f17-f30: feedback, review, analytics and motivation](2026-11-02-critique-f17-f30.md).
- [f31-f44: personalization, local operation and history](2026-11-02-critique-f31-f44.md).

Each review distinguishes inspected implementation, hypotheses and external
acceptance gaps. Connected means there is a composed local path; it does not mean
every device, provider, research authority or commercial journey has passed.

## Assessment before fixes

The design has product-specific strengths: Thai learning vocabulary, an ordinary
learning path independent of Research, and explicit answer/save acknowledgements.
The four viewed renders make the next review/practice action visible at large
text. They do not establish the visual quality of every screen. The main weakness
is continuity at transitions: keeping a selected date, retaining an unsaved plan,
and protecting a provider credential when a request changes destination.

Heuristic scores below are reviewer judgments from source plus the four renders,
not measured usability results. All ten heuristics apply to this Operate surface.

| Heuristic | Score /4 | Reason |
| --- | --- | --- |
| System status | 3 | Pending, saved, unavailable and report receipt states are explicit. |
| Familiar language | 3 | Thai actions are generally clear; Definition feedback incorrectly says translation. |
| Control and freedom | 2 | Profile exit/reload can discard a draft; reproduction required. |
| Consistency | 3 | Shared learning shell and owner contracts; calendar toggle changes the anchor. |
| Error prevention | 2 | Strong owner/evidence guards, but BYOK redirect forwards a synthetic credential. |
| Recognition | 3 | Due/weakness recommendations and source context reduce recall burden. |
| Efficiency | 3 | Resume, saved words and retained complete model files support repeat use. |
| Minimalism | 2 | Recall ladder exposes eight actions; effect on users needs a rendered task study. |
| Error recovery | 3 | Immutable retries and honest uncertain outcomes; exit continuity has gaps. |
| Help | 3 | Explicit hints and explanations preserve assisted-answer classification. |
| Total | 27/40 | Useful local product foundation, with transition defects to close. |

Priority findings:

1. P1, BYOK transport: `GeminiRestGateway._send` follows redirects by default.
   Root reproduced GET302 from127.0.0.1 tolocalhost with a synthetic key using
   two local HTTP servers. The redirect target received one request and the key,
   and validateKey accepted its response. Fix the shared transport boundary for
   both validation and tutor generation; retain safe failure responses.
2. P2, calendar: week→month→week derives the new week from month end rather than
   the original selected date. Preserve one date anchor through view changes and
   test month navigation, leap dates and owner invalidation.
3. P2, learning profile: dirty form has no exit guard; explicit reload also
   replaces the draft. Confirm discard, retain edits on cancellation and prevent
   unresolved saves or stale owner dialogs from causing unintended transitions.
4. P3, shared quiz feedback: Definition uses translation-specific wrong-answer
   copy. Use content-neutral correction guidance while preserving acknowledgement.

Recommendations use Impeccable harden for transition/transport failures and
clarify for feedback. No redesign or new authority is justified by these findings.

## Whole-app workflow review beyond the catalog

| Workflow | Inspected source and acceptance boundary |
| --- | --- |
| Launch→guest/account→ordinary learning | login_screen.dart and login_guest_mode_test.dart cover single-flight entry, validation, disposal and optional Research choice; live identity remains unverified. |
| Catalog→setup→answer→feedback→review/history | f01-f22 and f42-f43 use the canonical learning writer; assistance, drafts and acknowledgements stay distinct from mastery. |
| Goal→practice→calendar→next action | f25/f26/f35/f36 share owner-scoped profile and progress; date/exit fixes address continuity. |
| Learning→quest/streak→achievement→share | f29-f34 validate canonical sources and use the reward authority; native destination delivery is not proven. |
| Offline files→cancel→retry→activate | local31 already fixed cancellation/EOF retry; current regression must retain that behavior. |
| BYOK settings→consent→validation→Tutor | Gemini settings/use cases retain owner scope and cancellation; redirect transport defect is reproduced with synthetic data only. |
| Settings→export→cancel/save | ExportCenterScreen and export use cases separate personal and Research selection, owner checks and cancellation; actual external save destinations need device evidence. |
| Settings→account deletion | Exact confirmation, reauthentication and local/cloud stages remain distinct; no real deletion is performed. |
| Subscription→quota→ordinary learning | Billing runtime/UI preserve disabled purchase behavior and free offline scope; actual Play transactions remain unverified, separate from excluded Cloud Billing. |
| Research opt-in→authority→pre/post→withdraw/export | Source reviews retain signature/consent/owner gates. No enrollment, real upload or efficacy claim is authorized. |

For first-time users, the profile exit and Definition copy are concrete friction.
For distracted mobile users, calendar continuity and draft retention matter most.
For assistive-technology users, viewed large-text layouts are useful evidence but
physical TalkBack, keyboard, native dialogs and platform announcements remain
untested here. No visual detector or browser overlay was run on native Dart.

Eight visible Recall Ladder actions and technical report metadata are observations,
not proven functional failures. Do not silently hide available modes or remove
source evidence merely to reduce the number of controls. These require a focused
rendered task check before any further design change.

Questions skipped: the owner explicitly authorized critique-driven implementation;
no product choice is needed for the four bounded fixes. External authority and
device limitations remain explicit instead of being fabricated as completed work.

## Implementation disposition

All four priority findings are implemented. Shared Gemini transport disables
redirects; the real loopback reproduction changes from one credential-bearing
target request to zero. Calendar keeps a civil-date anchor through view toggles,
month clamps and Today. Profile Back/reload confirms draft replacement, blocks
busy saves and preserves uncertain retry identity. Quiz feedback is content-neutral.

Root reproduced the failures before implementation. Baseline full Flutter passed
5541 cases. Current focused AI/calendar/quiz checks pass157 and profile/domain/
integration checks pass37; these suites overlap and are not a unique combined
test count. AI backend passes522. Independent reviews accept the final source.
The first profile run exposed test-driving mistakes after keyboard/dialog changes;
tests now pump pending widget updates and scroll controls into view, without
weakening their behavioral assertions. Failed and successful logs are retained.

Full final-source regression, packaging and rendered acceptance are recorded in
the completion receipt under
`D:\LexiQuest-Storage\maintenance\2026-11-02\commercial-readiness\critique32`.
Do not treat focused results or this document as proof those later checks passed.

## Final integration and rendered checks

Source commit `100989e79b17e6706d5c6468bf52525072c96a4b` passed the complete
Flutter suite: 5563 passed, zero failed, with all1350 input files unchanged before
and after. Static analysis reports no issues. AI backend passes522; Voice CPU
passes82 with one real integration case deselected. No live provider was called.

Normal `lib/main.dart` release APK and AAB version `1.0.0+20` both build successfully.
Independent artifact review accepts signatures, full embedded build identity,
three native ABIs, pinned libraries, manifest metadata and source/test bindings.
APK SHA256 is `d3220b4959534618183a2277360b23100aa257869f80206be532808b407189a0`;
AAB is `b09e56d3f3e43d93bae0442aedbca70bd6133d8c764000db4196c4652b6773f6`.
Build logs retain Kotlin/SDK-version warnings. AAB signature evidence uses JarFile
and signed-payload coverage; JarInputStream verification is not attested. Disabled
service flags are bound to the reviewed build command and receipt, not decoded
independently from optimized AOT booleans. No package was published.

Root installed that exact APK as an update on read-only synthetic AVD
`LexiQuest_Commercial_27`, serial `emulator-5580`, Android API35, font scale1.0,
airplane mode with no active default network. No data clear or physical-device
action occurred. App Back and Android Back both display draft confirmation;
Stay retains `QA32-draft`, while explicit discard returns to the original empty
profile on reopening. Calendar week27Oct–2Nov → November → week27Oct–2Nov keeps
its anchor; Previous and Today work. The prior18 synthetic answers remain visible.
Screenshots/XML and assertions are retained in `native-ui-result.json`.

The first launch encountered an Android System UI not-responding dialog; Wait
recovered it and the app checks then passed. This is retained as an environment
limitation, not silently counted as a clean launch. One intermediate capture named
profile-reopened20 still shows Calendar because navigation actions were issued
too quickly; the separately captured profile-reopened-confirmed20 proves the
actual reopening. The task-owned emulator was stopped after verification.

Visual follow-up confirms readable dialog actions and calendar hierarchy. Some
progress/quest copy remains English within the Thai interface; localization
consistency is a polish observation, not a newly demonstrated persistence or
workflow failure. Recall Ladder density still needs a focused usability study.
The27/40 pre-fix judgment is not retroactively increased by test results.

All four confirmed findings are closed for this bounded engineering iteration.
All44 features have a review disposition; this is not certification that every
screen/device/provider works in production. Physical TalkBack/stylus/audio/native
destinations, live provider and Play acceptance, and Research authority remain
separate. Cloud A and Cloud Billing stay excluded. The completion receipt and
independent artifact review are in the critique32 evidence directory above.
