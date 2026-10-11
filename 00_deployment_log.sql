CREATE TABLE IF NOT EXISTS deployment_log (
    script_name  text        PRIMARY KEY,
    applied_at   timestamptz NOT NULL DEFAULT now()
);

INSERT INTO deployment_log (script_name) VALUES ('00_deployment_log.sql')
ON CONFLICT DO NOTHING;
