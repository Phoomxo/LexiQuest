# LexiQuest Claude Code Configuration & Autonomous Operating Guide

This project strictly adheres to the **Unified Multi-Agent Blueprint** defined in [AGENTS.md](./AGENTS.md).
Claude Code must execute development tasks autonomously using the predefined skill pattern without waiting for manual prompting.

---

## 1. Single Workspace & Preservation Invariant
- **Authoritative Workspace:** `C:\Users\Phet\Documents\LexiQuest` on branch `main`.
- **STRICT PROHIBITION:** Do NOT create git worktrees (`using-git-worktrees` is hard-blocked).
- **Protected Outside Paths:** Never touch `E:\เล่มโปรเจค` or `C:\Users\Phet\.lexiquest`.

---

## 2. Autonomous Intent-to-Skill Execution Pattern (Prompt-Free Operation)
Whenever a user request arrives, automatically invoke the matching skill chain:

| User Task / Intent | Autonomous Skill Chain (Executed In Order) | Mandatory Verifiable Artifact |
|---|---|---|
| **UI / Screen / Layout / Theme / Widget** | 1. `ui-design-suite` (Master UI Coordinator)<br>   ↳ `figma-designer` + `ui-ux-pro-max` (tokens & guidelines)<br>   ↳ `taste-skill` (tokens, spacing, contrast, micro-interactions)<br>   ↳ `flutter-build-responsive-layout` (Material 3 Compact <600dp)<br>2. `flutter-add-widget-test` (simulate tap, scroll) | Widget test proving real touch interaction + 0 RenderFlex overflow |
| **Database / State / Backend / API / Logic** | 1. `flutter-apply-architecture-best-practices` (4-layer wiring)<br>2. `dart-use-pattern-matching`<br>3. `dart-add-unit-test`<br>4. Drift SQLite mutation verification | Unit test verifying DB persistence / State update |
| **Bug / Crash / Overflow / Regression** | 1. `debugging-and-error-recovery`<br>2. `flutter-fix-layout-issues` or `dart-fix-runtime-errors`<br>3. `test-driven-development` | Reproducing test failing first, passing after fix |
| **QA / Pre-Commit / Verification** | 1. `constraint-driven-development` (audit for lazy stubs/suppressions)<br>2. `dart-run-static-analysis` (`flutter analyze`)<br>3. `verification-before-completion` (`flutter test`)<br>4. `ocr review` (`OpenCodeReview` CLI) | Exit code 0 on all gates + OCR review findings addressed |
| **Session End / Checkpoint / Delivery** | 1. `technical-writing` + `unslop`<br>2. `claude-mem sync`<br>3. Git commit with Conventional Commits | Claude-mem snapshot + clean working directory |

---

## 3. Mandatory Execution Invariants
- **No-Prompt Rule:** Never ask the user "Should I run tests?" or "Do you want a code review?". The matching skill chain must execute autonomously.
- **4-Level Wiring Rule:** Every UI element must wire: UI Widget $\rightarrow$ Application UseCase/Bloc $\rightarrow$ Repository Adapter $\rightarrow$ Drift SQLite Table / API. No dummy handlers `onPressed: () {}`.
- **Pipeline Runner:** You can run all verification gates automatically at any time with:
  `tool\agent_pipeline.bat All` or `powershell -ExecutionPolicy Bypass -File tool\agent_pipeline.ps1 -Gate All`
