# Supabase Client Access Inventory

Date: 2026-07-27
Branch: `feature/production-vertical-slices`

## Scope summary

- Five files under `lib/` reference Supabase.
- Two files perform Supabase data access:
  `lib/screens/shop_page.dart` and
  `lib/screens/select_wallpaper_screen.dart`.
- No Postgres table, RPC, Realtime, or Supabase Auth operation exists.
- The only accessed Storage bucket is `Image`.
- No Supabase key value is committed. Production requires an explicit
  `sb_publishable_...` client key; no service-role key is present.

## Initialization and identity

`lib/runtime/app_bootstrap.dart` initializes Supabase from
`LEXIQUEST_SUPABASE_URL` and `LEXIQUEST_SUPABASE_PUBLISHABLE_KEY`. The public
URL retains a production default, but the publishable key has no source
default, must use the current `sb_publishable_...` format, and fails safely to
`RuntimeAvailability.unavailable` when missing or malformed. The app uses
Firebase Auth and never establishes a Supabase user session. Every Supabase
request therefore operates as the anonymous role and depends entirely on
deployed bucket policies and RLS.

`lib/runtime/app_runtime_status.dart` and
`lib/screens/main_navigation_screen.dart` only expose readiness state; they do
not access Supabase data.

## Storage operations

### Shop product images

- Source: `lib/screens/shop_page.dart`
- Call: `supabase.storage.from('Image').getPublicUrl(imageName)`
- Path: Firestore `products.image_name`, passed to the public URL builder.
- Trigger: fallback when a product has no `image_url` and has a non-empty
  `image_name`.
- Access: public read only; no upload, update, or delete.
- Authentication: no Supabase session. Firebase sign-in is not bound to this
  request.

### Purchased wallpaper images

- Source: `lib/screens/select_wallpaper_screen.dart`
- Call: `supabase.storage.from('Image').getPublicUrl(imageName)`
- Path: Firestore `products.image_name`.
- Trigger: a purchased product has no `image_url` and has `image_name`.
- Access: public read only; no upload, update, or delete.
- Authentication: the screen requires a Firebase user, but no Firebase token
  is exchanged for a Supabase identity. The generated object URL remains
  public.

Both call sites assume the `Image` bucket is publicly readable. Neither
requires anonymous write access.

## Structured data

All current structured product and purchase data is read or written through
Firestore, not Supabase Postgres. No Supabase table, function, Edge Function,
or Realtime channel is referenced by the Flutter client.

## Version-controlled storage contract

The repository now owns the Supabase storage contract; the prior "no
`supabase/` directory" gap is closed.

- `supabase/config.toml`: local-only project (`project_id = "lexiquest-local"`),
  PostgreSQL 17, ports on the 65430+ range because Windows reserves the
  default 543xx range. No project ref, key, password, or JWT secret is stored.
- `supabase/migrations/20260727000000_image_bucket_public_readonly.sql`
  idempotently owns the `Image` bucket (`public = true`) and the
  `storage.objects` policy set:
  - keeps RLS enabled on `storage.objects` (`ENABLE` only, never `FORCE`) so
    `service_role`/`superuser` callers retain their normal RLS bypass;
  - `image_bucket_public_read`: permissive `SELECT` to `anon`,
    `authenticated`, scoped exactly to `bucket_id = 'Image'`;
  - `image_bucket_deny_client_insert` / `_update` / `_delete`: restrictive
    policies to `anon`, `authenticated` with `USING/WITH CHECK (false)`.

The three restrictive policies intentionally deny all client writes to
`storage.objects` for `anon` and `authenticated`; only `service_role`/Admin
callers keep the normal RLS bypass. The root `storage.rules` file governs
Firebase Storage only and has no effect on Supabase.

## Local verification

- CI (`.github/workflows/ci.yml`) provisions Supabase CLI 2.109.1 via the
  SHA-pinned `supabase/setup-cli` action, runs `supabase db start` then
  `supabase db reset --local --no-seed`, runs schema lint and security
  advisors, executes the SQL contract through `psql` inside the local
  container, and runs `supabase stop --no-backup`.
- `test/security/supabase_storage_contract.sql` verifies, inside a rolled-back
  transaction, the `Image` bucket row, RLS on `storage.objects`, the four
  policies in `pg_policies` (permissive/restrictive, command, roles, exact
  `qual`), anon read of a sentinel, and anon/authenticated `INSERT` plus anon
  `UPDATE`/`DELETE` denial (`SQLSTATE 42501` or zero rows).
- Local evidence observed on this branch: `supabase db reset --local --no-seed`
  succeeds; reapplying the migration directly succeeds; the SQL contract
  passes. This is local proof, not a deployed result.

## Remote parity (release gate)

No production project has been linked or modified. Remote parity is a
pre-release gate that still requires user-owned auth/project selection and
rotation/provisioning of the current publishable key. It also checks that the
deployed project matches the version-controlled contract:
`Image` permits public reads only; anonymous uploads, updates, and deletes are
denied; unused buckets and tables are inaccessible to the anonymous role; and
every Postgres table has RLS enabled, even if the current app does not query
it.
