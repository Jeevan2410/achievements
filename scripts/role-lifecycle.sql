\set ON_ERROR_STOP 0
SELECT current_setting('server_version_num')::int >= 160000 AS pg16 \gset
SELECT version();
CREATE ROLE proj_postgres LOGIN CREATEROLE NOSUPERUSER;   -- stands in for hosted Supabase postgres
GRANT CREATE ON DATABASE postgres TO proj_postgres;
SET ROLE proj_postgres;
CREATE SCHEMA app;
CREATE TABLE app.jobs (id int);
CREATE ROLE sa_owner NOLOGIN;
GRANT USAGE, CREATE ON SCHEMA app TO sa_owner;
GRANT SELECT ON app.jobs TO sa_owner;
CREATE FUNCTION app.job_count() RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$ SELECT count(*) FROM app.jobs $$;
\echo '== A. memberships after CREATE ROLE'
SELECT m.member::regrole AS member, m.grantor::regrole AS grantor, m.admin_option, to_jsonb(m)->>'inherit_option' AS inherit, to_jsonb(m)->>'set_option' AS set FROM pg_auth_members m WHERE m.roleid = 'sa_owner'::regrole ORDER BY 2;
\echo '== B. temporary SET membership, then hand the function over'
\if :pg16
GRANT sa_owner TO proj_postgres WITH SET TRUE, INHERIT FALSE;
\else
GRANT sa_owner TO proj_postgres;
\endif
ALTER FUNCTION app.job_count() OWNER TO sa_owner;
SELECT p.proowner::regrole AS function_owner FROM pg_proc p WHERE p.proname = 'job_count';
\echo '== C. proj_postgres removes what it can'
REVOKE sa_owner FROM proj_postgres;
\if :pg16
REVOKE sa_owner FROM proj_postgres GRANTED BY postgres;
REVOKE ADMIN OPTION FOR sa_owner FROM proj_postgres GRANTED BY postgres;
\endif
SELECT m.member::regrole AS member, m.grantor::regrole AS grantor, m.admin_option, to_jsonb(m)->>'set_option' AS set FROM pg_auth_members m WHERE m.roleid = 'sa_owner'::regrole ORDER BY 2;
\echo '== D. with only what is left, can proj_postgres take the role back or touch its function?'
\echo '-- D1 re-grant itself SET'
\if :pg16
GRANT sa_owner TO proj_postgres WITH SET TRUE;
\else
GRANT sa_owner TO proj_postgres;
\endif
SELECT count(*) AS memberships_now FROM pg_auth_members WHERE roleid = 'sa_owner'::regrole;
REVOKE sa_owner FROM proj_postgres;
\echo '-- D2 replace the function body'
CREATE OR REPLACE FUNCTION app.job_count() RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$ SELECT 42::bigint $$;
\echo '-- D3 take the function back'
ALTER FUNCTION app.job_count() OWNER TO proj_postgres;
SELECT p.proowner::regrole AS function_owner FROM pg_proc p WHERE p.proname = 'job_count';
RESET ROLE;
\echo '== E. the bootstrap superuser (supabase_admin on hosted) removes the automatic grant'
\if :pg16
REVOKE sa_owner FROM proj_postgres GRANTED BY postgres;
\endif
SELECT m.member::regrole AS member, m.grantor::regrole AS grantor, m.admin_option, to_jsonb(m)->>'set_option' AS set FROM pg_auth_members m WHERE m.roleid = 'sa_owner'::regrole ORDER BY 2;
SET ROLE proj_postgres;
\echo '-- E1 can proj_postgres re-grant itself now?'
GRANT sa_owner TO proj_postgres;
\echo '-- E2 replace the function body now?'
CREATE OR REPLACE FUNCTION app.job_count() RETURNS bigint LANGUAGE sql SECURITY DEFINER SET search_path = '' AS $$ SELECT 42::bigint $$;
\echo '-- E3 does the function still run for a caller?'
SELECT app.job_count() AS job_count;
RESET ROLE;
