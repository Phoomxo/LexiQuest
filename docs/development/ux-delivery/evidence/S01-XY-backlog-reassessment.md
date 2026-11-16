# Bounded backlog reassessment after S01-X/Y

Authority: plan v5 section 15.4 and controller instruction 2026-09-24 to select work by user outcome, group shared causes, and avoid empty succession. Source inspected in f72d at base 2ea4d407 plus the verified predecessor overlay and X/Y changes. This is a bounded selection review, not proof that the entire application is defect-free.

| Area / user outcome | Source and current evidence | Next indispensable evidence / readiness |
| --- | --- | --- |
| UX01/UX06: start, continue, request help, stop audio and return | render, navigate, goBack, renderMode, renderLabActivity, speakDraft; X/Y source pins. Y reproduces disappearing displayed controls and verifies a focus call to a retained heading. | Permitted real keyboard/screen-reader/visual review and real audio observation. Host focus calls cannot prove accessibility. |
| UX01/UX12: keep a draft with the intended owner | switchDemoOwner, examDraftKey/storeExamDraft, draft-discard actions, typed/canvas state; inherited and X/Y regression suite | Real native persistence/restart/owner acceptance. Prototype explicitly keeps only page-lifetime drafts. |
| UX03/UX07: independently enter and pause/resume each story route | renderPilot/openPilot and prior story support/revision evidence unchanged | Qualified content/media review, then trial participants. No instructional Flutter expansion before trial acceptance. |
| UX04/UX12: import, edit, delete, cancel and export intended data | renderImport/previewImportDraft, renderEditWord, renderDeleteWord, renderExport; inherited bounded host evidence retained | Actual permitted download/persistence/native behavior. No fake learner records or hosted-sync acceptance. |
| UX05/UX11: change exercise or exam track and return to the right draft | renderExam and three X selector handlers; all rendered tasks and global lab-map entries tested | Permitted visual/native confirmation; exam rubric/content remains draft. Invalid values and detached synthetic dispatch are defensive tests, not observed usability failures. |
| UX08: distinguish sample effort from learner evidence | renderReview/renderWeakness/renderHistory/renderProgress; inherited empty/sample distinctions | Actual user comprehension and production integration/persistence when scoped. Do not create mastery from viewing prototype content. |
| UX09/UX10: recover from unavailable camera/provider and choose a manual path | renderCamera/renderAi/readiness cancellation; Y camera sample stage continuation | Real camera/model/rights/provider/quota evidence, and permitted visual review. The sample flow does not invoke hardware/model/provider. |
| Team routing, separate from learner product | Jev offline64 evidence unchanged; controller dashboard login barrier unchanged | Fresh free/pricing/shared-spend/quota plus original ledger reservation required before a live batch. Do not probe login again without changed signal. |

## Selected decision

X/Y are complete at the host layer; zero unresolved RED. No additional concrete independent user-journey failure was selected by this review. Stop generating hypothetical guard packages and keep the current task idle/reserved. No successor was dispatched; S01 is still IN_PROGRESS with its original 28-day dates. Continue useful authorized work automatically when a concrete finding or changed prerequisite supplies a ready scope.

Required next review: start a sample mode, advance/retry a mission, open/cancel/confirm each draft-discard flow, stop audio (including completion/failure), and navigate the camera permission/failure/retry sample by keyboard and assistive technology through a permitted channel. Verify focus destination, order, announcement, visible focus and scroll while preserving entered text. Existing browser automation rejection must not be bypassed using another browser, CDP, headless or localhost.

Known mode play-audio synthetic fixture issue from the predecessor is unchanged: F/T/U deliberately invoke it outside displayed audio kinds. This is not evidence of a user-facing defect and does not justify silently changing old tests or opening a new package. Actual rendered controls must anchor future scope.

No paid inference, purchase, deploy, research activation, new heartbeat, external participant messages, reviewer approval or learning result was produced. Self-review only. All UX-D01-25 remain OPEN for their required layers.
