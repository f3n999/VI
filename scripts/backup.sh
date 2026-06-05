#!/bin/bash
# Sauvegarde 3-2-1 chiffrée — dump PostgreSQL + chiffrement AES-256
# 3 copies · 2 supports (local + distant) · 1 hors-site
#
# Usage : sh scripts/backup.sh [destination_rsync]
# Ex    : sh scripts/backup.sh user@backup-server:/backups/sl1p

set -euo pipefail
cd "$(dirname "$0")/.."

TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="./backups"
ARCHIVE="$BACKUP_DIR/velvet_${TIMESTAMP}.sql.gz.enc"
REMOTE="${1:-}"

mkdir -p "$BACKUP_DIR"

# ── 1. Dump PostgreSQL dans le conteneur ──────────────────────────────────────
echo "[1/4] Dump PostgreSQL..."
docker compose exec -T db-velvet \
    pg_dump -U velvet velvet | gzip > "/tmp/velvet_${TIMESTAMP}.sql.gz"

# ── 2. Chiffrement AES-256-CBC (clé dérivée du jwt_secret) ───────────────────
echo "[2/4] Chiffrement AES-256..."
PASSPHRASE=$(cat secrets/jwt_secret | head -c 32)
openssl enc -aes-256-cbc -pbkdf2 -iter 100000 \
    -pass "pass:$PASSPHRASE" \
    -in "/tmp/velvet_${TIMESTAMP}.sql.gz" \
    -out "$ARCHIVE"

chmod 600 "$ARCHIVE"
rm -f "/tmp/velvet_${TIMESTAMP}.sql.gz"

SIZE=$(du -sh "$ARCHIVE" | cut -f1)
echo "    → $ARCHIVE ($SIZE) — copie locale (support 1)"

# ── 3. Copie distante (support 2) si destination fournie ─────────────────────
if [ -n "$REMOTE" ]; then
    echo "[3/4] Copie distante vers $REMOTE..."
    rsync -az --progress "$ARCHIVE" "$REMOTE/"
    echo "    → copie distante ok (support 2, hors-site)"
else
    echo "[3/4] Pas de destination distante fournie — copie locale uniquement."
    echo "    → Pour activer : sh scripts/backup.sh user@host:/path"
fi

# ── 4. Rotation : ne garder que les 7 derniers backups locaux ─────────────────
echo "[4/4] Rotation (conservation des 7 derniers)..."
ls -t "$BACKUP_DIR"/velvet_*.sql.gz.enc 2>/dev/null | tail -n +8 | xargs -r rm -f
COUNT=$(ls "$BACKUP_DIR"/velvet_*.sql.gz.enc 2>/dev/null | wc -l)
echo "    → $COUNT backup(s) conservé(s) dans $BACKUP_DIR/"

echo ""
echo "✔  Backup terminé : $ARCHIVE"
