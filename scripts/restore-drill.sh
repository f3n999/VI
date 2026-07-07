#!/bin/bash
# Drill de restauration — vérifie qu'un backup est lisible et restaurable
# Usage : sh scripts/restore-drill.sh <fichier_backup.sql.gz.enc>
# Ex    : sh scripts/restore-drill.sh backups/velvet_20260605_120000.sql.gz.enc

set -euo pipefail
cd "$(dirname "$0")/.."

ARCHIVE="${1:-}"
if [ -z "$ARCHIVE" ] || [ ! -f "$ARCHIVE" ]; then
    # Prendre le backup le plus récent si aucun fourni
    ARCHIVE=$(ls -t backups/velvet_*.sql.gz.enc 2>/dev/null | head -1 || true)
    if [ -z "$ARCHIVE" ]; then
        echo "Aucun backup trouvé. Lancer d'abord : sh scripts/backup.sh"; exit 1
    fi
    echo "Utilisation du backup le plus récent : $ARCHIVE"
fi

PASSPHRASE=$(cat secrets/backup_passphrase)   # secret dédié : la rotation du JWT ne casse pas les restaurations
TMPFILE="/tmp/restore_drill_$(date +%s).sql.gz"

echo ""
echo "=== Drill de restauration ==="
echo "Fichier : $ARCHIVE"
echo ""

# ── 1. Déchiffrement ──────────────────────────────────────────────────────────
echo "[1/4] Déchiffrement..."
openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
    -pass "pass:$PASSPHRASE" \
    -in "$ARCHIVE" \
    -out "$TMPFILE"
echo "    → Déchiffrement OK"

# ── 2. Vérification de l'intégrité du gzip ───────────────────────────────────
echo "[2/4] Vérification intégrité gzip..."
gunzip -t "$TMPFILE"
echo "    → Fichier gzip intègre"

# ── 3. Vérification du contenu SQL (structure attendue) ──────────────────────
echo "[3/4] Vérification du contenu SQL..."
TABLES=$(gunzip -c "$TMPFILE" | grep -c "CREATE TABLE" || echo "0")
INSERTS=$(gunzip -c "$TMPFILE" | grep -c "INSERT INTO" || echo "0")
echo "    → $TABLES table(s) trouvée(s), $INSERTS bloc(s) INSERT"
[ "$TABLES" -ge 2 ] || { echo "ERREUR : moins de 2 tables dans le backup"; exit 1; }

# ── 4. Restauration sur une DB de test (velvet_drill) ────────────────────────
echo "[4/4] Restauration dans une base de test (velvet_drill)..."
docker compose exec -T db-velvet \
    psql -U velvet -c "DROP DATABASE IF EXISTS velvet_drill;" velvet 2>/dev/null || true
docker compose exec -T db-velvet \
    psql -U velvet -c "CREATE DATABASE velvet_drill;" velvet
gunzip -c "$TMPFILE" | \
    docker compose exec -T db-velvet psql -U velvet velvet_drill
ROWS=$(docker compose exec -T db-velvet \
    psql -U velvet velvet_drill -t -c "SELECT count(*) FROM health_data;" 2>/dev/null | tr -d ' ')
echo "    → Base velvet_drill restaurée — $ROWS ligne(s) dans health_data"

# Nettoyage
docker compose exec -T db-velvet \
    psql -U velvet -c "DROP DATABASE velvet_drill;" velvet 2>/dev/null || true
rm -f "$TMPFILE"

echo ""
echo "✔  Drill de restauration réussi. Le backup est valide et restaurable."
echo ""
