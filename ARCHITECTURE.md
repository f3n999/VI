# Architecture & sécurité — stack IoT durcie

## 1. Composants & frontières de confiance

```
Internet/LAN
    │  443 (TLS 1.2/1.3)            ← seul point d'entrée
    ▼
┌─────────────┐   réseau "edge"
│ reverse-proxy│──────────────┬──────────────┬───────────────┐
│  (nginx)    │              │              │               │
└─────────────┘        ┌─────▼────┐   ┌──────▼─────┐   ┌─────▼──────┐
                       │thread-api│   │tailor-panel│   │fabric-watch│
                       └────┬─────┘   └─────┬──────┘   └────────────┘
                réseau "data"│ (internal)   │
                       ┌─────▼──────────────▼─────┐   ┌──────────────────┐
                       │        db-velvet         │   │ stitch-processor │
                       │     (PostgreSQL 16)      │◄──┤  (data only)     │
                       └──────────────────────────┘   └──────────────────┘
```

- **edge** : zone exposée. Seul `reverse-proxy` publie des ports (80→301, 443).
- **data** : `internal: true` → aucune route vers Internet. Porte les données de santé.
- `db-velvet` et `stitch-processor` ne sont sur **aucun** réseau exposé ni publiés sur l'hôte → frontière d'isolation vérifiable.
- Secrets injectés en **fichiers** (Docker secrets), montés en `/run/secrets/*`, jamais en variables d'env ni en couches d'image.

## 2. Matrice de menaces (existant → mitigation dans cette stack)

| Menace (finding audit) | Mitigation appliquée | Résiduel |
|------------------------|----------------------|----------|
| Évasion conteneur via `docker.sock` (C1) | Mount supprimé ; Grafana sans accès Docker | Superviser Docker via `docker-socket-proxy` lecture seule (hors périmètre maquette) |
| Exfiltration données santé non-auth (C2) | JWT signé obligatoire + authz par `user_id`/rôle sur `/api/sensors*` ; stitch isolé + clé API | Pas de rate-limiting applicatif |
| SQLi back-office (C3) | Requêtes préparées (`PDO::prepare`/`execute`), écho SQL supprimé | — |
| Mots de passe en clair (C4) | PBKDF2-HMAC-SHA256 600k itérations, comparaison temps constant ; login back-office DB-backed | bcrypt/argon2id = upgrade (dépendance à ajouter) |
| `debug=True` exposé (C5) | `debug=False` + gunicorn (serveur WSGI prod) | — |
| Token forgeable / non vérifié (H1) | JWT HS256 signé, `exp` 1 h, vérifié par middleware | Pas de refresh/rotation ni révocation |
| Conteneurs root (H2) | `USER` non-root partout ; `cap_drop: ALL` (+ `cap_add` minimaliste CHOWN/SETUID/SETGID pour l'entrypoint) ; `no-new-privileges` ; validé live : `CapEff/CapPrm/CapInh = 0x0` sur le process app (cf. `/proc/1/status`) | — |
| Secrets en clair compose/env (H3) | Docker secrets fichier ; lecture `*_FILE` | Secret manager (Vault/KMS) = cible prod |
| Réseau plat (H4) | Segmentation edge/data, `data` internal | NetworkPolicies fines → k3s (dossier archi) |
| Port DB publié (H5) | DB non publiée, réseau interne, mot de passe fort généré | — |
| Grafana 8.3.0 CVE-2021-43798 (H6) | Grafana 11.3.0 | Vérifier patch courant (cf. #6) |
| Runtimes EOL (M1) | py3.12 / php8.3 / node22 / pg16 | Suivre EOL, rebuild régulier |
| Dépendances obsolètes (M2) | Versions à jour + scan SCA en CI (trivy) | — |
| Pas de healthcheck / limits (M3) | Healthchecks + `deploy.resources.limits` + `restart` | Réplication/HA = orchestration (archi) |

Threat classes **N/A** ici : insecure deserialization (pas de désérialisation d'objets), SSRF (pas de fetch d'URL côté serveur), prompt injection (pas de LLM dans cette stack).

## 3. Hashage mot de passe — choix

PBKDF2-HMAC-SHA256, 600 000 itérations (reco OWASP 2023). **Critère** : seul KDF fort
disponible nativement *à la fois* en Python (`hashlib.pbkdf2_hmac`) et PHP (`hash_pbkdf2`),
donc aucune dépendance ajoutée et vérification cohérente entre `thread-api` et `tailor-panel`.
Format `pbkdf2_sha256$iter$salt_b64$hash_b64`. **Upgrade prod** : argon2id (RFC 9106).

## 4. Reproductibilité / chaîne d'approvisionnement

- Images de base épinglées par tag ; **épingler par digest `@sha256:` avant prod** (CI résout le digest).
- CI (`.github/workflows/ci.yml`) : `hadolint`, `docker compose config`, build, scan `trivy` (HIGH/CRITICAL).
- À ajouter pour la prod : SBOM (syft), signature d'images (cosign), `package-lock.json` + `npm ci`.

## 5. Risques résiduels (laissés volontairement)

1. **ESXi 6.x EOL** (support général terminé) — acceptable pour la maquette, mais le **dossier d'architecture cible doit le présenter comme existant-à-migrer**, pas comme socle « sécurisé ». Cible : hyperviseur supporté (ESXi 8 / Proxmox VE).
2. **Certificat auto-signé** (maquette) — en prod : PKI interne ou Let's Encrypt (la Zone B utilise déjà LE).
3. **Tags d'images non épinglés par digest** — `docker compose config --resolve-image-digests` à committer avant prod.
4. ~~**Jeux de caps `cap_add` non validés au runtime**~~ — **VALIDÉ en live (2026-06-25)** : les trois services concernés (thread-api, tailor-panel, stitch-processor) démarrent correctement avec `cap_add: [CHOWN,SETUID,SETGID]`. L'entrypoint root copie les secrets vers `/tmp/secrets/` puis bascule sur l'utilisateur applicatif via `setpriv`/`su-exec`. Preuve : `CapEff = CapPrm = CapInh = 0x0` sur le process final (`/proc/1/status`). La transition `setresuid(0→nonzero)` vide les sets permitted et effective par règle noyau ; les binaires applicatifs (gunicorn, apache, node) n'ont pas de file capabilities → le bounding set résiduel (`0xc1`) n'accorde aucune surface d'exploitation réelle.
5. ~~**`tailor-panel` en `USER www-data` non testée**~~ — **VALIDÉ en live (2026-06-25)** : tailor-panel (Apache PHP) tourne comme `www-data` via l'entrypoint. Idem thread-api (appuser) et stitch-processor (node). Upgrade prod : php-fpm + nginx.
6. **`grafana/grafana:11.3.0`** : vérifier que c'est le patch courant (advisory GHSA) avant la prod.
7. **Secrets via fichiers** (visibles sur le filesystem hôte sous `secrets/`, `chmod 600`, gitignorés) — meilleur que l'env, mais un secret manager reste la cible prod.
8. **Pas de rate-limiting ni WAF, pas de centralisation de logs/SIEM** — relèvent des briques complémentaires du dossier d'architecture.
