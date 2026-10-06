\set ON_ERROR_STOP 0
\echo '== setup: a CREATEROLE, non-superuser role standing in for hosted Supabase postgres'
SELECT version();
CREATE ROLE proj_postgres LOGIN CREATEROLE NOSUPERUSER;
GRANT CREATE ON DATABASE postgres TO proj_postgres;
SET ROLE proj_postgres;
CREATE SCHEMA app;
CREATE TABLE app.jobs (id int);
\echo '== 1. create the NOLOGIN owner role'
CREATE ROLE sa_owner NOLOGIN;
\echo '-- memberships of sa_owner right after creation'
SELECT m.roleid::regrole AS role, m.member::regrole AS member, m.grantor::regrole AS grantor, m.admin_option, to_jsonb(m) ? 'set_option' AS has_set_col, to_jsonb(m)->>'inherit_option' AS inherit, to_jsonb(m)->>'set_option' AS set FROM pg_auth_members m WHERE m.roleid = 'sa_owner'::regrole;
\echo '== 2. give it a SECURITY DEFINER function'
GRANT USAGE ON SCHEMA app TO sa_owner;
GRANT SELECT ON app.jobs TO sa_owner;
CREATE FUNCTION app.job_count() RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$ SELECT count(*) FROM app.jobs $$;
ALTER FUNCTION app.job_count() OWNER TO sa_owner;
SELECT p.oid::regprocedure, p.proowner::regrole FROM pg_proc p WHERE p.proname = 'job_count';
\echo '== 3. remove proj_postgres membership in sa_owner'
REVOKE sa_owner FROM proj_postgres;
SELECT count(*) AS memberships_left FROM pg_auth_members WHERE roleid = 'sa_owner'::regrole;
\echo '== 4. what proj_postgres can still do afterwards'
\echo '-- re-grant itself membership'
GRANT sa_owner TO proj_postgres;
SELECT count(*) AS memberships_after_regrant FROM pg_auth_members WHERE roleid = 'sa_owner'::regrole;
REVOKE sa_owner FROM proj_postgres;
\echo '-- replace the function body'
CREATE OR REPLACE FUNCTION app.job_count() RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$ SELECT 42::bigint $$;
\echo '-- change its owner back'
ALTER FUNCTION app.job_count() OWNER TO proj_postgres;
\echo '-- drop the role'
DROP ROLE sa_owner;
\echo '-- function still owned by'
SELECT p.proowner::regrole AS owner FROM pg_proc p WHERE p.proname = 'job_count';
RESET ROLE;
