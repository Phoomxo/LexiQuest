# Configure and verify Android membership

This runbook describes the implemented configuration boundary. It does not record
a merchant activation, successful store purchase, deployment or release approval.
Billing defaults off in both the app and backend.

## Configure the backend

Use the AI API's existing Firebase identity and Application Default Credentials
configuration. The service identity needs the intended Play publisher and
Firestore access. Keep credentials and account-binding material in server secret
configuration, outside source control and app assets.

| Environment variable | Required value when enabling billing |
| --- | --- |
| `LEXIQUEST_AI_BILLING_ENABLED` | `true` |
| `LEXIQUEST_AI_BILLING_MANAGED_CONTENT_REQUIRED` | `true` to require paid managed-content access at the provider boundary |
| `LEXIQUEST_AI_BILLING_PACKAGE_NAME` | The exact Android package; current app is `com.lexiquest.app` |
| `LEXIQUEST_AI_BILLING_POLICY_REVISION` | An explicit immutable revision for the selected product policy |
| `LEXIQUEST_AI_BILLING_PRODUCTS_JSON` | A list of1..32 exact product/base-plan mappings described below |
| `LEXIQUEST_AI_BILLING_ACCOUNT_BINDING_KEY` | A stable server-only secret of32..256 UTF8 bytes |
| `LEXIQUEST_AI_BILLING_AUTHORITY_MAX_AGE_SECONDS` |1..3600; default300 |
| `LEXIQUEST_AI_BILLING_VERIFICATION_REQUESTS_PER_MINUTE` |1..120 per authenticated UID per UTC minute; default20 |
| `LEXIQUEST_AI_BILLING_RTDN_AUDIENCE` | The exact authenticated HTTPS notification audience |
| `LEXIQUEST_AI_BILLING_RTDN_SERVICE_ACCOUNT_EMAIL` | The expected Pub/Sub push identity ending in `.gserviceaccount.com` |

Each product mapping has exactly `productId`, `basePlanId`, `entitlements`, and
`dailyManagedUnits`. Use actual store identifiers and an approved quota. The
managed-content gate requires the `managedContent` entitlement. Product prices
come from the store SDK. No production product, price or quota is supplied by the
synthetic test fixtures. Production configuration requires both RTDN fields.

Keep the binding secret stable: changing it changes the obfuscated account
identifier used to associate purchases with a Firebase UID. A secret rotation
needs an explicit purchase-migration design before rollout.

## Configure the app and endpoints

The Android build accepts `--dart-define=LEXIQUEST_BILLING_ENABLED=true`.
Its existing `aiApiBaseUri` must point to the configured service. Firebase must
initialize successfully. The production composition enables purchasing only on
Android, and requires the current registered Firebase account and local owner.

| Endpoint | Purpose |
| --- | --- |
| `GET /v1/billing/catalog` | Server product allowlist and obfuscated account identifier |
| `POST /v1/billing/play/verify` | Verify the original purchase token against Play |
| `GET /v1/billing/entitlements` | Read current server-verified rights |
| `POST /v1/billing/play/notifications` | Authenticated Pub/Sub notification; refetch current Play state |
| `POST /v1/content` | Enforce rights/quota when required, using `Idempotency-Key` |

The server owns `billing_accounts`, `billing_purchases`, `billing_usage` and
`billing_usage_windows`. Client Firestore access is denied. The account export
and deletion inventory includes these namespaces. No raw purchase token is
retained in those documents.

## Collect release evidence

Use the intended signed build and authorized store test account to verify
localized offers, pending purchase, server verification, native completion,
restore, account switching, cancellation/revocation and RTDN delivery. Exercise
the real Firestore transaction path and account export/deletion before activation.
The local synthetic and emulator tests do not establish these external results.

For managed content, retry the same request identity after an interrupted
acknowledgement. A completed request returns its stored result. A submitted
request with an uncertain outcome must not automatically call the provider again.
Verify both quota exhaustion and repeated invalid verification-token limiting.

Keep billing disabled until the merchant configuration and this external evidence
are available and rollout is explicitly authorized. Ordinary learning remains
available when the optional billing composition cannot initialize.
