#!/bin/sh
# Expose DB_PASSWORD depuis le fichier secret Docker pour le provisioning Grafana
set -e
[ -f /run/secrets/db_password ] && export DB_PASSWORD=$(cat /run/secrets/db_password)
exec /run.sh "$@"
