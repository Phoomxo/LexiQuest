# PM7 Adventure visual inspection

Root independently viewed all three current PNGs with view_image on 2026-09-06 after main's corrected generation. Source is the PM7 working tree on codex/pair-matching-pm0-pm8 above cbc4541ff4ad058e11f056f2d06f7eada201e3f9; this is visual evidence, not full PM7 acceptance.

Generation: `.superpowers/sdd/pm7-adventure-golden-final.log` ends GREEN4, 1 second, including Thai regular six-pair, Thai/English narrow text200 reduced-motion semantics and typed late health failure. Final frozen regression still must compare these exact images without update.

All paths below are under `test/features/adventure/presentation/goldens/`.

| Image | SHA256 | Root observation |
| --- | --- | --- |
| adventure_pair_th_regular.png | 99a9c902292a73eefdd688390ae635775f2c64848d02c65696f101f981e2bd05 | 412×915: Thai title and optional narrative fit in header, six pairs and matching status are legible, canonical board is intact. |
| adventure_pair_th_narrow_text200.png | dc28540174c0ec68ade446105bcc4387bf0a0236a2f77b13b0b983b14a2bb6f3 | 320×720 at200%: Thai title and combining marks fit, optional decorative narrative is omitted, task instructions/status remain visible; focused board continues below viewport via its existing scroll. |
| adventure_pair_en_narrow_text200.png | 5c6bcc18f83159813d7e88f294d07d59630d58b937c7ab93e38d2c5a91e4d888 | 320×720 at200%: English title fits, matching instructions and status wrap, focused board continues below viewport; no clipped header narrative. |

The earlier subtitle clipping is corrected in these images. A clipped tile at the lower screenshot edge represents the scroll viewport, not proof that all tiles fit at once. Full action/scroll/keyboard/semantics parity is established by the relevant automated tests and final review, not these still images. PM6 already inspected long Thai below the fold on the reused board. No physical TalkBack/Switch/audio/performance or learner UAT was run; no external accessibility sign-off is implied.
