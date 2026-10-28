# Task 0A — Release A research-integrity gate

Worktree: `C:\Users\Phet\Documents\LexiQuest\.worktrees\release-a-research-integrity`
Branch: `codex/release-a-research-integrity`
Base: `f66d0316daff57c83ed972a11f6425cb326f482a`

Implement the research-integrity part of Stage 0 with strict TDD:

1. Remove all production navigation to research outputs that use sample, assumed, or synthetic data:
   - Remove the Export Center and Thesis Chart entries/routes from `ChooseModeScreen`.
   - Remove the Export Center entry/route from `SettingScreen`.
   - Do not merely relabel sample data as real research data.
2. Make `ResearchReportPdfExporterService` reject insufficient real observations with a typed `InsufficientData` result/exception.
   - No fallback sample size, pre-test score, post-test score, gain, latency, p-value, or expected significance.
   - Derive every displayed statistic from actual caller-supplied typed observations only.
   - Do not claim statistical significance.
3. Remove default fabricated values from `ThesisChartScreen`.
   - Any retained screen must require actual caller-supplied data and derive labels from that data.
   - If no production caller remains, keep changes minimal; do not delete unrelated export functionality.
4. Remove the production “Research CSV” sample export path from `ExportCenterScreen`. Ordinary progress/export behavior may remain.
5. Add focused regression/contract tests that fail first and prove:
   - empty research observations fail explicitly;
   - report output has no fabricated/default statistical claims;
   - chart construction has no fabricated default data;
   - production navigation does not expose Export Center/Thesis research routes;
   - Export Center does not present sample data as Research CSV.

Global constraints:

- Preserve existing non-research exports and unrelated behavior.
- No production code before a witnessed failing test.
- Do not edit generated plugin files.
- Do not modify or rebase `feature/associative-reading-loop`.
- Run focused tests, then `dart format --output=none --set-exit-if-changed` on touched Dart files and `flutter analyze`.
- Commit changes on this branch with a clear conventional commit.
- Write the full RED/GREEN evidence, files changed, commands, outputs, and self-review to `.superpowers/sdd/task-0a-research-integrity-report.md`.
- Return only status (`DONE`, `DONE_WITH_CONCERNS`, `NEEDS_CONTEXT`, or `BLOCKED`), commit SHA, one-line test summary, and concerns.
