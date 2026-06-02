# SL1PCONNECT — Stack IoT durcie (`VI`)

Re-conteneurisation sécurisée des 4 services IoT du cas d'étude + base PostgreSQL,
derrière un reverse proxy TLS, avec isolation réseau et gestion des secrets.
Cible de déploiement : une VM sur l'hyperviseur ESXi existant.

> Périmètre = track (a) : durcissement de la stack applicative (Compose durci).
> L'orchestration scale-up (k3s) et la consolidation Zone A relèvent du dossier d'architecture.

## Prérequis

- Docker Engine + Docker Compose v2
- `openssl` (génération du certificat de maquette)
- Entrées `hosts` (le reverse proxy route par `server_name`) :

```
127.0.0.1   api.sl1p.local panel.sl1p.local grafana.sl1p.local
```
Linux/macOS : `/etc/hosts` — Windows : `C:\Windows\System32\drivers\etc\hosts`
(remplacer `127.0.0.1` par l'IP de la VM si déploiement distant).

## Démarrer

```bash
sh scripts/gen-secrets.sh        # génère secrets/* (aléatoires) + certificat TLS
docker compose up -d --build
```

| Service          | Accès                              | Réseau        | Exposé hôte |
|------------------|------------------------------------|---------------|-------------|
| reverse-proxy    | https://api/panel/grafana.sl1p.local | edge        | 80, 443     |
| thread-api       | via RP → `api.sl1p.local`          | edge + data   | non         |
| tailor-panel     | via RP → `panel.sl1p.local`        | edge + data   | non         |
| fabric-watch     | via RP → `grafana.sl1p.local`      | edge          | non         |
| stitch-processor | **interne uniquement**             | data          | non         |
| db-velvet        | **interne uniquement**             | data (isolé)  | non         |

## Comptes de démonstration

DB-backed, mots de passe stockés en PBKDF2 (aucun clair). Comptes de démo :

| Email | Mot de passe | Rôle |
|-------|--------------|------|
| admin@sl1pconnect.fr | `admin` | admin |
| jean.dupont@example.com | `password123` | user |

## Vérifications (preuves pour la soutenance)

```bash
# 1. TLS + redirection
curl -kI http://api.sl1p.local/            # 301 -> https
curl -k  https://api.sl1p.local/health     # {"status":"ok"}

# 2. Auth obligatoire + anti-IDOR
curl -k https://api.sl1p.local/api/sensors/3                 # 401
TOKEN=$(curl -sk -X POST https://api.sl1p.local/api/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"jean.dupont@example.com","password":"password123"}' | sed 's/.*"token":"\([^"]*\)".*/\1/')
curl -k https://api.sl1p.local/api/sensors/3 -H "Authorization: Bearer $TOKEN"   # 200 (user 3 = jean)
curl -k https://api.sl1p.local/api/sensors/4 -H "Authorization: Bearer $TOKEN"   # 403 (données d'autrui)

# 3. Secrets absents de l'environnement (Docker secrets, pas d'env clair)
docker compose exec thread-api env | grep -i -E 'PASSWORD|SECRET'   # uniquement *_FILE

# 4. Plus de docker.sock dans Grafana
docker compose exec fabric-watch ls /var/run/docker.sock           # absent

# 5. Isolation : db et stitch injoignables depuis l'hôte
docker compose ps         # aucun port publié pour db-velvet / stitch-processor
curl http://localhost:5432   # connexion refusée
```

Preuve de segmentation (le reverse-proxy, en `edge`, n'a aucune route vers `data`) :
```bash
docker compose exec reverse-proxy wget -qO- http://stitch-processor:8082/health   # échoue : pas de route
```
`stitch-processor` reste joignable **en interne** (réseau `data`) avec sa clé API :
```bash
docker compose exec stitch-processor sh -c \
  'wget -qO- http://localhost:8082/stats --header "X-API-Key=$(cat /run/secrets/stitch_api_key)"'
```

## Arrêter

```bash
docker compose down            # garde les volumes
docker compose down -v         # supprime aussi db-data / grafana-data
```

Voir `ARCHITECTURE.md` pour la matrice de menaces et les risques résiduels.
