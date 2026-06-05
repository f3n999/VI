# Décisions techniques — journal

> Ce fichier trace les décisions non-évidentes et leur justification.
> À lire avant de modifier quoi que ce soit.

---

## D-01 — PBKDF2 plutôt que bcrypt/argon2id

**Décision :** PBKDF2-HMAC-SHA256 600k itérations.
**Pourquoi :** seul KDF fort disponible nativement en Python (`hashlib`) ET en PHP (`hash_pbkdf2`)
sans ajouter de dépendance. Les deux services (thread-api et tailor-panel) partagent le même
format `pbkdf2_sha256$iter$salt$hash`. bcrypt/argon2id = upgrade prod (dépendance à ajouter).

## D-02 — Docker secrets fichiers, pas variables d'environnement

**Décision :** tous les secrets via `/run/secrets/<name>`, lus par convention `<NAME>_FILE`.
**Pourquoi :** `docker inspect` et `docker compose config` exposent les env vars. Les fichiers
montés via Docker secrets sont visibles uniquement dans le conteneur. Jamais en couche d'image.

## D-03 — Réseau `data` internal:true

**Décision :** `db-velvet` et `stitch-processor` sur réseau `data` avec `internal: true`.
**Pourquoi :** empêche tout accès Internet sortant depuis ces services (exfiltration data santé).
db-velvet n'est joignable que depuis thread-api, tailor-panel, stitch-processor.

## D-04 — pydantic `extra="forbid"` sur tous les modèles

**Décision :** tout champ inconnu dans un body JSON → 400 immédiat, avant d'appeler la DB.
**Pourquoi :** réduction de la surface d'attaque. Un payload avec des champs inattendus
(tentative de mass assignment, injection de paramètres) est rejeté à la couche validation.

## D-05 — Pas de tag `latest` sur les images

**Décision :** toutes les images de base épinglées par version (ex: `postgres:16-alpine`).
**Pourquoi :** reproductibilité et sécurité. `latest` peut pointer vers une image différente
entre deux builds. Avant prod : épingler par digest `@sha256:`.

## D-06 — `read_only: true` + tmpfs

**Décision :** thread-api, stitch-processor, reverse-proxy, tailor-panel en filesystem read-only.
Les répertoires d'écriture légitimes sont montés en tmpfs (en mémoire, non persistant).
**Pourquoi :** si un conteneur est compromis, l'attaquant ne peut pas écrire de fichiers
persistants (pas de backdoor, pas de modification de code).
**Risque connu :** tailor-panel Apache avec read_only non testé runtime → voir ETAT.md.

## D-07 — Grafana sans docker.sock

**Décision :** `fabric-watch` n'a pas accès à `/var/run/docker.sock`.
**Pourquoi :** CVE connu (C1 dans matrice de menaces) — docker.sock = évasion de conteneur
complète. La supervision passe par les métriques PostgreSQL, pas par l'introspection Docker.

## D-08 — Tests mockent get_db (pas de DB réelle en CI)

**Décision :** tous les tests API patchent `app.get_db` avec `unittest.mock`.
**Pourquoi :** la CI n'a pas de PostgreSQL. Les tests vérifient la logique applicative
(auth, IDOR, validation pydantic, paramétrage SQL) indépendamment de l'infrastructure.
Les tests d'intégration réels = à faire sur la VM avec la stack complète.
