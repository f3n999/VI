# État du projet — snapshot

> Mis à jour : 2026-06-05 (session 2)
> Responsable maquette : toi (les collègues gèrent le dossier d'architecture)

---

## Périmètre de notre travail

**Livrable 2 — Maquette fonctionnelle :**
- Hyperviseur + VM (ESXi existant → à déployer sur la VM)
- 4 services IoT re-conteneurisés et sécurisés ✅
- Supervision active Grafana avec provisioning automatique ✅
- Déploiement reproductible sans clic manuel ✅

---

## Ce qui est 100% fait et validé

| Composant | État | Preuve |
|-----------|------|--------|
| Stack 6 services Docker Compose | ✅ | docker-compose.yml |
| Conteneurs non-root + cap_drop + read_only | ✅ | compose |
| Secrets Docker (jamais en env) | ✅ | compose |
| Réseau edge/data isolé | ✅ | compose |
| Healthchecks sur TOUS les services | ✅ | compose |
| TLS 1.2/1.3 + HSTS + headers sécurité | ✅ | nginx.conf |
| PBKDF2-SHA256 600k itérations | ✅ | app.py + init.sql |
| JWT HS256 + anti-IDOR | ✅ | app.py |
| Requêtes SQL préparées | ✅ | app.py + index.php |
| pydantic extra="forbid" | ✅ | app.py |
| 29 tests pytest (SQLi, auth, IDOR, pydantic) | ✅ | tests/ |
| CI hadolint + trivy + pytest | ✅ | .github/workflows/ci.yml |
| **EXT-01** Grafana provisioning auto | ✅ | fabric-watch/provisioning/ |
| **EXT-01** Grafana connecté à data network | ✅ | docker-compose.yml |
| **EXT-02** Dataset synthétique 49 lignes / 7 jours | ✅ | db-velvet/init.sql |
| **EXT-03** Script démo bash orchestré | ✅ | scripts/demo.sh |
| **EXT-04** Proof nmap scripté | ✅ | scripts/nmap-proof.sh |
| **EXT-05** Makefile | ✅ | Makefile |
| **EXT-06** Backup 3-2-1 chiffré + drill restauration | ✅ | scripts/backup.sh + restore-drill.sh |

---

## Ce qui reste

| Tâche | Contexte |
|-------|---------|
| **Déployer sur la VM ESXi** | Tout le code est prêt — `make up` sur la VM |
| Tester le runtime (caps, read_only tailor-panel) | Voir risques ci-dessous |
| Enregistrer la vidéo plan B | Faire tourner `make demo` sur la VM, capturer |
| EXT-07 Ansible (optionnel) | Seulement si du temps reste |

---

## Risques runtime connus (à vérifier au 1er `up`)

- `tailor-panel` + `read_only: true` : si ça boucle → retirer `read_only` de ce service uniquement
- `fabric-watch` + `cap_drop: ALL` + volume grafana-data : si chown échoue → retirer `cap_drop` de ce service
- `fabric-watch` accède maintenant au réseau `data` pour lire PostgreSQL — c'est voulu pour le dashboard
- DB_PASSWORD exposé comme env var dans l'entrypoint Grafana (temporairement, en mémoire uniquement)

---

## Commandes clés

```bash
make up        # génère secrets + build + start
make test      # 29 tests pytest
make demo      # scénario de démo complet
make nmap      # preuve isolation réseau
make logs      # logs en direct
make down      # stop
make clean     # stop + supprime volumes
sh scripts/backup.sh              # backup chiffré
sh scripts/restore-drill.sh       # drill de restauration
```
