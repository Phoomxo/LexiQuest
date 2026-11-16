---
target: signed 1.0.0+17 Login
total_score: 39
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 0
target_identity: "file:C:\\Users\\Phet\\.codex\\worktrees\\cycle12-release\\LexiQuest\\lib\\screens\\login_screen.dart"
target_fingerprint: "sha256:618ded78d99b2470b6b5b831547700879547889b3f123fde705340ff8d2c4708"
target_path: "C:\\Users\\Phet\\.codex\\worktrees\\cycle12-release\\LexiQuest\\lib\\screens\\login_screen.dart"
timestamp: 2026-10-26T09-15-11Z
slug: lib-screens-login-screen-dart
---
Method: design review only (detector not applicable, native Android platform)

## Design Health Score

| # | Heuristic | Score | Key evidence |
| --- | --- | ---: | --- |
| 1 | Visibility of System Status | 4 | Busy overlay, inline field/account errors and semantic progress label |
| 2 | Match System / Real World | 4 | Plain Thai copy and familiar email/password/Google/guest paths |
| 3 | User Control and Freedom | 4 | Guest/register routes, cancellable reset and provider flows |
| 4 | Consistency and Standards | 4 | Material 3 controls, color roles, 48dp actions and Android navigation |
| 5 | Error Prevention | 4 | Local validation, busy guard and provider availability gate |
| 6 | Recognition Rather Than Recall | 4 | Every icon is paired with a plain-language label |
| 7 | Flexibility and Efficiency | 4 | Autofill, keyboard submit and three sign-in/continue paths |
| 8 | Aesthetic and Minimalist Design | 4 | One filled primary action with clear secondary hierarchy |
| 9 | Error Recovery | 4 | Values persist; errors are local, actionable and non-destructive |
| 10 | Help and Documentation | 3 | Password help is present; public help/privacy links await approved endpoints |
| **Total** | | **39/40** | **Excellent; P0=0, P1=0** |

## Design Specificity Verdict

The layout uses a familiar Android sign-in grammar, but the LQ route mark,
Thai copy about vocabulary/review/progress, guest-first local path and calm
hierarchy make it recognizably LexiQuest rather than a generic template.

Deterministic scan: not applicable on native Flutter. No browser overlay was
created.

## Overall Impression

The screen is calm, legible and production-ready for bounded field testing.
Its strongest trait is disciplined hierarchy: email sign-in is primary while
Google, guest and registration remain discoverable without competing equally.

## What's Working

- 100% and 200% portrait remain readable; the 200% layout scrolls to every
  action.
- Forced landscape at 200% renders without overlap or crash.
- Semantics, autofill, 48dp targets, error recovery and lifecycle behavior are
  grounded in source tests and signed-device evidence.

## Priority Issues

- **[P2] Manual accessibility acceptance is incomplete**
  - **Why it matters:** automated semantics and screenshots cannot prove spoken
    order or full landscape reachability for a TalkBack user.
  - **Fix:** run human TalkBack and landscape bottom-reachability UAT on the
    exact signed artifact; keep fields pending until observed.
  - **Suggested command:** `$impeccable audit`
- **[P3] Contextual help/privacy is not exposed from Login**
  - **Why it matters:** a first-time user who is stuck has no direct help path.
  - **Fix:** add compact footer links only after owner-approved public help and
    privacy URLs exist; do not invent a contact or endpoint.
  - **Suggested command:** `$impeccable harden`

## Persona Red Flags

- **Jordan (First-Timer):** labels and hierarchy are immediately clear; the
  only red flag is no direct help link from this screen.
- **Sam (Accessibility-Dependent):** 200% rendering and semantics have
  engineering evidence, but actual TalkBack spoken order remains unverified.
- **Casey (Distracted Mobile User):** primary/alternative actions are in the
  thumb zone and warm resume is stable; Google and guest reduce typing.

## Minor Observations

The floating bubble covering the left edge of the hero copy in physical-device
captures is a Vivo system overlay, not app content. Use an overlay-free test
profile for final visual UAT rather than changing the app around an arbitrary
floating window.

## Questions to Consider

- Once approved public URLs exist, should Help and Privacy be one compact footer
  row or live behind a single “ช่วยเหลือ” link?
- Which human UAT profile should certify TalkBack and landscape reachability?
