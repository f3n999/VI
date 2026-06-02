# SL1PCONNECT — Stack IoT durcie (`VI`)

Re-conteneurisation **sécurisée** de la plateforme IoT du cas d'étude SL1PCONNECT :
4 services applicatifs + PostgreSQL, derrière un reverse proxy TLS, avec isolation
réseau, gestion des secrets, conteneurs non-root et CI de sécurité.

> Périmètre : pilier **Conteneurisation** du projet (cible de déploiement : une VM
> sur l'hyperviseur ESXi). Voir [`ARCHITECTURE.md`](ARCHITECTURE.md) et [`PLAN.md`](PLAN.md).

## Architecture

```
Internet/LAN ──443 (TLS 1.2/1.3)──► reverse-proxy (nginx)        réseau "edge"
                                       ├─► thread-api    (API REST mobile)
                                       ├─► tailor-panel  (back-office)
                                       └─► fabric-watch  (Grafana)
                                                  │
                              réseau "data" (internal, sans Internet)
                                       ├─ db-velvet        (PostgreSQL 16)
                                       └─ stitch-processor (traitement santé)
```

`db-velvet` et `stitch-processor` ne sont **sur aucun réseau exposé** ni publiés sur
l'hôte → frontière d'isolation vérifiable.

## Sécurité en bref

- **Conteneurs non-root** + `cap_drop: ALL` + `no-new-privileges` ; `read_only` + tmpfs où applicable
- **Secrets Docker** (fichiers `/run/secrets/*`) — jamais en variables d'environnement ni en couches d'image
- **Segmentation réseau** : `edge` exposé / `data` interne sans accès Internet
- **TLS** terminé au reverse proxy (TLS 1.2/1.3, HSTS)
- **Mots de passe** en PBKDF2-HMAC-SHA256 (600k itérations) — aucun en clair
- **API** : JWT signé + autorisation par `user_id`/rôle (anti-IDOR)
- **Back-office** : requêtes préparées (injection SQL fermée), CSRF, cookies durcis
- **CI** : `hadolint` + `docker compose config` + build + scan `trivy` (HIGH/CRITICAL)

## Prérequis

- Docker Engine + Docker Compose v2
- `openssl` (certificat de maquette)
- Entrées `hosts` (le proxy route par `server_name`) :
  ```
  127.0.0.1   api.sl1p.local panel.sl1p.local grafana.sl1p.local
  ```
  Linux/macOS : `/etc/hosts` — Windows : `C:\Windows\System32\drivers\etc\hosts`
  (remplacer `127.0.0.1` par l'IP de la VM si déploiement distant)

## Démarrer

```bash
sh scripts/gen-secrets.sh        # secrets aléatoires + certificat TLS
docker compose up -d --build
```

| Service          | Accès                          | Réseau       | Publié sur l'hôte |
|------------------|--------------------------------|--------------|-------------------|
| reverse-proxy    | `https://api/panel/grafana.sl1p.local` | edge | 80, 443 |
| thread-api       | via proxy → `api.sl1p.local`   | edge + data  | non |
| tailor-panel     | via proxy → `panel.sl1p.local` | edge + data  | non |
| fabric-watch     | via proxy → `grafana.sl1p.local` | edge       | non |
| stitch-processor | interne uniquement             | data         | non |
| db-velvet        | interne uniquement             | data (isolé) | non |

## Comptes de démonstration

DB-backed, mots de passe stockés hachés (aucun clair) :

| Email | Mot de passe | Rôle |
|-------|--------------|------|
| admin@sl1pconnect.fr | `admin` | admin |
| jean.dupont@example.com | `password123` | user |

## Vérifications (preuves)

```bash
# TLS + redirection HTTP -> HTTPS
curl -kI http://api.sl1p.local/
curl -k  https://api.sl1p.local/health

# Authentification obligatoire + anti-IDOR
curl -k https://api.sl1p.local/api/sensors/3                       # 401
TOKEN=$(curl -sk -X POST https://api.sl1p.local/api/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"jean.dupont@example.com","password":"password123"}' \
  | sed 's/.*"token":"\([^"]*\)".*/\1/')
curl -k https://api.sl1p.local/api/sensors/3 -H "Authorization: Bearer $TOKEN"   # 200
curl -k https://api.sl1p.local/api/sensors/4 -H "Authorization: Bearer $TOKEN"   # 403

# Secrets absents de l'environnement
docker compose exec thread-api env | grep -i -E 'PASSWORD|SECRET'   # uniquement *_FILE

# Plus de docker.sock dans Grafana
docker compose exec fabric-watch ls /var/run/docker.sock           # absent

# Isolation : db et stitch non joignables depuis l'hôte
docker compose ps                  # aucun port publié pour db-velvet / stitch-processor
nmap -p 1-65535 <ip-hote>          # seuls 80/443 ouverts
curl http://localhost:5432         # connexion refusée

# Résilience (SLA)
docker kill $(docker compose ps -q thread-api)   # redémarrage automatique
```

## Structure

```
VI/
├── docker-compose.yml          # réseaux, secrets, healthchecks, durcissement
├── ARCHITECTURE.md             # schéma, matrice de menaces, risques résiduels
├── PLAN.md                     # plan d'action projet (soutenance 7 juillet)
├── .github/workflows/ci.yml    # hadolint + compose config + build + trivy
├── scripts/gen-secrets.sh      # génération secrets + certificat TLS
├── reverse-proxy/nginx.conf    # TLS, vhosts, en-têtes de sécurité
├── db-velvet/init.sql          # schéma + seed (mots de passe hachés)
├── thread-api/                 # API Flask (JWT, authz, gunicorn, non-root)
├── tailor-panel/               # back-office PHP (requêtes préparées, non-root)
├── stitch-processor/           # traitement Node (clé API, isolé, non-root)
├── fabric-watch/               # Grafana (sans docker.sock)
└── secrets/                    # gabarits *.example (vrais secrets gitignorés)
```

## Arrêter

```bash
docker compose down            # conserve les volumes
docker compose down -v         # supprime aussi db-data / grafana-data
```
