#!/bin/sh
# Crée le rôle grafana_ro (lecture seule) — exécuté après init.sql au 1er démarrage.
set -e
PW=$(cat /run/secrets/grafana_db_password)
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname='grafana_ro') THEN
    CREATE ROLE grafana_ro LOGIN PASSWORD '${PW}';
    GRANT CONNECT ON DATABASE velvet TO grafana_ro;
    GRANT USAGE ON SCHEMA public TO grafana_ro;
    GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_ro;
    ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana_ro;
  END IF;
END
\$\$;
SQL
