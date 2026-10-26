---
target: Vivo signed release Login screen +14
total_score: 37
max_score: 40
na_heuristics: 
p0_count: 0
p1_count: 0
target_identity: "file:C:\\Users\\Phet\\.codex\\worktrees\\cycle12-release\\LexiQuest\\lib\\screens\\login_screen.dart"
target_fingerprint: "sha256:ab609dde0fc4eba40ba2337a24cb2194036abc8eeaa0810e25244e36352bd499"
target_path: "C:\\Users\\Phet\\.codex\\worktrees\\cycle12-release\\LexiQuest\\lib\\screens\\login_screen.dart"
timestamp: 2026-10-26T04-22-07Z
slug: lib-screens-login-screen-dart
---
# Login screen critique — Vivo signed release +14

Method: design review only (detector not applicable, native platform)

## Design Health Score

| # | Heuristic | Score | Key issue |
|---|---|---:|---|
| 1 | Visibility of System Status | 4 | Busy state disables actions and exposes an announced spinner. |
| 2 | Match System / Real World | 4 | Thai copy is direct and uses familiar account language. |
| 3 | User Control and Freedom | 4 | Password reset, Google, guest, and registration paths remain available. |
| 4 | Consistency and Standards | 4 | Material 3 controls, spacing, and hierarchy are consistent. |
| 5 | Error Prevention | 4 | Inline validation and busy guards prevent duplicate or invalid submissions. |
| 6 | Recognition Rather Than Recall | 4 | Every action and icon has a visible label. |
| 7 | Flexibility and Efficiency | 4 | Autofill, keyboard submit, Google, and guest paths support different users. |
| 8 | Aesthetic and Minimalist Design | 3 | Clear and calm, but the stock book/account symbols are category-generic. |
| 9 | Error Recovery | 3 | Provider failures preserve the form but rely on transient SnackBars. |
| 10 | Help and Documentation | 3 | Recovery and guest paths are clear; contextual support is not present here. |
| **Total** | | **37/40** | **Excellent** |

## Design Specificity Verdict

The Thai learning proposition, calm hierarchy, and evidence-led positioning fit
LexiQuest. The screen is coherent and trustworthy, but its central book icon
and generic account-circle Google icon could appear in many education apps.
Deterministic scan and visual overlays are not applicable to native Flutter.

## Overall Impression

The signed Vivo render is release-credible: the primary action is unmistakable,
secondary entry paths are separated, and the form remains readable without
visual collisions. The largest opportunity is stronger LexiQuest identity
without adding noise.

## What's Working

- One filled primary CTA anchors the screen; secondary paths do not compete.
- Thai copy explains the benefit before asking for credentials.
- 48dp controls, autofill, keyboard submit, explicit password visibility, and
  tested 200% text behavior cover the practical Android interaction floor.

## Priority Issues

1. **P3 — Generic product identity**: the stock book symbol and account-circle
   Google symbol weaken product specificity. Use a restrained LexiQuest mark
   and an approved Google sign-in treatment in a future polish pass.
2. **P3 — Transient provider recovery**: account failures appear in a SnackBar.
   Preserve the SnackBar for announcements, but retain actionable recovery near
   the form when the failure requires a retry or network change.

## Persona Red Flags

- **Jordan (first-timer)**: no blocking issue; the first action and guest path
  are understandable within one scan. Provider failure guidance may disappear
  before a hesitant user acts.
- **Sam (accessibility-dependent)**: labels, tooltips, semantics, and 200% text
  tests are present. Manual TalkBack spoken order remains unverified evidence.
- **Casey (distracted mobile user)**: primary and alternative actions are in the
  thumb zone and retained-data cold/warm launch passed. Five visible paths add
  one small decision burden, but hierarchy keeps cognitive load low.

## Minor Observations

- The Vivo accessibility floating control visible at the left edge is an OEM
  overlay, not an app overlap.
- Cognitive-load checklist: one minor failure on minimal choices; all other
  checklist items pass, so overall cognitive load is low.
- Dark-mode contrast is resolved through Material roles; no color-only state is
  used on this screen.

## Questions to Consider

- Could one compact LexiQuest mark replace the stock book without increasing
  the empty-state weight?
- Should retryable provider failures stay visible until the user acts?

Questions skipped: 2 Priority Issues.
