# Priority 8 physical speech checkpoint

Historical R2 checkpoint below. Latest R3 trials, R4 artifacts, failed USB
installation reconciliation and remaining work are recorded in
`2026-09-11-priority-7-12-checkpoint.md`; the old final paragraph does not describe
the current implementation status of priorities 9–12.

Worktree: `C:/Users/Phet/.codex/worktrees/02fa/LexiQuest`.
Branch: `codex/pair-matching-pm0-pm8`; HEAD at start
`788e90e62b1694c20945734787723c168b6a6ab2`.
Preserve inherited dirty files. Priority 8 source change is limited to two
Thai retry-button labels in `lib/screens/shadowing_challenge_screen.dart`.

Priority 7 local opt-in preview is verified; see the priority 7 results report.
Installed artifact remains manual v14 Thai R2, SHA256
`18dd1abb3d65dfba5e9f3e9a651c8db4827ebb652d8c96729710489585ccf13a`.
This fixture uses synthetic local data and real native speech dependencies.

## Verified

- Flutter selected speech use-case, Shadowing screen, Speaking screen and
  native TTS provider tests: 85 passed, exit 0. Log:
  `build/verification/priority-7-20260911/priority8-baseline.log`.
- Actual vivo route Learn > Shadowing > setup > start loads `station`.
- Reference playback button accepts input without a displayed error. This
  does not establish audible output or voice quality without a listener.
- Starting speech changes the control to Stop. Android RECORD_AUDIO app-op
  records a 2.833-second acquisition; no running acquisition after timeout.
- No-input timeout displays the Thai no-clear-speech message and restores Start.
- A second start followed immediately by the visible Back control returns to
  Learn; app-op duration 203 ms, no running acquisition after exit.
- Native screenshots/hierarchies under
  `build/verification/motivation-ui-20260908/device/manual-ui/`:
  `priority8-shadowing-ready`, `priority8-shadowing-played`,
  `priority8-shadowing-listening`, `priority8-shadowing-timeout`,
  `priority8-shadowing-exit`, and `priority8-human-ready`.

## Remaining physical acceptance

The device is reopened on Shadowing, ready for a human utterance, with no
microphone capture deliberately left running. No build/test process remains.
Next step: the holder taps reference playback and confirms audibility, then
taps Speak and reads the displayed word. Inspect the resulting transcript,
completion and persisted evidence; never substitute a fake gateway result for
that physical check. Platform recognition uses `onDevice: false`, so this is
not an offline-ASR guarantee. Current assessment is transcript edit-distance
similarity, not an acoustic pronunciation score.

The English Shadowing persistence-retry labels are now translated in source.
All 16 Shadowing screen tests passed after that text-only patch, exit 0;
`build/verification/priority-7-20260911/priority8-shadowing-thai.log`.
Scoped diff reviewed; other changes in that file predate this priority.
Current installed R2 artifact predates these two labels. Rebuild after physical
acceptance and any resulting fixes; do not describe R2 as containing this patch.

Priorities 9–12 are not implemented or complete in this pass. A read-only
inventory located the CEFR reader/service and content contracts for the next
priority. Keep user-requested ordering; no deployment, paid model request,
research upload, OEM log collection, or learner-data clearing performed.
