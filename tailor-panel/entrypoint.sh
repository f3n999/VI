#!/bin/sh
# Lance en root (cap_add minimal : CHOWN/SETUID/SETGID) pour copier les secrets
# Docker (root:root 600) vers un tmpfs prive lisible par www-data, puis droppe
# les privileges avant d'exec Apache. Necessaire car ce moteur Docker Compose
# ignore les champs secrets.mode/uid/gid (bind-mount brut des permissions hote).
set -eu

mkdir -p /tmp/secrets
for f in /run/secrets/*; do
  [ -f "$f" ] || continue
  name=$(basename "$f")
  cp "$f" "/tmp/secrets/$name"
  chmod 400 "/tmp/secrets/$name"
  chown www-data:www-data "/tmp/secrets/$name"
done

exec setpriv --reuid=www-data --regid=www-data --clear-groups -- "$@"
