-- LexiQuest Supabase storage contract test.
--
-- Asserts the intended security contract for the public Image bucket and the
-- storage.objects table without creating any bucket or policy. A later
-- migration is the sole owner of:
--   * storage.buckets row id = 'Image' (name = 'Image', public = true)
--   * image_bucket_public_read        PERMISSIVE SELECT to anon, authenticated,
--                                     scoped to bucket_id = 'Image'
--   * image_bucket_deny_client_insert RESTRICTIVE INSERT to anon, authenticated
--   * image_bucket_deny_client_update RESTRICTIVE UPDATE to anon, authenticated
--   * image_bucket_deny_client_delete RESTRICTIVE DELETE to anon, authenticated
--
-- Every statement runs inside one transaction that is rolled back, so no rows
-- persist.
--
-- Run by piping this file to:
--   docker exec -i supabase_db_lexiquest-local psql -U postgres -d postgres
--     -v ON_ERROR_STOP=1 -f -

BEGIN;

-- Catalog state is read as the superuser connection role, before SET ROLE.

DO $$
DECLARE
    b record;
BEGIN
    SELECT * INTO b FROM storage.buckets WHERE id = 'Image';
    IF NOT FOUND THEN
        RAISE EXCEPTION 'storage.buckets row id=''Image'' is missing';
    END IF;
    IF b.name IS DISTINCT FROM 'Image' THEN
        RAISE EXCEPTION 'Image bucket name mismatch: got %', b.name;
    END IF;
    IF b.public IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'Image bucket public flag mismatch: got %', b.public;
    END IF;
END $$;

DO $$
DECLARE
    rls_on boolean;
BEGIN
    SELECT c.relrowsecurity INTO rls_on
    FROM pg_class c
    WHERE c.oid = 'storage.objects'::regclass;
    IF rls_on IS DISTINCT FROM true THEN
        RAISE EXCEPTION 'storage.objects RLS is not enabled (relrowsecurity=%)', rls_on;
    END IF;
END $$;

DO $$
DECLARE
    n int;
    qual_text text;
BEGIN
    SELECT count(*) INTO n
    FROM pg_policies p
    WHERE p.schemaname = 'storage'
      AND p.tablename = 'objects'
      AND p.policyname = 'image_bucket_public_read'
      AND p.permissive = 'PERMISSIVE'
      AND p.cmd = 'SELECT'
      AND p.roles @> ARRAY['anon', 'authenticated']::name[]
      AND cardinality(p.roles) = 2;
    IF n <> 1 THEN
        RAISE EXCEPTION 'image_bucket_public_read policy missing or misconfigured (matching rows=%)', n;
    END IF;

    SELECT COALESCE(p.qual, '') INTO qual_text
    FROM pg_policies p
    WHERE p.schemaname = 'storage'
      AND p.tablename = 'objects'
      AND p.policyname = 'image_bucket_public_read';
    IF qual_text IS DISTINCT FROM '(bucket_id = ''Image''::text)' THEN
        RAISE EXCEPTION 'image_bucket_public_read is not scoped exactly to the Image bucket (qual=%)', qual_text;
    END IF;

    SELECT count(*) INTO n
    FROM pg_policies p
    WHERE p.schemaname = 'storage'
      AND p.tablename = 'objects'
      AND p.policyname = 'image_bucket_deny_client_insert'
      AND p.permissive = 'RESTRICTIVE'
      AND p.cmd = 'INSERT'
      AND p.roles @> ARRAY['anon', 'authenticated']::name[]
      AND cardinality(p.roles) = 2;
    IF n <> 1 THEN
        RAISE EXCEPTION 'image_bucket_deny_client_insert policy missing or misconfigured (matching rows=%)', n;
    END IF;

    SELECT count(*) INTO n
    FROM pg_policies p
    WHERE p.schemaname = 'storage'
      AND p.tablename = 'objects'
      AND p.policyname = 'image_bucket_deny_client_update'
      AND p.permissive = 'RESTRICTIVE'
      AND p.cmd = 'UPDATE'
      AND p.roles @> ARRAY['anon', 'authenticated']::name[]
      AND cardinality(p.roles) = 2;
    IF n <> 1 THEN
        RAISE EXCEPTION 'image_bucket_deny_client_update policy missing or misconfigured (matching rows=%)', n;
    END IF;

    SELECT count(*) INTO n
    FROM pg_policies p
    WHERE p.schemaname = 'storage'
      AND p.tablename = 'objects'
      AND p.policyname = 'image_bucket_deny_client_delete'
      AND p.permissive = 'RESTRICTIVE'
      AND p.cmd = 'DELETE'
      AND p.roles @> ARRAY['anon', 'authenticated']::name[]
      AND cardinality(p.roles) = 2;
    IF n <> 1 THEN
        RAISE EXCEPTION 'image_bucket_deny_client_delete policy missing or misconfigured (matching rows=%)', n;
    END IF;
