# SL1PCONNECT — Stack IoT durcie (`VI`)

Re-conteneurisation **sécurisée** de la plateforme IoT du cas d'étude SL1PCONNECT :
4 services applicatifs + PostgreSQL + supervision Grafana, derrière un reverse proxy
TLS, avec isolation réseau, gestion des secrets, conteneurs non-root et CI de sécurité.
Une couche d'observabilité (métriques + logs) est disponible en extension.

> Périmètre : **livrable 2** (maquette fonctionnelle) — cible de déploiement : une VM
> sur l'hyperviseur ESXi. Voir aussi [`ARCHITECTURE.md`](ARCHITECTURE.md),
> [`PLAN.md`](PLAN.md), [`docs/HA-OBSERVABILITY.md`](docs/HA-OBSERVABILITY.md) et [`CLAUDE.md`](CLAUDE.md).

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

  extension observabilité (opt-in, réseau "monitoring" internal) :
       Prometheus + node_exporter (métriques)  ·  Loki + Promtail (logs)
```

`db-velvet` et `stitch-processor` ne sont **sur aucun réseau exposé** ni publiés sur
l'hôte → frontière d'isolation vérifiable.

## Sécurité en bref

- **Conteneurs non-root** + `cap_drop: ALL` + `no-new-privileges` ; `read_only` + tmpfs où applicable
- **Secrets Docker** (fichiers `/run/secrets/*`) — jamais en variables d'environnement ni en couches d'image
- **Segmentation réseau** : `edge` exposé / `data` interne sans accès Internet / `monitoring` interne
- **TLS** terminé au reverse proxy (TLS 1.2/1.3, HSTS)
- **Mots de passe** en PBKDF2-HMAC-SHA256 (600k itérations) — aucun en clair
- **API** : validation stricte (pydantic `extra="forbid"`) + JWT signé + autorisation par `user_id`/rôle (anti-IDOR)
- **Back-office** : requêtes préparées (injection SQL fermée), CSRF, cookies durcis
- **CI** : `hadolint` + `docker compose config` + **pytest** (29 tests) + scan `trivy` (HIGH/CRITICAL)

## Prérequis

- Docker Engine + Docker Compose v2, `make`, `openssl`
- Entrées `hosts` (le proxy route par `server_name`) :
  ```
  127.0.0.1   api.sl1p.local panel.sl1p.local grafana.sl1p.local
  ```
  Linux/macOS : `/etc/hosts` — Windows : `C:\Windows\System32\drivers\etc\hosts`
  (remplacer `127.0.0.1` par l'IP de la VM si déploiement distant)

## Démarrer

```bash
make up        # génère les secrets + le certificat, build et démarre la stack
make ps        # état des services (doivent être healthy)
```

| Service          | Accès                          | Réseau       | Publié sur l'hôte |
|------------------|--------------------------------|--------------|-------------------|
| reverse-proxy    | `https://api/panel/grafana.sl1p.local` | edge | 80, 443 |
| thread-api       | via proxy → `api.sl1p.local`   | edge + data  | non |
| tailor-panel     | via proxy → `panel.sl1p.local` | edge + data  | non |
| fabric-watch     | via proxy → `grafana.sl1p.local` | edge + data | non |
| stitch-processor | interne uniquement             | data         | non |
| db-velvet        | interne uniquement             | data (isolé) | non |

### Avec l'observabilité (métriques + logs)
```bash
sh scripts/gen-secrets.sh
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d --build
```

## Commandes (Makefile)

| Commande | Effet |
|----------|-------|
| `make up` | génère les secrets, build et démarre |
| `make test` | lance les 29 tests pytest |
| `make demo` | rejoue le scénario de démo complet |
| `make nmap` | scanne les ports ouverts (preuve d'isolation) |
| `make logs` | suit les logs en direct |
| `make down` / `make clean` | arrête / arrête et supprime les volumes |

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

# Rejeu de l'injection SQL → bloquée (couverte aussi par les tests pytest)
make test

# Secrets absents de l'environnement
docker compose exec thread-api env | grep -i -E 'PASSWORD|SECRET'   # uniquement *_FILE

# Plus de docker.sock dans Grafana
docker compose exec fabric-watch ls /var/run/docker.sock           # absent

# Isolation : db et stitch non joignables depuis l'hôte
make nmap                          # seuls 80/443 ouverts
curl http://localhost:5432         # connexion refusée

# Résilience (SLA)
docker kill $(docker compose ps -q thread-api)   # redémarrage automatique
```

## Structure

```
VI/
├── docker-compose.yml               # stack de base : réseaux, secrets, durcissement
├── docker-compose.observability.yml # extension : Prometheus/node_exporter + Loki/Promtail
├── Makefile                         # up / test / demo / nmap / logs / down
├── ARCHITECTURE.md · PLAN.md · CLAUDE.md
├── docs/HA-OBSERVABILITY.md         # HA, observabilité, fix sécu Grafana (lecture seule)
├── .github/workflows/ci.yml         # hadolint + compose config + pytest + trivy
├── scripts/                         # gen-secrets, demo, nmap-proof, backup, restore-drill
├── monitoring/                      # configs Prometheus / Loki / Promtail + datasources
├── reverse-proxy/nginx.conf         # TLS, vhosts, en-têtes de sécurité
├── db-velvet/init.sql               # schéma + seed synthétique (mots de passe hachés)
├── fabric-watch/                    # Grafana + provisioning auto (dashboard santé)
├── thread-api/                      # API Flask (pydantic, JWT, anti-IDOR) + tests/
├── tailor-panel/                    # back-office PHP (requêtes préparées, non-root)
├── stitch-processor/                # traitement Node (clé API, isolé, non-root)
└── secrets/                         # gabarits *.example (vrais secrets gitignorés)
```

## Arrêter

```bash
make down            # conserve les volumes
make clean           # supprime aussi db-data / grafana-data / prometheus-data / loki-data
```
