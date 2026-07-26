# Supabase Client Access Inventory

Date: 2026-07-26
Branch: `feature/production-vertical-slices`

## Scope summary

- Five files under `lib/` reference Supabase.
- Two files perform Supabase data access:
  `lib/screens/shop_page.dart` and
  `lib/screens/select_wallpaper_screen.dart`.
- No Postgres table, RPC, Realtime, or Supabase Auth operation exists.
- The only accessed Storage bucket is `Image`.
- The app has a publishable anonymous client key only; no service-role key is
  present.

## Initialization and identity

`lib/runtime/app_bootstrap.dart` initializes Supabase from
`LEXIQUEST_SUPABASE_URL` and `LEXIQUEST_SUPABASE_PUBLISHABLE_KEY`, with
production public-client defaults. The app uses Firebase Auth and never
establishes a Supabase user session. Every Supabase request therefore operates
as the anonymous role and depends entirely on deployed bucket policies and RLS.

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

## Missing server-side evidence

The repository contains no:

- `supabase/` migration or configuration directory;
- SQL migrations;
- `CREATE POLICY` or `ENABLE ROW LEVEL SECURITY` statement;
- version-controlled `storage.objects` policy.

The root `storage.rules` file governs Firebase Storage only and has no effect
on Supabase.

Consequently, this repository cannot prove that:

1. `Image` is intentionally public read but not public write;
2. the anonymous role cannot access other buckets or tables;
3. every deployed Supabase table has RLS enabled and a least-privilege policy.

## Required production verification

Export and version-control the deployed Supabase configuration. Confirm that:

- `Image` permits public reads only;
- anonymous uploads, updates, and deletes are denied;
- unused buckets and tables are inaccessible to the anonymous role;
- every Postgres table has RLS enabled, even if the current app does not query
  it.
