#!/bin/sh
# Preuve d'isolation réseau — seuls 80/443 doivent être ouverts sur l'hôte.
set -e

# Installation nmap si absent
if ! command -v nmap >/dev/null 2>&1; then
    echo "Installation de nmap..."
    apt-get install -y nmap -q 2>/dev/null || \
    yum install -y nmap -q 2>/dev/null || \
    apk add --no-cache nmap 2>/dev/null || \
    { echo "Impossible d'installer nmap — l'installer manuellement."; exit 1; }
fi

TARGET="${1:-localhost}"
echo ""
echo "=== Scan nmap sur $TARGET (ports 1-10000) ==="
echo ""

RESULT=$(nmap -p 1-10000 --open "$TARGET" 2>/dev/null)
echo "$RESULT"

echo ""
echo "=== Ports ouverts trouvés ==="
OPEN=$(echo "$RESULT" | grep -E "^[0-9]+/(tcp|udp).*open" || echo "aucun")
echo "$OPEN"

echo ""
# Vérification : seuls 80 et 443 doivent apparaître
UNEXPECTED=$(echo "$OPEN" | grep -v -E "^(80|443)/(tcp|udp)" | grep -v "aucun" || echo "")

if [ -z "$UNEXPECTED" ]; then
    echo "✔  RÉSULTAT : seuls 80/443 sont ouverts — isolation réseau confirmée."
    echo "   db-velvet (5432), stitch-processor (8082), thread-api (8080),"
    echo "   tailor-panel (8080), grafana (3000) : tous invisibles depuis l'hôte."
else
    echo "⚠  ATTENTION : ports inattendus détectés :"
    echo "$UNEXPECTED"
    exit 1
fi
echo ""
