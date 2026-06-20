# Haute disponibilité & observabilité — extensions

Ces extensions sont **additives** : le `docker-compose.yml` de base n'est pas modifié.
La stack de démo qui fonctionne déjà n'est jamais menacée.

---

## 1. Observabilité (métriques + logs)

Fichier : `docker-compose.observability.yml` (+ configs dans `monitoring/`).

| Service | Rôle |
|---------|------|
| **Prometheus** | collecte des métriques (rétention 7 j) |
| **node_exporter** | métriques système de l'hôte (CPU, RAM, disque, réseau) |
| **Loki** | stockage des logs |
| **Promtail** | collecte les logs des conteneurs (lecture de fichiers, **sans docker.sock**) |

Grafana reçoit automatiquement deux datasources supplémentaires (Prometheus, Loki)
en plus de `VelvetDB`. Aucun `docker.sock` n'est monté → cohérent avec notre durcissement.

### Lancer
```bash
sh scripts/gen-secrets.sh
docker compose -f docker-compose.yml -f docker-compose.observability.yml up -d --build
docker compose -f docker-compose.yml -f docker-compose.observability.yml ps
```
Puis dans Grafana : les métriques hôte (node_exporter) et les logs (Loki) sont
disponibles à côté du dashboard santé existant.

> ⚠️ À valider au 1er `up` (non testé en CI) : `node-exporter` (pid host + mount `/:ro`)
> et le démarrage de `loki` (le schéma de config Loki varie selon les versions).
> Tout est isolé dans l'override : si un service de la couche obs échoue, **la stack de
> base reste intacte**.

---

## 2. Haute disponibilité

### 2.1 Implémenté en maquette : redondance du tier applicatif (load-balancing)

Le reverse proxy nginx résout les upstreams dynamiquement
(`resolver 127.0.0.11` + `set $upstream`). En **scalant** un service stateless, le DNS
Docker renvoie plusieurs IP et nginx **répartit la charge** automatiquement.

```bash
docker compose -f docker-compose.yml -f docker-compose.observability.yml \
  up -d --build --scale thread-api=2
```

**Démo HA :** tuer une instance → l'autre continue de servir, et `restart: unless-stopped`
relance l'instance tuée.
```bash
docker compose ps thread-api                 # 2 instances
docker kill $(docker compose ps -q thread-api | head -1)
curl -k https://api.sl1p.local/health        # toujours 200 (l'autre instance répond)
```

### 2.2 Cible (dossier d'architecture) — au-delà de la maquette

> **Honnêteté soutenance :** sur **un seul hôte ESXi**, la HA est démontrée comme
> *mécanisme* (load-balancing, bascule, redémarrage), pas survivable à une panne d'hôte.
> La vraie HA exige **plusieurs nœuds**. C'est le rôle du dossier d'architecture :

- **PostgreSQL en réplication primaire/réplica** (streaming replication) — reproduit
  exactement les **pgsql1/pgsql2** du schéma du prof. Bascule par promotion du réplica
  (ex. Patroni + etcd pour l'automatisation).
- **Reverse proxy en paire active/standby** + **keepalived** (VIP) — reproduit la paire
  **Scylla/Charybde** du schéma. Plus de point unique en entrée.
- **Orchestrateur k3s multi-nœuds** — reprogrammation automatique des pods sur un nœud
  survivant, NetworkPolicies pour l'isolation Art.9, stockage répliqué (Longhorn).
- **vSphere HA** côté hyperviseur si plusieurs hôtes ESXi.

---

## 3. Amélioration sécurité recommandée — Grafana en lecture seule

**Constat :** aujourd'hui Grafana se connecte à PostgreSQL avec l'utilisateur **`velvet`
(propriétaire, plein privilège)**. Si Grafana est compromis, l'attaquant a un accès en
**écriture/suppression** sur les données de santé.

**Correctif (moindre privilège) :** un utilisateur PostgreSQL **lecture seule** dédié.

> ⚠️ À appliquer **après test** (touche le chemin d'auth Grafana qui fonctionne) et
> nécessite une base fraîche (`make clean` puis `make up`, car `init.sql` ne s'exécute
> qu'à l'initialisation). Rollback trivial : remettre `user: velvet` dans `velvet.yml`.

1. Nouveau secret : ajouter `grafana_db_password` à `scripts/gen-secrets.sh`
   (`gen 24 > secrets/grafana_db_password`).
2. Script d'init `db-velvet/zz-grafana-ro.sh` (s'exécute après `init.sql`) :
   ```sh
   #!/bin/sh
   set -e
   PW=$(cat /run/secrets/grafana_db_password)
   psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<SQL
   CREATE ROLE grafana_ro LOGIN PASSWORD '${PW}';
   GRANT CONNECT ON DATABASE velvet TO grafana_ro;
   GRANT USAGE ON SCHEMA public TO grafana_ro;
   GRANT SELECT ON ALL TABLES IN SCHEMA public TO grafana_ro;
   ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO grafana_ro;
   SQL
   ```
3. Monter ce script + le secret sur `db-velvet`, exposer `GRAFANA_DB_PASSWORD` dans
   `fabric-watch/entrypoint.sh`, et dans `velvet.yml` remplacer `user: velvet` /
   `${DB_PASSWORD}` par `user: grafana_ro` / `${GRAFANA_DB_PASSWORD}`.

Résultat : un Grafana compromis ne peut plus que **lire** — plus aucune écriture sur
les données de santé. Argument fort pour un jury sécurité.
