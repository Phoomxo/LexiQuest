# LexiQuest Stabilization Gate Implementation Plan

> **Execution contract:** Work in small, independently verifiable changes. Use
> Cointh/GLM at maximum reasoning effort for one narrowly scoped file at a time.
> Do not advance to the next gate while the current gate is red.

**Goal:** Bring the current production vertical slices to a reproducible,
security-reviewed, continuously verified state without starting GPU workloads.

**Architecture:** Keep the existing Flutter application and three CPU-only
backend verification suites as the source of truth. GitHub Actions repeats the
same quality gates on clean runners. Dependency changes are isolated by direct
package and accepted only after analysis, tests, and an Android build. Security
work follows threat model, discovery, validation, attack-path analysis, and
remediation verification.

**Toolchain:** Flutter 3.44 / Dart 3.12, Android Gradle Plugin 9 / Gradle 9,
Java 17 bytecode, Python 3.11 with uv, pytest, GitHub Actions, OSV-compatible
dependency auditing, Codex Security, Cointh/GLM CLI.

---

## Gate 0: Reproducible Baseline

**Files:**

- Verify: `tool/cli/verify.ps1`
- Record: `docs/PRODUCTION_FOUNDATION.md`

1. Run the CPU-safe verification entry point.
2. Confirm Flutter analysis/tests, all backend tests, Android debug build, and
   the read-only GPU doctor pass.
3. Record any pre-existing warning separately from failures introduced later.

**Pass condition:** The existing branch is green before stabilization changes.

## Gate 1: GitHub CI

**Files:**

- Create: `tool/cli/tests/ci-workflow.tests.ps1`
- Create: `.github/workflows/ci.yml`

1. Add a failing structural contract test for triggers, least-privilege
   permissions, immutable action pins, Flutter checks, CPU-only backend tests,
   and Android build.
2. Ask GLM to implement the single workflow file against that contract.
3. Run the contract test locally, then validate the workflow syntax.
4. Push the workflow and confirm PR checks are created.

**Pass condition:** CI is reproducible, least-privilege, and covers every
mandatory non-secret verification path.

## Gate 2: AI API Deprecations

**Files:**

- Modify: `backend/ai_api/src/lexiquest_ai/errors.py`
- Modify: `backend/ai_api/pyproject.toml`
- Modify: `backend/ai_api/uv.lock`
- Verify: `backend/ai_api/tests/`

1. Reproduce each deprecation with warnings promoted to errors.
2. Replace the renamed HTTP 422 constant without changing its numeric contract.
3. Adopt the supported TestClient transport dependency and refresh only the AI
   API lockfile.
4. Run the AI suite with deprecation warnings promoted to errors.

**Pass condition:** All AI API tests pass with zero deprecation warnings.

## Gate 3: Flutter Dependency Modernization

**Files:**

- Modify: `pubspec.yaml`
- Modify: `pubspec.lock`
- Verify: Flutter tests and Android debug build

1. Upgrade `camera` to the current resolvable major version.
2. Review its official changelog and adapt one affected source file at a time.
3. Run analysis, tests, and Android build.
4. Upgrade `google_mlkit_image_labeling` separately.
5. Repeat analysis, tests, and Android build.
6. Document SDK-pinned transitive packages that cannot safely be forced.

**Pass condition:** Every resolvable direct dependency is current and no
dependency override hides an SDK constraint.

## Gate 4: Built-in Kotlin Compatibility

**Files:**

- Modify if required: `android/settings.gradle.kts`
- Modify if required: `android/app/build.gradle.kts`
- Verify: plugin warning output and Android debug build

1. Compare the project with the current Flutter Built-in Kotlin migration
   contract.
2. Remove obsolete app-owned Kotlin Gradle plugin configuration only when the
   app no longer needs it.
3. Distinguish app-owned configuration from upstream plugin warnings; never
   patch the package cache.
4. Rebuild and record any upstream-only compatibility exception with package
   and version.

**Pass condition:** LexiQuest owns no obsolete Kotlin configuration, and all
remaining warnings have an explicit upstream owner and upgrade path.

## Gate 5: Dependency and Repository Security

**Files:**

- Create: `.github/dependabot.yml`
- Create: security scan artifacts under the scanner-selected report directory
- Modify: validated vulnerable files only

1. Audit Dart, Python, npm, and Android dependency graphs.
2. Add automated dependency update coverage for each maintained ecosystem.
3. Run the standard repository security workflow:
   threat model, finding discovery, validation, attack-path analysis, and final
   report.
4. Fix validated high-confidence findings in minimal, test-driven patches.
5. Re-run dependency audits and targeted regression tests.

**Pass condition:** No unresolved critical/high validated finding, no known
fixable production dependency vulnerability, and remaining risks are documented.

## Gate 6: Release Candidate Verification

**Files:**

- Modify: `docs/PRODUCTION_FOUNDATION.md`
- Modify: PR description/checklist

1. Run `tool/cli/verify.ps1` from a clean working tree.
2. Re-run warning-as-error and dependency audit commands.
3. Review the complete branch diff for accidental secrets, generated artifacts,
   and unrelated files.
4. Commit and push each independently verified gate.
5. Confirm the PR check rollup is green.

**Pass condition:** Local verification, security gates, dependency gates, and
GitHub checks all pass against the same commit.
