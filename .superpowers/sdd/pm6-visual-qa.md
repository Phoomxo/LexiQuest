# PM6 visual QA — interim

Date: 2026-09-06. Worktree C:/Users/Phet/.codex/worktrees/02fa/LexiQuest, branch codex/pair-matching-pm0-pm8. Root opened actual PNGs with view_image; no image editing or Flutter tooling by root. Main implementer still owns final source/golden generation.

All paths below are under test/features/learning/pair_matching/goldens/pair_board/.

- thai_regular_standard6.png: six balanced rows; visible English/Thai labels and heading readable, no visible clipping.
- english_reverse_selected.png: Thai prompt/English targets, selected border and local pronunciation label visible; no visible overlap.
- thai_wide_bounded.png: actual 1280px fixture uses centered bounded content; no stretched full-width cards.
- Initial thai_long_narrow_text_200.png showed short water/น้ำ while the long fixture was offscreen. This did not establish long-label visual QA; root requested actual long item selection/scrolled capture.
- Corrected thai_dark_high_contrast_wrong_repair.png: light feedback container now has readable dark text/icon after main fixed onSecondaryContainer binding. SHA256 73672FD77E0F7C1495C8F3F754B16763474AC7835CAE720B195CFC7956D16BA5.
- thai_guided_reduced_motion_no_audio.png: canonical mapping and separate explicit confirmation readable, no visible overlap. No audio fallback line is visible in this fixture; no-audio acceptance needs actual route failure/copy tests, not this filename. SHA256 8B26DA4E7D38CC017FFD32CBF3323C86D87F4D86AC29567A9D59513A74D72F1F.
- thai_long_narrow_text_200_scrolled.png: actual long Thai label fully wraps across multiple lines; English targets remain readable and vertically separated. Current reverse-layout heading incorrectly says เลือกความหมาย over English targets; main already identified and is fixing language-aware focused copy. SHA256 C5C5759BE0434ADC7A1AC797866EA9C137BA8342FEEFAFA9D5A75E8AF2FA1AC2.

Final baselines and tests must be regenerated/compared after remaining copy changes. Setup, timeout, result, History visual QA and actual accessibility behavior remain pending. This is not final PM6 acceptance, physical device evidence, or formative UAT.

## Actual host surfaces — additional interim inspection

Root opened host_setup_thai_guardian.png, host_timeout_thai.png, host_result_thai_measured.png and host_replay_result_english.png. In the viewed versions, setup shows actual four pairs, typed new-content reason, guardian note, OFF default and validated600-second maximum; language direction icons are visible. Timeout's own actions have one filled Continue and two outlined alternatives. The shell surface background is opaque/readable. Thai normal result shows measured2 seconds and English replay3 seconds matching synthetic test scenarios, with separate descriptive star/independence/support/time copy.

Two concrete hierarchy corrections sent to main before final baselines: result currently makes Replay filled/primary while Return is a small bottom text action; approved UI17.9 requires source return/continue as primary with Replay secondary. Add visible star icons with one accessible score description, retaining the existing policy/value. Timeout also still inherits a second filled legacy Show strategy action above Continue. Root verified its two texts are neutral generic strategy/context, not lexical mappings, so no mapping leak was established; suppress only that legacy HintPanel for the explicitly reserved Pair route because Pair has its own support controls. Preserve committed accessibility/companion feedback and default legacy/other-mode behavior.

These observations are interim. Main is still correcting source and regenerating images; no final all-surface or physical accessibility acceptance is claimed.

## Final twelve-image inspection for PM6 review

Root opened all twelve current PNGs after final regeneration on 2026-09-06. The concrete interim issues above are closed in these fixtures: no missing direction glyph, readable dark feedback, actual long Thai wraps at200% with neutral correct target instruction, Return is the primary result action, Replay is outlined with its no-additional-progress/reward explanation, visible stars retain one score description, and timeout shows matched/total with one filled Continue and no inherited legacy HintPanel. No visible clipping, overlap or contrast blocker was found in the displayed fixture regions. Narrow scroll views deliberately show different portions of the same vertically scrollable content; the scrolled image exposes the full long label and targets.

Actual host fixtures retain existing English companion feedback. This review covers Pair's own Thai/English content and does not claim global app localization. Static images do not prove screen-reader or switch operation, real native audio, physical-device performance or formative UAT. Those require their separately recorded behavioral tests/external gates. History has actual widget/typed-replay tests but no new History golden in this twelve-image set.

Root verified pm6-final-golden-generate.log GREEN10 producing twelve PNGs; the final Pair grouped run also compared these baselines and ended GREEN494. Voice grouped run GREEN163 and full analyzer No issues8.3s were read from their actual logs. These are evidence for the pending independent PM6 review, not a declaration that PM0–PM8 is finished.

| PNG | SHA256 at final visual inspection |
| --- | --- |
| english_reverse_selected.png | 650304E8C329F1D93F9C5D30F1C484A66790EF47891FECFC239B7D2614FC2A8E |
| host_replay_result_english.png | 59F3FC2780288BD3433AC06BEC823F9F49E96D2D08AB8CABA72F8B8F6967DBC5 |
| host_result_thai_measured.png | DCC96C1C4409BF136B6957D571DD6A5F068C4283E23D4627DE3E414D0E385880 |
| host_setup_thai_guardian.png | A176C83A5534B6B5DF5AF13F6520B40A3140FD4F6C31C96169FF0491E027175C |
| host_timeout_thai.png | FD549BBAB8E8C904E404CD0FDC2596EF0FA809594CF1E847707AC17CD3B7E7AA |
| thai_dark_high_contrast_wrong_repair.png | 73672FD77E0F7C1495C8F3F754B16763474AC7835CAE720B195CFC7956D16BA5 |
| thai_guided_reduced_motion_no_audio.png | 8B26DA4E7D38CC017FFD32CBF3323C86D87F4D86AC29567A9D59513A74D72F1F |
| thai_long_narrow_text_200.png | D21BDE3D8BDC26C5A535186644D2415AA4D9564FA3CE1E3F87D1DDE859889955 |
| thai_long_narrow_text_200_scrolled.png | E786AF9701B8A758F68512FD124B686AE4459A57C471147B05A4BD9C0BCC9D7E |
| thai_regular_compact4.png | 8B4264517131D25EEE7F99C4E29645EFFD114F67FA30625EDF609A638F7C3CF2 |
| thai_regular_standard6.png | 195D5E2B9965A9880FC3378D95EF6D3BEE2DC46C9BF5CED8C5E19D2B98EE436F |
| thai_wide_bounded.png | 4A41750CD333C9EA763165B8E37302DCD459CB858FC4152BAFFADE9D73B25FD2 |