END $$;

-- Sentinel + client-role behavior.

-- Insert the probe object as the superuser; postgres bypasses RLS.
INSERT INTO storage.objects (bucket_id, name)
VALUES ('Image', 'contract/sentinel.txt');

SET LOCAL ROLE anon;

DO $$
DECLARE
    c int;
BEGIN
    SELECT count(*) INTO c
    FROM storage.objects
    WHERE bucket_id = 'Image' AND name = 'contract/sentinel.txt';
    IF c < 1 THEN
        RAISE EXCEPTION 'anon cannot read the Image sentinel (visible rows=%); public read policy failed', c;
    END IF;
END $$;

-- anon INSERT must be denied with SQLSTATE 42501.
DO $$
DECLARE
    denied boolean := false;
BEGIN
    BEGIN
        INSERT INTO storage.objects (bucket_id, name)
        VALUES ('Image', 'contract/anon-insert-attempt.txt');
    EXCEPTION WHEN insufficient_privilege THEN
        denied := true;
    END;
    IF NOT denied THEN
        RAISE EXCEPTION 'anon INSERT into the Image bucket was unexpectedly allowed (expected SQLSTATE 42501)';
    END IF;
END $$;

-- anon UPDATE must not change the sentinel (42501 or zero rows).
DO $$
DECLARE
    denied boolean := false;
    changed int := 0;
BEGIN
    BEGIN
        UPDATE storage.objects
        SET name = name
        WHERE bucket_id = 'Image' AND name = 'contract/sentinel.txt';
        GET DIAGNOSTICS changed = ROW_COUNT;
    EXCEPTION WHEN insufficient_privilege THEN
        denied := true;
    END;
    IF denied THEN
        NULL;
    ELSIF changed <> 0 THEN
        RAISE EXCEPTION 'anon UPDATE of the Image sentinel changed % row(s); expected denial', changed;
    END IF;
END $$;

-- anon DELETE must not remove the sentinel (42501 or zero rows).
DO $$
DECLARE
    denied boolean := false;
    removed int := 0;
BEGIN
    BEGIN
        DELETE FROM storage.objects
        WHERE bucket_id = 'Image' AND name = 'contract/sentinel.txt';
        GET DIAGNOSTICS removed = ROW_COUNT;
    EXCEPTION WHEN insufficient_privilege THEN
        denied := true;
    END;
    IF denied THEN
        NULL;
    ELSIF removed <> 0 THEN
        RAISE EXCEPTION 'anon DELETE of the Image sentinel removed % row(s); expected denial', removed;
    END IF;
END $$;

-- authenticated INSERT must be denied with SQLSTATE 42501.
SET LOCAL ROLE authenticated;

DO $$
DECLARE
    denied boolean := false;
BEGIN
    BEGIN
        INSERT INTO storage.objects (bucket_id, name)
        VALUES ('Image', 'contract/authenticated-insert-attempt.txt');
    EXCEPTION WHEN insufficient_privilege THEN
        denied := true;
    END;
    IF NOT denied THEN
        RAISE EXCEPTION 'authenticated INSERT into the Image bucket was unexpectedly allowed (expected SQLSTATE 42501)';
    END IF;
END $$;

ROLLBACK;
