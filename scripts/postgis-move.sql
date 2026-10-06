\set ON_ERROR_STOP 0
\echo '== setup: PostGIS in public, owned by supabase_admin (like hosted Supabase)'
CREATE ROLE supabase_admin SUPERUSER LOGIN;
CREATE ROLE app_owner LOGIN;            -- stands in for the project's non-superuser postgres role
CREATE SCHEMA extensions;
SET ROLE supabase_admin;
CREATE EXTENSION postgis SCHEMA public;
RESET ROLE;
SELECT extname, extversion, extrelocatable, extnamespace::regnamespace AS schema, extowner::regrole AS owner FROM pg_extension WHERE extname = 'postgis';
ALTER DATABASE postgres SET search_path = "$user", public, extensions;
SET search_path = "$user", public, extensions;
CREATE TABLE public.jobs (id serial PRIMARY KEY, location geography(Point, 4326));
CREATE INDEX idx_jobs_location ON public.jobs USING gist (location);
INSERT INTO public.jobs (location) VALUES (ST_MakePoint(28.97, 41.01)::geography), (ST_MakePoint(29.10, 41.05)::geography);
-- RPC styles seen in Supabase projects
CREATE FUNCTION public.jobs_nearby_plain(lng float, lat float, meters float) RETURNS SETOF public.jobs LANGUAGE sql STABLE
  AS $$ SELECT * FROM public.jobs WHERE ST_DWithin(location, ST_MakePoint(lng, lat)::geography, meters) $$;
CREATE FUNCTION public.jobs_nearby_pinned_public(lng float, lat float, meters float) RETURNS SETOF public.jobs LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
  AS $$ BEGIN RETURN QUERY SELECT * FROM public.jobs WHERE ST_DWithin(location, ST_MakePoint(lng, lat)::geography, meters); END $$;
CREATE FUNCTION public.jobs_nearby_pinned_both(lng float, lat float, meters float) RETURNS SETOF public.jobs LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public, extensions
  AS $$ BEGIN RETURN QUERY SELECT * FROM public.jobs WHERE ST_DWithin(location, ST_MakePoint(lng, lat)::geography, meters); END $$;
CREATE FUNCTION public.jobs_nearby_empty_path(lng float, lat float, meters float) RETURNS SETOF public.jobs LANGUAGE sql STABLE SET search_path = ''
  AS $$ SELECT * FROM public.jobs WHERE public.ST_DWithin(location, public.ST_MakePoint(lng, lat)::public.geography, meters) $$;

\echo '== 1. as a non-owner, non-superuser role (hosted Supabase postgres is in this position)'
GRANT CREATE ON SCHEMA extensions TO app_owner;
SET ROLE app_owner;
UPDATE pg_extension SET extrelocatable = true WHERE extname = 'postgis';
ALTER EXTENSION postgis SET SCHEMA extensions;
RESET ROLE;

\echo '== 2. plain ALTER EXTENSION as superuser (no relocatable flag)'
ALTER EXTENSION postgis SET SCHEMA extensions;

\echo '== 3. documented PostGIS procedure as superuser'
BEGIN;
UPDATE pg_extension SET extrelocatable = true WHERE extname = 'postgis';
ALTER EXTENSION postgis SET SCHEMA extensions;
ALTER EXTENSION postgis UPDATE TO "ANYNEXT";
ALTER EXTENSION postgis UPDATE;
UPDATE pg_extension SET extrelocatable = false WHERE extname = 'postgis';
COMMIT;
SELECT extname, extversion, extrelocatable, extnamespace::regnamespace AS schema FROM pg_extension WHERE extname = 'postgis';

\echo '== after the move'
SELECT format_type(atttypid, atttypmod) AS column_type, atttypid::regtype FROM pg_attribute WHERE attrelid = 'public.jobs'::regclass AND attname = 'location';
SELECT indexrelid::regclass, indisvalid FROM pg_index WHERE indrelid = 'public.jobs'::regclass AND indexrelid::regclass::text = 'idx_jobs_location';
SET enable_seqscan = off;
EXPLAIN (COSTS OFF) SELECT id FROM public.jobs WHERE ST_DWithin(location, ST_MakePoint(28.97, 41.01)::geography, 20000);
RESET enable_seqscan;
SELECT to_regclass('public.spatial_ref_sys') AS in_public, to_regclass('extensions.spatial_ref_sys') AS in_extensions;
SELECT ST_AsText(ST_Transform(ST_SetSRID(ST_MakePoint(28.97, 41.01), 4326), 3857)) AS transform_ok;
\echo '-- plain function'
SELECT count(*) AS plain FROM public.jobs_nearby_plain(28.97, 41.01, 20000);
\echo '-- SET search_path = public'
SELECT count(*) AS pinned_public FROM public.jobs_nearby_pinned_public(28.97, 41.01, 20000);
\echo '-- SET search_path = public, extensions'
SELECT count(*) AS pinned_both FROM public.jobs_nearby_pinned_both(28.97, 41.01, 20000);
\echo '-- SET search_path = empty, fully qualified public.ST_*'
SELECT count(*) AS empty_path FROM public.jobs_nearby_empty_path(28.97, 41.01, 20000);
\echo '-- functions pinning search_path without extensions (audit query)'
SELECT p.oid::regprocedure, p.proconfig FROM pg_proc p WHERE p.pronamespace = 'public'::regnamespace AND p.proconfig IS NOT NULL AND NOT EXISTS (SELECT 1 FROM unnest(p.proconfig) c WHERE c LIKE 'search_path=%extensions%');
