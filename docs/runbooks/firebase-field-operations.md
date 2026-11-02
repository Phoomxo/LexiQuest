# Firebase field operations

This runbook is an operational gate. It does not grant permission to enable
paid cloud usage. LexiQuest remains usable from Drift when every Firebase
control below is disabled.

## App Check rollout

1. Development and emulator builds may set
   `--dart-define=LEXIQUEST_APP_CHECK_DEBUG=true`. Register only the generated
   debug token used by the owner test device and revoke it after testing.
2. Release builds must omit that define. The app activates Play Integrity.
3. Register package `com.lexiquest.app`, the release SHA-256 certificate, and
   Play Integrity in Firebase before the owner smoke test.
4. Observe valid/invalid App Check traffic with enforcement off.
5. Enforce Firestore only after the release-signed APK completes the full
   offline/online journey. Auth is protected by its own provider controls.
6. If rejection or cost anomalies occur, set the server cloud policy to
   disabled and distribute a build with
   `LEXIQUEST_CLOUD_SYNC_ENABLED=false`. Local learning and pending outbox
   records remain available.

## Billing mode

Record exactly one mode in release evidence:

- `noBillingAccount`: remain on Spark/no billing, set alerts to false and
  not-applicable to true, and verify truthful quota-exhaustion behavior.
- `budgeted`: attach billing only with explicit cost authority, configure
  actual-spend alerts at 50%, 80% and 100%, and document quota/kill-switch
  ownership. A budget sends alerts; it is not a hard spending cap.

Route any alerts to an owner-controlled private channel. Do not put email,
webhook secrets or billing credentials in this repository. Gemini BYOK,
Supabase and Play costs are separate from the Firebase billing record.

## Android App Link

The manifest accepts Firebase Hosting email-action links at:

`https://vocab-learning-app-219ef.firebaseapp.com/__/auth/links`

Firebase may deliver this path as a wrapper whose `link` parameter contains
the percent-encoded Firebase action handler at
`https://vocab-learning-app-219ef.firebaseapp.com/__/auth/action`. The app
decodes that parameter once, then requires HTTPS, the exact project host, and
the exact handler path. A legacy flattened wrapper with `mode` and `oobCode`
on `/__/auth/links` remains supported.

`/auth/action` remains the state/continue URL supplied through
`ActionCodeSettings`. Only the app's relative internal route may use that
path directly. An absolute action or continue URL must use HTTPS and the exact
project host; untrusted hosts, user-info host confusion, alternate paths,
double encoding, duplicate action codes, and open redirects fail closed.

After release signing, publish `/.well-known/assetlinks.json` on that host with
the exact release certificate SHA-256 and package `com.lexiquest.app`. Confirm
with Android `pm verify-app-links` and a real Firebase verification/reset email.
The deterministic accepted/rejected contract lives in
`test/fixtures/email_action_links.json`. Invalid or expired codes fail closed.

## Cost boundary

- Emulator tests and local Drift are the default.
- Gemini remains participant BYOK and is unrelated to the Firebase budget.
- Do not enable Firebase paid products for the 30-person trial without an
  explicit owner acceptance record.

## Production account-deletion export

Account deletion is default-off. The only accepted production export
authority is `gcp-kms-hmac-sha256-v1`; an unknown value or an incomplete
bucket, KMS key-version, retention, or recovery configuration must fail
closed. If new deletion requests are enabled but the service cannot be
composed, `/health/ready` must return 503. Turning off new requests must not
remove the service needed to recover an already committed operation.

Set the runtime configuration through the deployment secret/configuration
layer, not a committed `.env` file:

- `LEXIQUEST_AI_ACCOUNT_DELETION_ENABLED` controls only new requests;
- `LEXIQUEST_AI_ACCOUNT_DELETION_SERVER_EXPORT_AUTHORITY` must be exactly
  `gcp-kms-hmac-sha256-v1`;
