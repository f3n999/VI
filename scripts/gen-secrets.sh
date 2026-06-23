#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

mkdir -p secrets reverse-proxy/tls

gen() { openssl rand -base64 "$1" | tr -d '\n'; }

[ -f secrets/db_password ]            || gen 24 > secrets/db_password
[ -f secrets/jwt_secret ]             || gen 48 > secrets/jwt_secret
[ -f secrets/grafana_admin_password ] || gen 24 > secrets/grafana_admin_password
[ -f secrets/stitch_api_key ]         || gen 32 > secrets/stitch_api_key
chmod 600 secrets/db_password secrets/jwt_secret secrets/grafana_admin_password secrets/stitch_api_key

if [ ! -f reverse-proxy/tls/server.crt ]; then
  MSYS_NO_PATHCONV=1 openssl req -x509 -nodes -days 365 -newkey rsa:2048 \
    -keyout reverse-proxy/tls/server.key \
    -out    reverse-proxy/tls/server.crt \
    -subj   "/C=FR/O=SL1PCONNECT/CN=sl1p.local" \
    -addext "subjectAltName=DNS:api.sl1p.local,DNS:panel.sl1p.local,DNS:grafana.sl1p.local"
  chmod 600 reverse-proxy/tls/server.key
fi

echo "secrets + TLS generes."
