# Commercial readiness, 2026-11-02

Status: integration verification in progress; production rollout not authorized.
Worktree: `C:\Users\Phet\.codex\worktrees\cycle12-release\LexiQuest`.
Branch: `codex/remaining-system-readiness`; starting source `8ec037c0`.

## First release policy

The user chose a quota-based managed-AI subscription and delegated product
defaults. The proposed first offer is THB99/month, product
`lexiquest_ai_monthly`, base plan `monthly`, policy revision `managed-ai-v1`,
with10 managed-generation units per UTC day. This is an engineering/product
proposal, not evidence of a configured or approved Play offer. The application
shows the actual localized Play SDK price and server quota before purchase.
Ordinary offline learning remains free. Gemini BYOK and native TTS are separate.

A unit is reserved when the service accepts a new managed request. An uncertain
provider outcome can retain that reservation;10 units do not promise10
successful answers. Auth retry preserves the operation ID. A new manual lesson
request can use a new operation ID and consume a new unit. Do not advertise a
free manual retry after an uncertain result.

The included12-word English/Thai starter pack can be previewed and explicitly
installed without a content server. It uses the existing codec and canonical
install writer; viewing the catalog creates no owner data. Authored answers are
distributed across three option positions. Provenance remains AI-assisted,
editorial-pending, with A1 as the declared target rather than a certification.

## Current engineering evidence

Evidence root:
`D:\LexiQuest-Storage\maintenance\2026-11-02\commercial-readiness`.

| Unit | Current evidence | Disposition |
| --- | --- | --- |
| Native-only speech with managed AI | config/factory129PASS; real AI-only bootstrap1PASS | Accepted; `bfc2107e` |
| Voice health with rejected GPU runtime | real RED then full CPU82PASS | Accepted; `de7e3a2f` |
| Membership catalog/UI | combined billing/starter78PASS; full AI backend463PASS | Accepted; `cc251a7b` |
| Starter pack and actual learning routes | broader pack/bootstrap331PASS, including small-screen/large-text tests | Accepted; `d3da6792` |
| Analysis | `analysis-corrected.log`,0 issues after one braces lint correction | Passed on current Dart source |
| Backend evidence collector | root duplicate-key regression60PASS on PS5.1 and PS7 | Independent review accepted |
| Release configuration | root `release-config-root-duplicates.log`,55PASS | Independent review accepted |
| CPU AI image | actual build and `ai-container/smoke-optional-json.json` | Independent review accepted; provider/production acceptance false |

The CPU image is
`sha256:0b67fe4fab7b3a967d319209d23276a2ed5d678f04c991a0cc8c8402d2cb1531`.
The smoke test used UID/GID65532, no network, read-only root, no host mounts or
credentials, and verified cleanup of its exact task container. HTTP results:
live200, ready503/PROVIDER_UNAVAILABLE, docs404, missing bearer401. No GPU/model
packages were installed. The first two smoke attempts failed before container
creation on Windows executable discovery and omitted Docker JSON properties;
their logs are preserved. See the backend README for build and smoke commands.

The catalog remains8 domains/44 capabilities and schema25/45 tables. No new
migration or parallel entitlement/learning/reward authority was introduced.
Final full regression, exact-source Android artifact and isolated-emulator
evidence are still pending in this checkpoint.

## Configure and accept a real managed service

Use a real HTTPS AI origin. Native-only voice needs no remote Voice URL.
For the chosen policy, the existing server settings are:

```text
LEXIQUEST_AI_BILLING_ENABLED=true
LEXIQUEST_AI_BILLING_MANAGED_CONTENT_REQUIRED=true
LEXIQUEST_AI_BILLING_PACKAGE_NAME=com.lexiquest.app
LEXIQUEST_AI_BILLING_POLICY_REVISION=managed-ai-v1
LEXIQUEST_AI_BILLING_PRODUCTS_JSON=[{"productId":"lexiquest_ai_monthly","basePlanId":"monthly","entitlements":["managedContent"],"dailyManagedUnits":10}]
```

Set the account-binding key through a versioned secret reference. Configure the
actual RTDN audience/service-account identity and least-privilege Play publisher
access. Do not put secret values in release JSON, command arguments or Git.
Select and test an available provider/model with real service credentials before
opening paid access. The bundled development provider defaults are not a
production provider acceptance result.

The public release JSON uses schemaVersion1 with exactly these fields:
`packageName`, `version`, `minimumPreviousVersionCode`, `aiApiUrl`, `voiceMode`,
`voiceApiUrl`, `cloudSyncEnabled`, `contentReportsEnabled`, and `billing`.
Use `voiceMode=native`, `voiceApiUrl=null`; billing contains `enabled=true`,
`policyRevision` and the product array above. Version must exceed the actual
previous Play version. The locally retained baseline is18; it does not establish
the current Play Console version. The validator rejects placeholders, private
origins and unknown/secret fields.

Build both artifacts with one reviewed configuration:

```powershell
./tool/cli/package-field-release.ps1 -Version <approved-version> -ReleaseProfile publicProduction -ConfigurationPath <approved-public-json>
```

The packager binds the source commit and full canonical configuration hash to
the APK/AAB build ID. Collect actual authenticated backend policy after the
service is approved and available:

```powershell
./tool/cli/collect-commercial-backend-policy.ps1 -ConfigurationPath <approved-public-json> -OutputDirectory <new-private-evidence-root> -IdTokenEnvironmentVariable <token-environment-variable-name>
```

The collector makes a GET to `/v1/billing/catalog`, never a purchase or deployment.
It rejects redirects, wrong origins, oversized/malformed/duplicate-key JSON,
reflected credentials and mismatched policy. It publishes exactly three private
files atomically. Keep their relative references under this output root.
A complete interrupted `.pending` directory is revalidated and published without
another HTTP request or token. Partial/foreign staging is preserved and refused;
inspect it and choose a fresh output path rather than overwriting it.

Public release acceptance additionally needs hash-bound actual Play license-test
or production journey records for localized offers, pending/verified purchase,
native completion, restore, account switch, cancellation/revocation, RTDN,
quota exhaustion/retry, export/deletion and upgrade migration. The collector
does not manufacture these records or merchant approval. Keep private backend
account identifiers and raw evidence out of Git.

## Remaining rollout dependencies

The configured Cloud project was inspected read-only; Cloud Run API is disabled.
No API was enabled and no service was deployed. A production HTTPS origin,
merchant/product activation, provider acceptance and the latest actual Play
version have not been established. The isolated offline Android emulator is a
synthetic test surface, not physical-device/TalkBack/store UAT.

Research remains default-off until trusted authority and rollout permission are
supplied. The project-approved GPU stack remains rejected; native TTS is the
first-release voice path. No real purchase, enrollment or research upload has
been performed. AGENTS.md section6 states: “Do not deploy, publish, enroll
participants, upload real research data, or perform destructive cleanup merely
because implementation is authorized.”

Pre-existing dirty files in the Documents checkout, untracked critiques and test
failure artifacts are preserved. Three previously denied cache cleanups remain
untouched. Do not delete signed artifacts or failed-run evidence as a substitute
for a verified duplicate cleanup.
