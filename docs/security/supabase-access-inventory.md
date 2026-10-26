# Supabase client access inventory

Date: 2026-10-26

## Current source truth

The Flutter application has **no runtime data callers** for Supabase. Source inspection finds no `Supabase.instance`, Storage, Postgres table, RPC, Realtime or Supabase Auth operation under `lib/`.

`AppBootstrap` can initialize `supabase_flutter` from `LEXIQUEST_SUPABASE_URL` and `LEXIQUEST_SUPABASE_PUBLISHABLE_KEY`, then records only `ready`, `degraded` or `unavailable` runtime status. A valid key changes initialization status; it does not fetch marketplace images or other data. Shop and wallpaper behavior use the local reward catalog and existing application authorities.

## Local infrastructure contract

The repository retains an isolated Supabase Storage policy for possible future use:

- `supabase/migrations/20260727000000_image_bucket_public_readonly.sql`
- `test/security/supabase_storage_contract.sql`
- the pinned Supabase CLI workflow in `.github/workflows/ci.yml`

The local contract creates the public-read `Image` bucket and denies anonymous/authenticated insert, update and delete. This proves only the version-controlled local policy; it does not prove a remote project, deployed parity or an application caller.

## Release disposition

The marketplace remains **local-only even when** `LEXIQUEST_SUPABASE_PUBLISHABLE_KEY` is present. Release documentation and UI must not claim remote Supabase images work.

Adding a runtime caller is separate product work. It requires an explicit feature decision, remote project selection, owner-approved publishable-key provisioning, deployed policy parity, data-flow/privacy review and tests showing public reads succeed while client writes fail. A service-role key must never enter the app, build arguments, repository, logs or release evidence.
