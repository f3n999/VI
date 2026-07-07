#!/bin/sh
# Expose DB_PASSWORD depuis le fichier secret Docker pour le provisioning Grafana
set -e
[ -f /run/secrets/grafana_db_password ] && export GRAFANA_DB_PASSWORD=$(cat /run/secrets/grafana_db_password)
exec /run.sh "$@"