- `LEXIQUEST_AI_ACCOUNT_DELETION_EXPORT_BUCKET` and
  `LEXIQUEST_AI_ACCOUNT_DELETION_EXPORT_KMS_KEY_VERSION` identify the private
  bucket and the active full CryptoKeyVersion resource name;
- `LEXIQUEST_AI_ACCOUNT_DELETION_EXPORT_TRUSTED_KMS_KEY_VERSIONS` is an
  optional comma-separated allowlist of exact retired CryptoKeyVersion names
  that remain trusted only while old receipts/verifiers are recoverable;
- `LEXIQUEST_AI_ACCOUNT_DELETION_EXPORT_RETENTION_SECONDS` must be at least
  `LEXIQUEST_AI_ACCOUNT_DELETION_RECOVERY_RETENTION_SECONDS`; and
- `LEXIQUEST_AI_ACCOUNT_DELETION_EXPORT_MAXIMUM_DOCUMENTS` and
  `LEXIQUEST_AI_ACCOUNT_DELETION_EXPORT_MAXIMUM_BYTES` bound synchronous work.

Any unknown authority, malformed resource name, partial configuration, or
retention mismatch prevents production composition. Application Default
Credentials must resolve to the reviewed runtime service account; do not use a
downloaded service-account key in the repository or application image.

Before enabling the authority, provision and record all of the following as
deployment evidence. Do not put credentials or key material in this repository.

- A private GCS bucket with public access prevented. The runtime identity may
  create an object only when absent and read that exact export for replay
  verification; it must not be able to make exports public. Object names and
  metadata must not contain a UID, owner label, email, or recovery secret.
- Cloud KMS HMAC-SHA256 key versions for the active key and every explicitly
  trusted recovery version. Grant the runtime identity only MAC-sign,
  MAC-verify, and key-version metadata access. The raw idempotency/recovery key
  is converted to a domain-separated keyed verifier before persistence and is
  never stored in Firestore, the object, metadata, or logs. A legacy operation
  containing `idempotencyKey` is migrated atomically through KMS; unavailable
  KMS or malformed legacy state fails closed without deleting data.
- Firestore read/query/delete access only for the owner-isolated inventory
  below, Firebase Auth get/delete access for the exact UID, and no access to
  unrelated global content.
- The Firestore rules owner-write fence on
  `account_deletion_operations/{uid}`. Emulator coverage must show every
  owner-scoped writer and sync replay is rejected while reads, another owner,
  and UID-less shared vocabulary continue normally. Admin SDK writers bypass
  rules, so the IAM review must attest there is no independent privileged
  owner-data writer during deletion.
- Query-discovered owner documents must carry their Firestore `update_time`.
  Non-recursive deletes use `LastUpdateOption`; a recursive category root is
  transactionally owner-checked and claimed with the same precondition before
  descendants are removed. A lost race stops receipt attachment and Auth
  deletion.

The shared export-and-delete inventory follows `FIREBASE_ACCOUNT_DATA_SOURCES`:

- `field_users/{uid}/**` including descendants;
- `users/{uid}` and `state/{uid}`;
- `categories` documents whose `uid` equals the authenticated UID, including
  all descendants;
- `purchased_items` documents whose `user_id` equals that UID;
- `vocabulary` documents whose `uid` equals that UID;
- `billing_accounts`, `billing_purchases`, `billing_usage`, and
  `billing_usage_windows` documents whose `firebaseUid` equals that UID;
- `research_enrollments`, `research_consents`, and `research_study_archives`
  documents whose `firebaseUid` equals that UID; and
- `content_reports` and `content_report_limits` documents whose `firebaseUid`
  equals that UID.

Only `field_users` and `categories` include descendants. The snapshot reader
and deleter use the same inventory and validate queried owner fields.

It intentionally excludes `products`, `global_words`, `quiz`, and
`voice_telemetry_events`. Firebase Auth export is allowlisted to identity and
account status fields (UID, email and verification state, display name, phone,
photo, disabled/tenant state, provider identifiers, and creation/last-sign-in
timestamps). Password material, tokens, and custom claims are forbidden.

