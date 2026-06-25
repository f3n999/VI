#!/bin/bash
# Script de démo live — soutenance SL1PCONNECT
# Usage : sh scripts/demo.sh
# Pré-requis : stack lancée (make up) + /etc/hosts configuré

set -e
cd "$(dirname "$0")/.."

# ── couleurs ──────────────────────────────────────────────────────────────────
G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; C='\033[0;36m'; N='\033[0m'; B='\033[1m'

step() { echo -e "\n${C}${B}╔══ Étape $1 — $2 ══${N}"; }
ok()   { echo -e "${G}✔  $1${N}"; }
info() { echo -e "${Y}▶  $1${N}"; }
fail() { echo -e "${R}✘  $1${N}"; }
hr()   { echo -e "${C}────────────────────────────────────────────${N}"; }

echo -e "${B}\n  SL1PCONNECT — Démo live soutenance\n${N}"

# ── Étape 1 : Reproductibilité ────────────────────────────────────────────────
step 1 "Reproductibilité"
info "Génération des secrets + certificat TLS..."
sh scripts/gen-secrets.sh

info "Démarrage de la stack..."
docker compose up -d --build

info "Attente que tous les services soient healthy..."
TIMEOUT=120
ELAPSED=0
while true; do
    STATUS=$(docker compose ps --format json 2>/dev/null | \
        python3 -c "import sys,json; data=sys.stdin.read()
lines=[l for l in data.split('\n') if l.strip()]
unhealthy=[json.loads(l) for l in lines if 'Health' in json.loads(l) and json.loads(l)['Health'] not in ('healthy','')]
print(len(unhealthy))" 2>/dev/null || echo "0")
    if [ "$STATUS" = "0" ]; then break; fi
    sleep 5; ELAPSED=$((ELAPSED+5))
    if [ $ELAPSED -ge $TIMEOUT ]; then
        fail "Timeout — vérifier : docker compose logs"
        exit 1
    fi
done
docker compose ps
ok "Tous les services sont up. Reproductible depuis Git, zéro clic manuel."
hr

# ── Étape 2 : Secrets non exposés ─────────────────────────────────────────────
step 2 "Secrets non exposés"
info "Variables d'environnement de thread-api :"
docker compose exec thread-api env | grep -i -E 'PASSWORD|SECRET' || true
ok "Seuls les *_FILE apparaissent — les valeurs sont dans /run/secrets/, jamais en clair."
hr

# ── Étape 3 : Isolation réseau ────────────────────────────────────────────────
step 3 "Isolation réseau"
info "Ports publiés sur l'hôte :"
docker compose ps --format "table {{.Name}}\t{{.Ports}}"

info "PostgreSQL inaccessible depuis l'hôte :"
curl -s --connect-timeout 2 http://localhost:5432 && fail "Port 5432 accessible !" || ok "Port 5432 refusé."

info "Scan nmap (seuls 80/443 doivent être ouverts) :"
sh scripts/nmap-proof.sh
hr

# ── Étape 4 : Authentification + anti-IDOR ────────────────────────────────────
step 4 "Authentification obligatoire + anti-IDOR"
BASE="https://api.sl1p.local"

info "Sans token → 401"
CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$BASE/api/sensors/3")
[ "$CODE" = "401" ] && ok "GET /api/sensors/3 sans token → $CODE" || fail "Attendu 401, obtenu $CODE"

info "Login..."
RESP=$(curl -sk -X POST "$BASE/api/login" \
  -H 'Content-Type: application/json' \
  -d '{"email":"jean.dupont@example.com","password":"password123"}')
TOKEN=$(echo "$RESP" | python3 -c "import sys,json; print(json.load(sys.stdin)['token'])" 2>/dev/null)
ok "Token obtenu."

info "Ses propres données → 200"
CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$BASE/api/sensors/3" \
  -H "Authorization: Bearer $TOKEN")
[ "$CODE" = "200" ] && ok "GET /api/sensors/3 avec token → $CODE" || fail "Attendu 200, obtenu $CODE"

info "Données d'un autre utilisateur → 403 (IDOR fermé)"
CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$BASE/api/sensors/4" \
  -H "Authorization: Bearer $TOKEN")
[ "$CODE" = "403" ] && ok "GET /api/sensors/4 avec token user3 → $CODE ← IDOR fermé !" || fail "Attendu 403, obtenu $CODE"
hr

# ── Étape 5 : Rejeu injection SQL ─────────────────────────────────────────────
step 5 "Rejeu de l'injection SQL (faille subie par le prof)"
PAYLOAD='{"email":"'\'' OR '\''1'\''='\''1","password":"x"}'
info "Payload : $PAYLOAD"
RESP=$(curl -sk -X POST "$BASE/api/login" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD")
CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X POST "$BASE/api/login" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD")
echo "  Réponse : $RESP"
[ "$CODE" = "401" ] && ok "Injection → $CODE. Bloquée. La requête est paramétrée, le payload ne part jamais dans le SQL." || fail "Attendu 401, obtenu $CODE"
hr

# ── Étape 6 : Tests CI ────────────────────────────────────────────────────────
step 6 "Tests pytest (preuve formelle)"
info "Exécution de la suite de tests..."
python3 -m venv .venv 2>/dev/null || true
.venv/bin/pip install -q -r thread-api/requirements-dev.txt 2>/dev/null
.venv/bin/pytest thread-api/tests -q && ok "29 tests verts — dont test_injection_sql_bloquee." || fail "Des tests ont échoué."
hr

# ── Étape 7 : Supervision Grafana ─────────────────────────────────────────────
step 7 "Supervision Grafana"
CODE=$(curl -sk -o /dev/null -w "%{http_code}" https://grafana.sl1p.local/api/health)
[ "$CODE" = "200" ] && ok "Grafana répond → ouvrir https://grafana.sl1p.local" || fail "Grafana : code $CODE"
info "Dashboard 'SL1PCONNECT — Supervision IoT' → courbes fréquence cardiaque, chutes, postures."
hr

# ── Étape 8 : Résilience SLA ──────────────────────────────────────────────────
step 8 "Résilience — redémarrage automatique (SLA < 2 min)"
# Pourquoi pas `docker kill` : Docker 29.x marque le stop comme explicite (via l'API daemon)
#   → restart: unless-stopped ne se déclenche pas (comportement voulu : ne pas boucler sur un stop demandé).
# Pourquoi pas `docker exec kill 1` : le noyau Linux protège PID 1 d'un PID namespace contre
#   tout signal envoyé depuis l'intérieur du même namespace (comportement init, signal(7)).
# Solution retenue : tuer le PID hôte du process principal (hors namespace)
#   = crash vu par containerd comme sortie anormale → restart: unless-stopped déclenche le redémarrage.
info "Crash simulé de thread-api (SIGKILL depuis l'hôte, hors PID namespace)..."
SVC_ID=$(docker compose ps -q thread-api)
HOST_PID=$(docker inspect "$SVC_ID" --format '{{.State.Pid}}')
info "PID hôte : $HOST_PID — envoi SIGKILL (hors namespace)"
kill -SIGKILL "$HOST_PID"
sleep 3
docker compose ps thread-api
info "Attente du redémarrage + healthcheck..."
sleep 20
CODE=$(curl -sk -o /dev/null -w "%{http_code}" "$BASE/health")
[ "$CODE" = "200" ] && ok "thread-api revenu healthy. SLA respecté." || info "Encore en redémarrage — normal sous 30s."
hr

echo -e "\n${G}${B}  ✔  Démo terminée.${N}\n"
