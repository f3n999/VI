#!/bin/sh
# Expose GRAFANA_DB_PASSWORD depuis le secret Docker (root:root 600) pour le
# provisioning Grafana (${GRAFANA_DB_PASSWORD} dans velvet.yml).
# user: "0" requis : Docker secrets sont root:root 600, non lisibles en non-root
# sans le pattern entrypoint+tmpfs (même contrainte que thread-api/tailor-panel).
set -e
[ -f /run/secrets/grafana_db_password ] && export GRAFANA_DB_PASSWORD=$(cat /run/secrets/grafana_db_password)
exec /run.sh "$@"
