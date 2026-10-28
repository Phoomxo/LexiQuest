# Motivation form component

Worktree `C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`, branch
`codex/remaining-system-readiness`, built on `65f955de`. Schema stays v15/34.

The standalone form loads the supplied structured instrument and saves coded
responses through the existing measurement repository. Failed saves retry the
same command. Durable completion and delivery of the navigation callback retry
separately, so callback failure cannot submit another answer or close operation.
Owner/run/repository replacement and temporary invisibility hide private items
and invalidate late acknowledgements. This visibility token is not research
authority; the repository still performs its existing checks.

A new failing widget case reproduced a withdrawal intent being cleared when
the same form temporarily disappeared and returned. Canonical withdrawal may
have committed even if historical bookkeeping failed. The form now retains the
identical pending withdrawal for the same binding, keeps questions hidden and
offers retry. A genuinely replaced binding clears private local state.

Actual rendered dark text failed Flutter's contrast guideline. The shared dark
theme replaced its generated dark foregrounds with light-theme brand/error
colors. The fix uses the generated dark primary/onPrimary and error/onError
pairs, preserving the explicit Ocean primary pair and the light theme. Two
color tests first failed, then passed for the relevant surface variants.

Current-source evidence:

- 24 form widget cases passed, including the reproduced visibility/withdrawal
  failure, exact retries, stale acknowledgements and 200% text sizing.
- 79 combined form/theme/accessibility/appearance/shop checks passed.
- Five real-font Flutter widget captures passed; the 100% dark capture also
  passed `textContrastGuideline`. Thai light 100%, Thai dark 100/200%, English
  dark 200% and scrolled Thai actions were inspected. These are widget fixtures,
  not physical-device or complete-app UAT.
- Final `flutter analyze --no-pub` reported no issues.
- An independent reader accepted the actual form, tests and shared theme diff.

Logs, before/after PNGs, reproducible capture source and the hash manifest live
under `D:\LexiQuest-Storage\maintenance\2026-10-28\remaining-systems`.
The normal APK at the retained path remains the verified `1128b9e6` artifact;
this component has no production route yet. The next unit persists accepted
quiz inputs and checkpoints before composing a truthful study host.

The latest full suite remains 2594 on `1128b9e6`; it predates this component.
Enrollment/upload remain default-off. Automatic approval rejected the earlier
owned emulator stop/delete command with `blocked by policy`; no retry occurred.
