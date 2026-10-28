### Task PM8 — Compatibility rollout, G4P evidence and prototype sign-off (12 pd)

**Requirements:** all FR-105–130, DATA-016–021, UI-018–027, NFR-038–046, BR-024–034

**Files/evidence:**

- Update as-built SDS, RTM, Test Plan and UAT evidence links
- Add checkpoint v1–v5 plus next-version fixtures in the repository's existing codec test location
- Add feature/emergency-off integration fixtures without enabling production
- Archive G4P evidence under the approved build-evidence location; do not place private/raw vocabulary in docs

**Steps:**

1. reserve the actual next checkpoint version; Release A reads old+new and writes old;
2. run recovery/rollback matrix and set minimum compatible build; only then Release B may write new checkpoint under hidden f10 flag;
3. run PMT-001–044, UAT-039–050, 8/44 registry/navigation, learning/SRS/mastery/weakness/reward/history/Today and Adventure fallback regressions;
4. run `flutter analyze --no-pub lib test`, focused dependency/privacy checks and bounded manual diff review;
5. verify feature off, Pair emergency-off, Adventure-off, accepted-session close and unrelated Quiz modes;
6. reconcile RTM exactly 258/258 and record current build/commit/config/device evidence;
7. Product, Learning/Data, UX/Accessibility, QA and Tech choose Accept/Revise/Reject;
8. keep status Hidden/Internal; G4P does not authorize MS-08A/MS-08B or production enablement

**Exit:** signed G4P package, reproducible rollback and zero open S0/S1; otherwise Revise/Reject with owner/date
