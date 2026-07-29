-- LexiQuest: public read-only Image bucket.
--
-- Establishes the storage.buckets row for the public Image bucket and the
-- client-facing RLS contract on storage.objects: anon/authenticated may read
-- objects in the Image bucket but must never insert, update, or delete them.
-- Service-role/Admin callers keep their normal RLS bypass (no FORCE).
-- Idempotent: safe to re-run via the Supabase CLI.

-- 1. Upsert the public Image bucket (name/public only; never touch owner).
INSERT INTO storage.buckets (id, name, public)
VALUES ('Image', 'Image', true)
ON CONFLICT (id) DO UPDATE
SET name = EXCLUDED.name,
    public = EXCLUDED.public;

-- 2. The Image bucket is the only public bucket in this release.
UPDATE storage.buckets
SET public = false
WHERE id <> 'Image' AND public = true;

-- 3. Remove broad policies left by the retired project before establishing
--    the production contract below.
DROP POLICY IF EXISTS "allow-delete-store-images 164ncr_0" ON storage.objects;
DROP POLICY IF EXISTS "allow-insert-store-images 164ncr_0" ON storage.objects;
DROP POLICY IF EXISTS "allow-select-store-images 164ncr_0" ON storage.objects;
DROP POLICY IF EXISTS "allow-update-store-images 164ncr_0" ON storage.objects;

-- 4. Keep RLS enabled on storage.objects. ENABLE only (never FORCE) so that
--    service_role / superuser callers retain their normal RLS bypass.
--    Conditional: the Supabase base schema already enables RLS on
--    storage.objects and owns the table, so a non-owner migration role cannot
--    run an unconditional ALTER (SQLSTATE 42501). Probe pg_class and only emit
--    the ALTER when RLS is not yet enabled; an unsafe base still fails loudly
--    because the ALTER then runs and surfaces the privilege error.
DO $$
DECLARE
    rls_enabled boolean;
BEGIN
    SELECT c.relrowsecurity
      INTO rls_enabled
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
     WHERE n.nspname = 'storage'
       AND c.relname = 'objects';

    IF rls_enabled IS NULL THEN
        RAISE EXCEPTION 'storage.objects not found; cannot verify RLS state';
    ELSIF rls_enabled = false THEN
        ALTER TABLE storage.objects ENABLE ROW LEVEL SECURITY;
    END IF;
END $$;

-- 5. Public read of the Image bucket, scoped exactly to bucket_id = 'Image'.
DROP POLICY IF EXISTS image_bucket_public_read ON storage.objects;
CREATE POLICY image_bucket_public_read
ON storage.objects
FOR SELECT
TO anon, authenticated
USING (bucket_id = 'Image'::text);

-- 6. Deny client inserts into storage.objects (RESTRICTIVE, false check).
DROP POLICY IF EXISTS image_bucket_deny_client_insert ON storage.objects;
CREATE POLICY image_bucket_deny_client_insert
ON storage.objects
AS RESTRICTIVE
FOR INSERT
TO anon, authenticated
WITH CHECK (false);

-- 7. Deny client updates of storage.objects.
DROP POLICY IF EXISTS image_bucket_deny_client_update ON storage.objects;
CREATE POLICY image_bucket_deny_client_update
ON storage.objects
AS RESTRICTIVE
FOR UPDATE
TO anon, authenticated
USING (false)
WITH CHECK (false);

-- 8. Deny client deletes from storage.objects.
DROP POLICY IF EXISTS image_bucket_deny_client_delete ON storage.objects;
CREATE POLICY image_bucket_deny_client_delete
ON storage.objects
AS RESTRICTIVE
FOR DELETE
TO anon, authenticated
USING (false);
