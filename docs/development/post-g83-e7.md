# E7 — system verification and final ledger

E7 starts from accepted E6 `133e382db5e4c59d29975b39a47e5dfa3820d2d2` on `lexiquest/post-g83-e7`. The exclusive writer claim is control revision 276. Baseline verification matched all 3,744 source entries through Git-blob and raw/normalized hashes and all eight E6 evidence pins. The accepted application remains schema 34, 58 tables and 48 direct-owner descriptors.

G8.4 has produced the [executable plan](post-g83-e7/system-test-plan.json), [initial NOT RUN ledger](post-g83-e7/initial-not-run-ledger.json), and [E6 reuse register](post-g83-e7/reuse-evidence.json). The current Dart generator wrote and checked a separate versioned artifact; historical schema-26 artifacts are unchanged. The plan retains 67 original package identities, 74 overlapping coverage records, 12 formula groups, all 16 test families and F01–F09. Its 106 cases reference 62 distinct execution commands, with disjoint local target selection. The 79 inherited targets retain E6 delta-reconciled receipts, not a summed unique-test count.

G8.5 is next: execute the 453 other local Flutter targets and bounded backend/rules/evaluator checks serially, capture failures and correct affected code. Device/artifact journeys, faults/resources, changed-code review and final ledger remain pending. Physical camera, human TalkBack/audio/rubric calibration and live-provider requirements remain distinct NOT RUN cases; no mock or screenshot substitutes for those results.

Recovery follows the current implementation authorization: diagnose failed methods, correct and retest without weakening acceptance. No subagents, deployment, added cost, research activation or successor dispatch. Standard/default requested; effective runtime tier is not exposed and remains unverified.
