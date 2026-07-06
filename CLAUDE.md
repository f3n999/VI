# CLAUDE.md — Projet SL1PCONNECT (Virtualisation & Conteneurisation, B3 Oteria)

> **À lire en entier avant toute action.** Ce fichier donne le contexte, l'état du
> repo, les décisions verrouillées, les conventions à respecter et le travail
> restant. Objectif : pouvoir continuer le projet sans contexte externe.
> Toute la communication et la doc du projet sont **en français**.

---

## 1. Le projet en une page

**Cas d'étude (fictif) : SL1PCONNECT** — sous-vêtements de luxe connectés (HealthTech/IoT),
collecte de **données de santé** (RGPD Art.9). L'infra existante a grandi par accumulation
(serveurs hétérogènes, Docker mal configuré, secrets en clair, déploiements manuels, zéro
supervision). **Mission :** concevoir et déployer une infrastructure de remplacement
**virtualisée, conteneurisée, orchestrée, reproductible et sécurisée**.

**Rendus (deadline : soutenance le 7 juillet) :**
1. **Dossier d'architecture** (schéma, choix justifiés, comparatifs, plan d'adressage, plan de migration).
2. **Maquette fonctionnelle** (hyperviseur + VM + ≥1 service IoT re-conteneurisé + supervision + déploiement reproductible).
3. **Démo live** en soutenance (~5-10 min présentation préparée + 15-20 min démo + questions).

