---
target: Vivo signed release Login screen +15
total_score: 40
max_score: 40
na_heuristics: ""
p0_count: 0
p1_count: 0
target_identity: "file:C:\\Users\\Phet\\.codex\\worktrees\\cycle12-release\\LexiQuest\\lib\\screens\\login_screen.dart"
target_fingerprint: "sha256:618ded78d99b2470b6b5b831547700879547889b3f123fde705340ff8d2c4708"
target_path: "C:\\Users\\Phet\\.codex\\worktrees\\cycle12-release\\LexiQuest\\lib\\screens\\login_screen.dart"
timestamp: 2026-10-26T05-09-55Z
slug: lib-screens-login-screen-dart
---
# Login screen critique — Vivo signed release +15

Method: design review only (detector not applicable, native Flutter)

## Design Health Score

| # | Heuristic | Score | Result |
|---|---|---:|---|
| 1 | Visibility of System Status | 4 | Busy state disables actions and exposes an announced spinner. |
| 2 | Match System / Real World | 4 | Thai copy is direct and uses familiar account language. |
| 3 | User Control and Freedom | 4 | Password reset, Google, guest, and registration paths remain available. |
| 4 | Consistency and Standards | 4 | Material 3 controls, responsive spacing, and hierarchy are consistent. |
| 5 | Error Prevention | 4 | Inline validation and busy guards prevent invalid or duplicate submissions. |
| 6 | Recognition Rather Than Recall | 4 | Every action and icon has a visible label. |
| 7 | Flexibility and Efficiency | 4 | Autofill, keyboard submit, Google, and guest paths support different users. |
| 8 | Aesthetic and Minimalist Design | 4 | The LQ route mark, primary CTA, and calm spacing create a specific identity. |
| 9 | Error Recovery | 4 | Provider failures remain inline until action and clear when recovery begins. |
| 10 | Help and Documentation | 4 | Recovery, guest, and registration paths appear in the context where needed. |
| **Total** | | **40/40** | **Excellent** |

## Design Specificity Verdict

The LQ route mark, Thai learning proposition, and restrained action hierarchy
read as LexiQuest rather than a generic education login. Deterministic DOM
scans and browser overlays do not apply to this native Flutter target.

## Overall Impression

The signed Vivo render is release-credible. The form is centered, all controls
fit without collisions, and alternative entry paths remain subordinate to the
primary sign-in action. The previous generic identity and transient recovery
issues are closed.

## What's Working

- One filled primary CTA anchors the screen while Google, guest, and register
  actions remain visually distinct.
- Retryable account failures stay near the form, use semantic color roles, and
  announce through a live region.
- Responsive 16/20dp compact gutters, 48dp targets, keyboard submit, autofill,
  and tested 200% text cover the practical Android interaction floor.

## Priority Issues

None.

## Persona Red Flags

- **Jordan (first-timer)**: no blocking issue; the proposition, primary action,
  and guest path are understandable within one scan.
- **Sam (accessibility-dependent)**: labels, tooltips, live-region feedback,
  semantics, and 200% text tests are present. Manual TalkBack remains separate
  physical evidence rather than a visual critique defect.
- **Casey (distracted mobile user)**: error feedback persists until action and
  the primary/alternative actions remain distinguishable in the thumb zone.

## Minor Observations

- The floating control at the left edge is a Vivo OEM overlay, not an app
  overlap.
- The text G is not official Google artwork, but its adjacent full label is
  unambiguous and it does not impair accessibility or task completion.
- Dark-mode contrast uses Material color roles and no state depends on color
  alone.

## Questions to Consider

None required for this pass; there are no unresolved priority issues.

Questions skipped: no unresolved priority issues; continue ADLC automatically.
