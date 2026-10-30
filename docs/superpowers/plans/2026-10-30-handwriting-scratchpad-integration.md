# Handwriting Scratchpad plan — f12 / P35 typed caller

**State:** root-approved API and ready after [Wave18](../../field/2026-10-30-remaining-systems-wave18.md):
source `29038b4add94bb83df19188b2562ed3ea7f11d1f`, cycle12
`codex/remaining-system-readiness`; Flutter4262/analysis0/CLI23/backend390+one existing opt-in skip
and normal APK are attested. D-only test-first drafts began on the frozen predecessor;
root will promote and execute the next concrete unit after committing/pushing this checkpoint. Schema20/37 stays unchanged; no v21 reservation,
dependency, OCR, persistence, evidence field or learning authority is proposed.

## Outcome and fixed authority

Use the existing P18→Cloze typed variant/category→TypedClozeSession→P35 path.
Offer an initially collapsed inline scratch area alongside the original
`cloze-response` TextField. Undo/Clear change ink only. Drawing alone never
enables Save; only the typed response enters the existing canonical answer/
finish/ACK lifecycle. After ACK, retain read-only ink beside the existing answer
for manual comparison, with copy stating that the result checks typed text,
not handwriting. No pre-answer reveal or stroke recognition is added.

This implements the frozen f12 purpose: local ephemeral handwriting/self-checking
without OCR or automatic mastery claims
(`alltcas_idea_integration_catalog.dart:256`; TOR:154/241/343).
Current clozeTyped guidedPractice/hint1, word/content/provenance pins, retry,
projection and outbox behavior remain unchanged. No new handwriting prompt,
self-rating score or Research enrollment/event is created. f03/f05 remain partial.

## Small public widget API for first review

```dart
HandwritingScratchpad({
  super.key,
  required bool Function() canEdit,
  String languageCode = 'th',
});
```

The widget imports Flutter drawing/gesture UI only, never LearningUseCases,
owner/database repositories or AppDependencies. No controller, enabled duplicate,
recognition callback, submit event or serialization API is necessary.

Typed P35 supplies `key: ObjectKey(widget.session)` and
`canEdit: () => _canAnswer && _pendingAnswer == null`. This must be a **live**
read of the parent state/epoch, not a closure over a previously captured bool.
Every pointer and Undo/Clear callback rechecks canEdit at invocation, including
retained callbacks after owner/route loss before the next frame. Build may read
it for enabled styling but cannot use that cached result as authority.
Hidden/collapsed surfaces also reject editing; the view toggle remains usable
for read-only comparison after ACK.

A newly created closure during ordinary rebuild/IME is not a new binding:
never compare function identity or reset ink for that reason. Session identity
changes dispose/reset through the key. Parent invalidation removes the pad;
the generic widget cannot distinguish owner loss from an ordinary input freeze
and must not invent that authority.

## Bounded local state and interaction

Store normalized finite points with64strokes/4096total accepted points maximum.
One active pointer ID owns drawing; secondary pointers cannot add/end its stroke.
Support normal touch/stylus/mouse without palm-rejection/recognition claims.
Clip painting to a modest bounded canvas and reject invalid/zero-size geometry.
Normalized coordinates preserve draft through ordinary resize/IME; no raster or
per-pixel buffers. An explicit paint version/snapshot drives repaint reliably.

At a limit, retain existing ink, reject extra samples visibly and allow Undo/
Clear to free capacity. Undo removes the latest stroke; Clear erases only ink,
never the typed controller or saved facts. Retire active pointer capture when
editing becomes blocked; retain its last accepted points for comparison. A late
move/up or old control callback cannot mutate ink after canEdit becomes false.

Canvas input claims drawing only inside its bounds. Preserve outer ListView
scrolling from the rest of the page and keyboard-only typed operation. A compact
expand/collapse control may hide the surface while keeping same-attempt ink in
local state. It must not add a modal route or destroy the draft when the IME
opens. Keep prompt, typed answer and CTA reachable; no huge canvas at200% text.

Use theme ink/surface contrast, labelled empty/limit state and Undo/Clear focus/
Enter controls. Do not announce every point or present meaningless recognized
text to TalkBack. Typed fallback is always available without drawing. No animation
is needed; Reduced Motion must remain respected.

## Parent privacy regression before the bounded fix

Current `FillInTheBlanksScreen._invalidate` (:146) synchronously clears its
TextEditingController and calls setState; the owner listener (:98) can invoke it
during persistentCallbacks. Add the cheap actual RED first: stable direct sync
owner stream, accepted typed round with ink/text, then ancestor Builder emits
null→same owner during a frame. Require no build exception, immediate live
canEdit=false, hidden old-owner pad/text, no later pointer/control restoration
and zero extra canonical facts.