Each server export is canonical JSON written once under the operation ID.
Replays and uncertain upload outcomes must download the stored bytes, recompute
the digest, and verify the HMAC binding before deletion can continue. A body,
owner, UID, client receipt, recovery key, expiry, algorithm, or trusted key
version mismatch stops the operation; the object is never overwritten.

Use a seven-day recovery/export period unless the approved deployment record
specifies another positive value, and never exceed 30 days. Configure the GCS
lifecycle to delete expired export objects and ensure any bucket retention
policy protects them for the full recovery period without retaining them past
the approved bound. Keep `recoveryExpiresAtUtc` as the recovery deadline, but
do **not** configure TTL on it. Configure Firestore TTL only on the native
timestamp `purgeAtUtc`, which the service omits until `identityDeleted == true`.
This keeps the owner-write fence durable while Auth deletion or its
acknowledgement is pending. Legacy ISO recovery timestamps remain readable but
are not TTL evidence. Capture lifecycle/retention, terminal-only TTL, the
active and trusted KMS versions, IAM review, and synthetic create/replay/
tamper/expiry/lost-race tests in release evidence.

For the seven-day policy, verify actual bucket metadata records a retention
period of `604800` seconds. The runtime probe accepts retention periods from
zero through the configured export retention. A passing probe alone does not
prove the full recovery period is protected.

Before enabling TTL, record aggregate counts of terminal and nonterminal
`account_deletion_operations` documents, with `purgeAtUtc` classified as a native
timestamp, missing, or invalid. Verify that no nonterminal document carries
`purgeAtUtc`, and record the actual TTL field configuration. Serializer unit
tests do not prove the existing documents or deployed TTL configuration.
If a TTL-eligible timestamp belongs to real or unclassified data, leave the
policy disabled until that deletion scope is separately authorized. Report only
counts in evidence, without document IDs, UIDs, or account payloads.

For a configured deletion authority, `/health/ready` performs a cached runtime
attestation after earlier service-readiness checks pass. A failing attestation
returns 503. The attestation checks:

- Bucket metadata has enforced public-access prevention and uniform
  bucket-level access. A covering lifecycle Delete rule has an age from zero
  through the configured export retention. Bucket retention is within that
  same range, default event-based hold and versioning are disabled, and soft
  delete retention is zero.
- GCS `test_iam_permissions` returns both requested permissions,
  `storage.objects.create` and `storage.objects.get`. This request does not
  enumerate or reject additional permissions.
- Every trusted KMS version is enabled HMAC-SHA256 and passes MAC sign/verify.
- Firestore can get the reserved
  `account_deletion_operations/__readiness__` document, query a reserved UID in
  `categories`, and delete the reserved document with `ExistsOption(False)`.
  That precondition prevents deletion if the document exists.
- Firebase Auth `get_user` returns user-not-found for a reserved UID. The probe
  does not call Auth delete or prove Auth delete permission.

Provider readiness runs first. With LLM models off, `/health/ready` returns
`PROVIDER_UNAVAILABLE` before the deletion attestation. While models remain off,
run the account-deletion readiness probe directly with the actual cloud
configuration and reviewed runtime identity. Record that result separately.
Review effective IAM metadata for Auth delete authority and excess permissions
across all resources. The probe is default-off with the deletion authority and
does not replace IAM, lifecycle, retention, TTL, or rollout evidence.
Every new deletion request must pass the same cached attestation before the
tombstone is claimed; direct or in-flight traffic cannot bypass a failed health
probe. Recovery remains available to finish an already committed operation.

Local tests and emulator data do not authorize live deletion. Enabling the
production authority, changing IAM, provisioning paid resources, or deleting
real account data still requires the owner-approved rollout record.

## Cloud kill switch

Set the server cloud policy to disabled first, then distribute a build with
`LEXIQUEST_CLOUD_SYNC_ENABLED=false` if provider access must stop completely.
Do not clear Drift or the outbox. Verify Quiz, SRS, reading, progress, rewards,
and export while cloud sync is disabled before declaring the kill switch ready.
