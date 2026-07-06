#!/bin/sh
# Le mot de passe de la datasource est lu par Grafana via $__file{/run/secrets/db_password}
# (provisioning) — aucun secret exporté en variable d'environnement.
set -e
exec /run.sh "$@"
