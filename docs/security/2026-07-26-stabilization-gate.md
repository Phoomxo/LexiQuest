# LexiQuest Stabilization Security Gate

Date: 2026-07-26
Branch: `feature/production-vertical-slices`

## Decision

The local code and dependency stabilization gate is green. Production release
remains conditional on two external controls that cannot be proven from this
repository:

1. compare the repository Firestore policy with the deployed project and
   capture/test the currently deployed Supabase RLS policies;
2. start and complete the native Codex Security workspace scan.

The GitHub-hosted checks must also run against the pushed commit before merge.

## Verified locally

- `tool/cli/verify.ps1`: PASS across all 12 phases.
- Flutter: static analysis clean; 561 tests passed; Android debug APK built.
- Voice API: 36 tests passed.
- AI API: 74 tests passed.
- Local LM: 72 tests passed.
- Live GPU doctor: RTX 3050 available; no training process was modified or
  started.
- OSV-Scanner: six dependency manifests scanned; no unfiltered findings.
- Gitleaks 8.30.1: scanned all 165 commits in the repository history; no
  unapproved secrets found.
- GitHub Actions: every workflow passes `actionlint`; action references are
  immutable SHA pins.
- Hugging Face Space: dependency resolution and OSV scan pass; cached
  Qwen2.5-0.5B loaded offline and the authenticated request boundary was
  exercised without retraining.

## Security changes

- Replaced the Hugging Face Space's bearer-prefix soft gate with
  cryptographic Firebase ID-token verification. Missing configuration fails
  readiness closed.
- Added a self-contained, non-root Hugging Face Docker Space with a
  digest-pinned Python base image, health check, pinned dependencies, and
  deployment contract tests.
- Bounded Hugging Face prompt and generation tokens, enabled tokenizer
  truncation, and cached the Firebase verifier while handling initialization
  races.
- Removed all executable `trust_remote_code=True` model loads. Current
  Transformers supports the Qwen2.5 model family natively.
- Hardened AI provider URLs: remote endpoints require HTTPS; HTTP is restricted
  to loopback; malformed URLs and embedded user credentials are rejected
  without echoing secrets.
- Suppressed Firebase decoder exception chaining in both Python APIs so
  malformed token contents cannot reach traceback collectors.
- Converted unexpected Flutter AI transport exceptions to the privacy-safe
  typed network failure.
- Removed the developer-specific Firebase service-account path and hard-coded
  database URL from the seed script. It now uses Application Default
  Credentials, exports its function, has no write-on-import behavior, and
  returns a failing CLI exit code when seeding fails.
- Android release traffic is explicitly HTTPS-only; application backup is
  disabled; the unused legacy external-storage permission was removed; camera
  and microphone hardware are optional install capabilities.
- Android release artifacts no longer reuse the debug key. Release builds fail
  closed until a gitignored release keystore is configured; debug builds remain
  operational.
- Removed the unused `mailer` client dependency and its three transitives.
- Added Gitleaks CI, OSV PR/scheduled scans, Dependabot coverage across nine
  update configurations spanning seven package ecosystems, and CPU-safe source
  security contract tests.
- Added version-controlled Firestore and Storage rules plus Firebase deployment
  configuration. Firestore syntax was accepted by the local emulator; neither
  policy is considered deployed until the target project is verified.

## Secret-scanning policy

`.gitleaks.toml` extends the standard ruleset and uses path-plus-pattern
allowlists only for intentionally public mobile configuration and documented
scanner false positives:

- FlutterFire-generated Firebase client API identifiers;
- the Supabase publishable anonymous client key;
- four documented scanner false positives in tests, training scripts, or
  local preference keys.

Firebase client keys and Supabase publishable keys are not server credentials.
They still require Firebase Security Rules, Google API restrictions, and
Supabase RLS. No service-account private key, provider key, personal token, or
runtime Firebase ID token is approved for source control.

## Dependency exceptions

Two npm findings remain narrowly filtered until 2026-10-26:

- `GHSA-mh99-v99m-4gvg`: `brace-expansion` is present in the dependency tree
  only through the Firestore/google-gax cleanup chain, which the runtime does
  not import; the sole project consumer of that tree is the offline seed
  utility.
- `GHSA-w5hq-g745-h8pq`: `uuid` is present in the dependency tree only through
  the optional `@google-cloud/storage` package, which the Firestore-only seed
  utility never imports or calls.

No package override is used. Remove each exception as soon as Firebase Admin
ships a corrected dependency tree.

## Upstream compatibility exception

The app itself uses Flutter's Built-in Kotlin migration pattern. Four external
plugins still apply the Kotlin Gradle Plugin:

- `firebase_storage`
- `flutter_tts`
- `fluttertoast`
- `speech_to_text`

The settings-level Kotlin plugin pin and `android.builtInKotlin=false` must
remain until those plugins publish Built-in Kotlin-compatible releases.
Removing the compatibility switch now breaks the Android build.

## Outstanding production controls

- `firestore.rules` and `firebase.json` now capture a least-privilege,
  default-deny policy derived from the client access inventory. Deployment and
  emulator/live-project verification remain a release gate because the remote
  rules may still differ from this reviewed repository policy.
- Supabase RLS migrations/policies are absent. Confirm the public image bucket
  and every table are read/write scoped as intended.
- The native Codex Security workspace
  `54bd568b-56a7-40cc-8121-1594465b1046` is valid but still has
  `setup.submitted=false`; the user must press **Start scan** in that workspace.
- Docker Desktop was not running, so the Space image could not be built
  locally. The Dockerfile was statically tested, its base digest was resolved
  from the registry, and the Python app was executed locally.
- Before a public app-store release, register a permanent production Android
  application ID in Firebase and provide its matching `google-services.json`.
  The current Firebase registration still uses the scaffold
  `com.example.vocab_learning_app` identifier.
- Generate and securely retain the Android upload/release key, then populate
  the gitignored `android/key.properties` from the committed example.
- Workflows are new on this branch. GitHub checks are not considered green
  until the pushed PR commit receives their results.

## Release criteria

Merge only when the same commit satisfies:

1. local `tool/cli/verify.ps1`, OSV, Gitleaks, and `actionlint` remain green;
2. GitHub CI, OSV, and Gitleaks checks complete successfully;
3. Firestore rules match the target project and Supabase RLS is captured and
   tested;
4. the native Codex Security scan completes with no unresolved high-impact
   finding;
5. the two OSV exceptions remain justified and unexpired;
6. `.zcode/`, credentials, local environments, checkpoints, and generated
   runtime artifacts are absent from the commit.
