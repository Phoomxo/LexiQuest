# Configure the optional Research transport

Research defaults off in the app and AI API. This runbook describes the implemented
configuration interface; it does not establish ethics approval, validated
instruments, permission to enroll participants, deployment or research efficacy.

## Supply the trusted release inputs

Pass a `ResearchTransportConfiguration` to
`AppBootstrap.production(researchTransportConfiguration: configuration)`.
Its `availability` defaults to disabled. Supply the exact approved Motivation
protocol/instrument checksum, presentation catalog, distinct Assessment
definition/mapping/form-content authority, Ed25519 operation verifier, P-256
participation verifier, issuer/key identifiers, supported presentations, matching
consent notice, and approved participation-permit resolver for the current binding.
Protocol app/build metadata must match the actual build, including version suffixes.

The production adapter uses the current registered Firebase account and existing
local-owner binding. It advances a generation across account/owner transitions
and rechecks the binding around token acquisition. Missing identity, configuration
or authority prevents Research while ordinary learning remains available.
Do not supply synthetic signing keys, instruments or notices in a release build.

The backend uses its existing Firebase identity and Application Default
Credentials setup. These environment variables configure Research:

| Variable | Value |
| --- | --- |
| `LEXIQUEST_AI_RESEARCH_ENABLED` | `true` only for an authorized rollout |
| `LEXIQUEST_AI_RESEARCH_OPERATION_PUBLIC_KEYS_JSON` | Object mapping trusted key IDs to standard-base64 32-byte Ed25519 public keys; 1..32 entries |
| `LEXIQUEST_AI_RESEARCH_PARTICIPATION_PUBLIC_KEYS_JSON` | Object mapping trusted key IDs to uncompressed P-256 public keys as `04` plus 128 hexadecimal digits; 1..32 entries |
| `LEXIQUEST_AI_RESEARCH_AUTHORITY_MAX_AGE_SECONDS` | 1..3600, default300 |

Signing private keys remain outside the service/app source and assets. A server
response cannot introduce a new trusted public key.

## Provision through the authorized issuer

The app has no self-enrollment endpoint. An authorized administrative process
must supply `research_enrollments/{firebaseUid}` with the exact registered UID,
local owner, enrollment/revision, active interval, consent receipt/version,
protocol, and two distinct instrument scopes. Each scope contains its exact
requirements, issuer-signed operation/participation documents, current revocation
state, applicable receipts and archive pins. The server validates the closed
record shape in `ResearchService._authority`; unknown fields or contradictory
scope/owner/pin data fail closed. Use that parser as the schema authority.

The server owns `research_enrollments`, `research_consents` and
`research_study_archives`. Direct client Firestore reads and writes are denied.
The account export/deletion inventory includes all three namespaces. Do not
pre-create an accepted consent decision in place of the participant's action.

## Exercise the actual app flow

1. Open Settings → Research participation. Confirm the provisioned context and
   read the matching supplied notice. Explicit acknowledgement records the
   server's decision timestamp; browsing does not accept or import participation.
2. Explicitly refresh both instrument authorities. The paired gate opens only
   when both signed snapshots and current bindings are valid. Backgrounding or
   account changes retire the gate.
3. Explicitly activate the preprovisioned participation on this device. This
   imports the existing signed assignment/participation through the canonical
   local transaction; it does not create a server enrollment.
4. Complete the configured Study journey. Export Center's controlled one-cycle
   archive verifies separate current export grants. Dedicated upload verifies
   separate current upload grants and requires an explicit upload action.
5. Retry an uncertain upload with the retained request identity and exact bytes.
   Changed facts require a newly reviewed snapshot. Scoped Research disables the
   older owner-wide Research JSON format; personal exports remain available.
6. Withdraw from the authority page, Settings or the Study questionnaire. The
   local terminal barrier takes effect before the server request. An offline
   withdrawal reports pending acknowledgement and reconciles on explicit retry
   or the next authorized refresh; collection remains stopped locally.

The API routes are `GET /v1/research/enrollment-context`,
`POST /v1/research/consent`, `POST /v1/research/authority/refresh` and
`POST /v1/research/study-archives`. Uploads use the dedicated bounded endpoint,
not ordinary learning sync. Before rollout, record authorized real-service and
device evidence for consent/withdrawal, both instruments, stale/revoked authority,
cross-owner rejection, before/after linkage, upload retry, account export and
deletion. Local synthetic/emulator results do not establish those external facts.