If reproduced, change **only this P35 widget's affected redraw path**:
set sticky invalidation/epoch/selection fields synchronously before controller
listeners or rendering, then clear controller and redraw safely after-frame when
inside persistentCallbacks. Keep idle behavior, final owner/current guards and
frozen commands unchanged. Cover initial/current owner delivery as needed by the
same regression; do not build a global native screen framework or sweep siblings.
Root must observe actual RED/GREEN before this becomes a claimed fix.

## Exact write set and test order

1. New `lib/widgets/handwriting_scratchpad.dart`.
2. Existing `lib/screens/fill_in_the_blanks_screen.dart`: typed branch only,
   live guard/key integration, scoped cleanup and the proven local redraw fix.
3. New `test/widgets/handwriting_scratchpad_test.dart`.
4. New `test/screens/typed_cloze_scratchpad_test.dart`, reusing the existing real
   Cloze harness; a unique test-only ACK helper may be added if no public equivalent exists.
   Preserve `fill_in_the_blanks_screen_test.dart` assertions;
   adjust only meaningful layout interactions if tests require it.

Freeze the widget API first, then test-first drafts, actual parent/frame RED
and focused GREEN. No chooser, bootstrap, repository, schema/inventory, model,
policy, field-set or network-source change belongs in this card. Root remains
the sole C writer and serialized Flutter executor.

## Acceptance before wider attestation

- Actual pointer strokes/dots render; single-pointer ownership, Undo/Clear,
  collapse/expand, resize, point/stroke limits and repaint behave deterministically.
  Retained handlers after live canEdit=false do nothing; closure replacement
  during IME/rebuild preserves the same-session ink.
- Draw/Undo/Clear alone leaves the already-started real DB snapshot unchanged.
  Empty text cannot save despite ink. Typed save/finish retains exactly one
  original canonical answer/outbox/profile/end; raw strokes never enter wire,
  export, preferences or logging. ACK loss/freeze cannot mint a new command.
- Owner null/ABA/error/done, dependency/session replacement, cover/hidden route,
  pause/dispose and late pointer-up clear/hide privacy without setState errors.
  A new attempt/restart has no retained ink. No authority or recognition is
  inferred from the drawing.
- Thai/English320px/200%, real IME, Tab/Enter and outer scrolling keep prompt,
  typed response and Save/Finish reachable. Flush pending layout **before**
  measuring/revealing controls, preserving physical hit-testing after the P34
  stale-layout lesson; do not hide failures with skipOffstage:false.
- Keep existing choice-Cloze/native/data/projection/owner tests intact. Root
  completes independent review, focused/wider checks and the next frozen-source
  regression/build. No physical stylus/TalkBack, efficacy or production claim.

No blocking product decision is needed for this aid+typed-ACK slice. Standalone
ink scoring, OCR, pre-answer reveal, retained/exported ink or broader writing-mode
calibration is outside it. No Pair Matching or claim that all f13/f05 work is done.

## Review and execution board

- Root promoted test-first drafts after the Wave18 checkpoint was committed/pushed.
  The old P35 frame regression first needed three compile-only fixture corrections;
  actual RED then proved TextEditingController.clear/markNeedsBuild during a sibling
  build and an old enabled input after null-to-same owner delivery. The bounded P35
  sticky invalidation/deferred redraw and owner-start-after-frame fix passes the
  same case without suppressing exceptions. Other native writers remain unchanged.
- Widget API RED1 preceded source promotion. In-memory raster awaits moved into a
  bounded real async zone; pixel assertions still crop only the actual canvas.
  Measured pan RED captured outer offset84 becoming124 while drawing. Canvas-only
  EagerGestureRecognizer passes the unchanged physical gesture with relative
  baseline equality and an outside-scroll control; read-only canvas has no eager
  recognizer. Limits64/4096 and live editing guards remain unchanged.
- The clean four-module run passes80 tests, including18 generic widget cases,
  17 actual Typed Cloze cases and existing Cloze/chooser tests, with no warnings.
  Legacy scroll helpers now select the real outer P35 list, flush layout and use
  list padding; the held-ACK test uses bounded frame pumping while its progress
  indicator intentionally animates. Assertions and choice-Cloze behavior remain.
- Final analysis reports0 issues after six test-only style/import corrections.
  Production review and clean validation follow-up ACCEPT; source hashes for
  widget/parent are EBB1AFD7B8F1F85AAAD1D2EB65D97A98189DC4E23D092215033BF6176D390C2F
  and EBD98CFDF1F326FEB3C8ACF194989C3BAC481424840E0BE2A0D43C074848FFF0.
  Full current-source regression/backend/CLI/build attestation is next; f12
  classification changes only after that evidence. Schema20/37 and v21 remain
  unchanged/unreserved, with no production Research or physical-UAT claim.
