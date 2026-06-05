#!/bin/sh
# Preuve d'isolation réseau Docker.
# Objectif : confirmer que les ports internes des conteneurs (db, api, grafana, node)
# ne sont PAS exposés sur l'hôte. On teste directement ces ports spécifiques.
set -e

if ! command -v nmap >/dev/null 2>&1; then
    echo "Installation de nmap..."
    apt-get install -y nmap -q 2>/dev/null || \
    yum install -y nmap -q 2>/dev/null || \
    apk add --no-cache nmap 2>/dev/null || \
    { echo "Impossible d'installer nmap — l'installer manuellement."; exit 1; }
fi

TARGET="${1:-localhost}"
echo ""
echo "=== Preuve d'isolation réseau — $TARGET ==="
echo ""

# Ports qui doivent être OUVERTS (reverse-proxy uniquement)
REQUIRED_OPEN="80,443"

# Ports qui doivent être FERMES (services internes Docker)
# db-velvet:5432, thread-api:8080, tailor-panel:8080, stitch-processor:8082, grafana:3000
INTERNAL_PORTS="3000,5432,8080,8082"

echo "--- Vérification ports exposés (80/443) ---"
OPEN=$(nmap -p "$REQUIRED_OPEN" --open "$TARGET" 2>/dev/null | grep -E "^[0-9]+/(tcp|udp).*open" || echo "")
echo "$OPEN"

echo ""
echo "--- Vérification ports internes (doivent être fermés) ---"
CLOSED=$(nmap -p "$INTERNAL_PORTS" "$TARGET" 2>/dev/null | grep -E "^[0-9]+/(tcp|udp)" || echo "")
echo "$CLOSED"

echo ""
FAIL=0

# Vérifier que 80 et 443 sont ouverts
for PORT in 80 443; do
    if echo "$OPEN" | grep -q "^${PORT}/"; then
        echo "✔  Port $PORT ouvert (attendu)"
    else
        echo "✗  Port $PORT fermé — le reverse-proxy ne répond pas"
        FAIL=1
    fi
done

# Vérifier que les ports internes sont fermés/filtrés
for PORT in 3000 5432 8080 8082; do
    STATE=$(echo "$CLOSED" | grep "^${PORT}/" | awk '{print $2}' || echo "")
    if [ "$STATE" = "open" ]; then
        echo "✗  Port $PORT OUVERT — fuite d'isolation !"
        FAIL=1
    else
        echo "✔  Port $PORT fermé/filtré (attendu)"
    fi
done

echo ""
if [ "$FAIL" -eq 0 ]; then
    echo "✔  RÉSULTAT : isolation réseau confirmée."
    echo "   Seul le reverse-proxy est visible. db-velvet, thread-api,"
    echo "   tailor-panel, stitch-processor et grafana sont invisibles."
else
    echo "✗  ECHEC : isolation réseau compromise."
    exit 1
fi
echo ""
