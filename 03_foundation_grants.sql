-- Least-privilege login for the API. Run as the schema owner. Re-runnable.
-- No password is set here (no secrets in git). After the first run, set it by hand:
--   ALTER ROLE nexus_app PASSWORD '<from your secret store>';
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'nexus_app') THEN
        CREATE ROLE nexus_app LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE;
    END IF;
    EXECUTE format('GRANT CONNECT ON DATABASE %I TO nexus_app', current_database());
END;
$$;

GRANT USAGE ON SCHEMA public TO nexus_app;
-- On PostgreSQL 14 and older PUBLIC may still hold CREATE on public; revoke it there too if so.
REVOKE CREATE ON SCHEMA public FROM nexus_app;

GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO nexus_app;
-- The deployment log is for people applying scripts, not for the app.
REVOKE ALL ON deployment_log FROM nexus_app;

-- Functions and procedures are callable only by roles that are granted EXECUTE.
REVOKE EXECUTE ON ALL ROUTINES IN SCHEMA public FROM PUBLIC;
GRANT EXECUTE ON ALL ROUTINES IN SCHEMA public TO nexus_app;

-- Objects created later by this owner are covered without another grants script.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO nexus_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public REVOKE EXECUTE ON ROUTINES FROM PUBLIC;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT EXECUTE ON ROUTINES TO nexus_app;

INSERT INTO deployment_log (script_name) VALUES ('03_foundation_grants.sql')
ON CONFLICT DO NOTHING;