**Ce repo (`VI`)** = le pilier **Conteneurisation** : la plateforme IoT (Zone B du cas d'étude)
re-conteneurisée et durcie. C'est la brique technique de la maquette et de la démo.

---

## 2. État actuel du repo

Stack durcie **complète**, poussée sur GitHub (`f3n999/VI`), **validée statiquement**
(`docker compose config` OK, round-trip PBKDF2 vérifié) mais **pas encore lancée en live**
(à faire sur la VM Ubuntu de l'ESXi).

```
VI/
├── docker-compose.yml          # réseaux, secrets, healthchecks, durcissement
├── README.md                   # run + preuves
├── ARCHITECTURE.md             # schéma, matrice de menaces, risques résiduels
├── PLAN.md                     # plan d'action projet (3 jours → soutenance)
├── CLAUDE.md                   # ce fichier
├── .github/workflows/ci.yml    # hadolint + compose config + build + trivy
├── scripts/gen-secrets.sh      # génère secrets/* + certificat TLS (OBLIGATOIRE avant up)
├── reverse-proxy/nginx.conf    # TLS, vhosts par server_name, en-têtes sécurité
├── db-velvet/init.sql          # schéma + seed (mots de passe hachés PBKDF2)
├── thread-api/                 # API Flask : JWT, authz anti-IDOR, gunicorn, non-root
├── tailor-panel/               # back-office PHP : requêtes préparées, CSRF, non-root
├── stitch-processor/           # traitement Node : clé API, isolé, non-root
├── fabric-watch/               # Grafana (SANS docker.sock)
└── secrets/                    # gabarits *.example ; vrais secrets gitignorés
```

**Fait depuis :** validation stricte **pydantic** (`extra="forbid"` + `strict=True`) sur
`thread-api`, **suite de tests pytest** (29 tests), **scan d'images Trivy** en CI (en plus du
fs), secrets en `chmod 600`, `backups/` gitignoré. La stack vulnérable d'origine est isolée
dans `legacy-vulnerable-AVANT/` (référence avant/après, **à ne pas déployer**).

**Restant (sur la VM) :** déploiement live + vérif des inconnus runtime (§10), Grafana
non-root + user `grafana_ro`, chiffrement au repos. Vérifier l'état réel avec `git status`
avant de (re)faire.

---

## 3. Décisions d'architecture VERROUILLÉES

Issues des réponses du prof — **ne pas les remettre en cause**, les justifier dans le dossier.

| Sujet | Décision |
|-------|----------|
| Modèle | **Hybride** : Nice on-prem virtualisé + cloud **HDS OVH conservé** (données santé) |
| Budget | enveloppe 100 k€ ; **≈ 0 € réel** (serveur existant réutilisé + 100 % open-source) → argument de maîtrise des coûts |
| Hyperviseur | **ESXi existant** (maquette) ; cible proposée = **Proxmox VE** (open-source, supporté) |
| Orchestration | **Compose durci** (maquette) → **k3s** (cible) |
| À garder | **OpenBSD** (DNS NSD/DNSSEC), modèle **4 pare-feux**, **IPSec FW2FW** |
| Legacy | **Windows XP NON migré** → VLAN quarantaine isolé ; **Sage → SaaS** |
| Données | migration incluse ; **dataset de test généré via LLM** ; **AUCUNE donnée réelle** |
| Chiffrement | **BDD chiffrée au repos** (gap actuel) + TLS partout |
| Sauvegarde | **3-2-1, chiffrée, restauration testée** |
| Secrets | Docker secrets (maquette) → Vault (cible) |

---

## 4. Grille de notation implicite (les « tips » du prof = à démontrer)

Le prof a explicitement cité, et a révélé avoir **subi une injection SQL sur l'API** :

- `Trivy` — **en place** (CI) : scan **fs** (IaC + dépendances) **et scan d'images** (boucle sur les images buildées)
- `hadolint` (lint Dockerfile) — **en place** (CI)
- `healthcheck` — **en place** (compose)
- `yaml strict` (`docker compose config`) — **en place** (CI)
- **`pydantic`** (validation stricte) — **en place** : `extra="forbid"` + `strict=True` sur `thread-api`
- **tests « dans tous les sens »** (pytest) — **en place** (29 tests, job CI dédié)
- **`nmap`** (preuve d'exposition réseau) — à scénariser pour la démo
- **rejeu de l'injection SQL** → **bloquée** (requêtes préparées), couvert par les tests, à rejouer en démo

> **Angle fort de la soutenance :** « La faille SQL que vous avez subie sur l'API, on l'a
> identifiée et fermée — et on le prouve en live. »

---

## 5. Architecture de la stack (ce repo)

```
Internet/LAN ──443 (TLS 1.2/1.3)──► reverse-proxy (nginx)         réseau "edge"
                                       ├─► thread-api    :8080   (API REST mobile)
                                       ├─► tailor-panel  :8080   (back-office)
                                       └─► fabric-watch  :3000   (Grafana)
                                                  │
                              réseau "data" (internal, SANS accès Internet)
                                       ├─ db-velvet        (PostgreSQL 16)
                                       └─ stitch-processor (traitement santé, clé API)
```

- **Reverse proxy** = seul service exposé (ports 80→301 et 443). Route par `server_name` :
  `api.sl1p.local`, `panel.sl1p.local`, `grafana.sl1p.local`.
- **`db-velvet` et `stitch-processor`** : sur le réseau `data` **uniquement**, non publiés →
  c'est la **preuve d'isolation** (démo : `nmap` ne voit que 80/443).
- **Modèle de sécurité** : conteneurs non-root, `cap_drop: ALL`, `no-new-privileges`,
  `read_only`+tmpfs là où c'est sûr, secrets en fichiers, TLS au proxy.

---

## 6. Conventions à respecter ABSOLUMENT

- ❌ **Jamais de tag `latest`** sur les images. Pin par version (idéalement par digest avant prod).
- 🔒 **Jamais committer de secret.** Les secrets réels (`secrets/db_password`, `jwt_secret`,
  `grafana_admin_password`, `stitch_api_key`) et le TLS (`reverse-proxy/tls/`) sont **gitignorés**.
  Seuls les `secrets/*.example` sont versionnés. **Vérifier `git diff --cached` avant chaque commit.**
- 👤 Conteneurs **non-root** (`USER`), `cap_drop: ALL`, `security_opt: no-new-privileges:true`.
- 🔑 Mots de passe en **PBKDF2-HMAC-SHA256 / 600 000 itérations**, format
  `pbkdf2_sha256$iter$salt_b64$hash_b64`. **Jamais de mot de passe en clair**, ni en base, ni en code.
- 🧱 **Requêtes préparées partout** (psycopg2 `%s`, PDO `:param`). Jamais de concaténation SQL.
- 📥 Secrets lus via convention **`<NAME>_FILE`**. Deux mécanismes selon le service :
  - **`fabric-watch`** (user root) : lit directement dans `/run/secrets/` (monté par Docker Compose).
  - **`thread-api`, `tailor-panel`, `stitch-processor`** : l'entrypoint root copie vers `/tmp/secrets/` (tmpfs privé, `chmod 400 <appuser>:<appuser>`), puis droppe les privilèges. Les `*_FILE` pointent vers `/tmp/secrets/<name>`. **Tout nouveau service non-root doit suivre ce pattern** (l'entrypoint de thread-api fait référence).
- 🧪 **Aucune donnée réelle.** Données de test/préprod **générées via LLM** ou faker, anonymisées.
- 📝 Messages de commit clairs ; finir par le trailer `Co-Authored-By` si généré par l'IA.
  Brancher avant de committer si on n'est pas sur une branche de travail. **Ne pas push sans accord.**

---

## 7. Commandes

```bash
# Lancer la stack (la génération des secrets est OBLIGATOIRE — ils ne sont pas dans le repo)
sh scripts/gen-secrets.sh
docker compose up -d --build
docker compose ps                      # tout doit être running/healthy

# Accès navigateur : ajouter au /etc/hosts
#   127.0.0.1  api.sl1p.local panel.sl1p.local grafana.sl1p.local
curl -k https://api.sl1p.local/health

# Valider le compose sans démarrer
docker compose config

# Tests API (à mettre en place — cf. §11)
cd thread-api && pip install -r requirements-dev.txt && pytest -q

# Arrêt
docker compose down            # garde les volumes ; -v pour tout supprimer
```

---

## 8. Détails techniques utiles

- **Comptes de démo** (mots de passe hachés en base) : `admin@sl1pconnect.fr` / `admin` (admin),
  `jean.dupont@example.com` / `password123` (user, id=3).
- **Régénérer un hash PBKDF2** (Python stdlib, même format que `init.sql`) :
  ```python
  import hashlib, os, base64
  salt = os.urandom(16)
  dk = hashlib.pbkdf2_hmac("sha256", b"motdepasse", salt, 600000)
  print("pbkdf2_sha256$600000$%s$%s" % (base64.b64encode(salt).decode(), base64.b64encode(dk).decode()))
  ```
  La vérification existe en Python (`thread-api/app.py: verify_password`) **et** en PHP
  (`tailor-panel/index.php: verify_password`) — garder les deux cohérents si on change le schéma.
- **Secrets attendus** par le compose : `db_password`, `jwt_secret`, `grafana_admin_password`,
  `stitch_api_key` (générés par `scripts/gen-secrets.sh`).

---

## 9. Travail restant (plan 3 jours)

**J1 — Dossier d'architecture :** audit au propre (`AUDIT.md`), schéma cible hybride, plan
d'adressage, comparatifs justifiés (hyperviseur/orchestrateur/backup/CI-CD), plan de migration
(SLA < 2 h, XP isolé, Sage→SaaS, OpenBSD gardé), budget.

**J2 — Maquette & durcissement :** déployer la stack sur l'ESXi/VM ; **ajouter pydantic**
(`extra="forbid"`) à `thread-api` ; **écrire les tests pytest** ; **scan nmap** ; supervision
Grafana ; dataset synthétique via LLM.

**J3 — Reproductibilité & démo :** déploiement reproductible (Git+CI, option Ansible/Terraform) ;
backup 3-2-1 + **drill de restauration** ; finaliser le dossier ; **slides + script de démo +
répétition + plan B (vidéo de secours)**.

### Détail des tests pytest à écrire (`thread-api/tests/`)
Tests unitaires/composant (sans DB réelle, en mockant `get_db`), à faire tourner en CI :
- `verify_password` : bon mot de passe / mauvais / hash malformé.
- Modèles pydantic : rejet d'un champ inattendu, d'un type invalide, d'un champ manquant.
- API (Flask test client) : login OK/KO, **rejeu injection SQL** (payload dans `email` →
  401 + assertion que la requête est **paramétrée**, pas concaténée), `/api/sensors` sans token → 401,
  IDOR cross-user → 403, accès à ses propres données → 200, token invalide → 401, body invalide → 400.

---

## 10. Inconnus runtime à vérifier au 1er `up`

Non testés en live (rédigés « durci » mais à confirmer ; cf. `ARCHITECTURE.md §5`). Si un
conteneur boucle (`docker compose ps` → Restarting/Exited) → `docker compose logs <svc>` :

- **caps** sous `cap_drop: ALL` (#2) : si `operation not permitted`, ajouter la cap manquante
  ou retirer temporairement `cap_drop` du service.
- **`tailor-panel`** Apache rootless `USER www-data` (#3) : en secours, retirer `USER www-data`
  du Dockerfile.
- **`fabric-watch`** Grafana + volume sous `cap_drop ALL` (#5) : si erreur de chown, retirer
  `cap_drop` de ce service.

---

## 11. Garde-fous

- **Ne jamais committer/pusher de secret** ni de donnée réelle. Vérifier `git diff --cached`.
- **Ne jamais pusher sans accord explicite** de l'utilisateur.
- Ne pas introduire de tag `latest`, ni de mot de passe en clair, ni de concaténation SQL.
- Quand un détail (version, CVE, flag) n'est pas vérifiable, le marquer comme tel — ne pas inventer.

---

## 12. Pointeurs

- `README.md` — démarrage + commandes de preuve.
- `ARCHITECTURE.md` — schéma, matrice de menaces, risques résiduels.
- `PLAN.md` — plan d'action détaillé.
- Documents du cas d'étude fournis par le prof (énoncé `cas_etude_virtu_conteneur` + schéma
  `infra.drawio`) : à déposer dans un dossier `docs/` du repo pour que l'assistant y ait accès.
