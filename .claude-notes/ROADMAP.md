# Roadmap maquette — extensions par ordre de priorité

> Principe : une extension = un bloc autonome, testable, committé.
> On valide chaque étape avant de passer à la suivante.
> Soutenance : 7 juillet.

---

## EXT-01 — Grafana provisioning automatique [ À FAIRE ]

**Pourquoi :** actuellement `fabric-watch` démarre Grafana vierge.
La démo "reproductible" tombe si on doit cliquer pour configurer Grafana.
Sans provisioning auto, le `docker compose up` ne donne pas un dashboard prêt.

**Ce qu'on fait :**
- `fabric-watch/provisioning/datasources/velvet.yml` → datasource PostgreSQL auto
- `fabric-watch/provisioning/dashboards/provider.yml` → loader de dashboard
- `fabric-watch/provisioning/dashboards/iot.json` → dashboard santé (heart_rate, falls, posture)
- `fabric-watch/Dockerfile` : COPY du dossier provisioning

**Résultat attendu :** `docker compose up` → Grafana ouvre sur dashboard rempli, zéro clic.

**Preuve démo :** ouvrir `https://grafana.sl1p.local` → tableau de bord immédiatement visible.

---

## EXT-02 — Dataset synthétique enrichi [ À FAIRE ]

**Pourquoi :** actuellement `init.sql` a 4 lignes de données. Pour Grafana et la démo c'est vide.
Le prof a dit explicitement : données générées via LLM, jamais de données réelles.

**Ce qu'on fait :**
- `db-velvet/seed_demo.sql` : 30-40 lignes `health_data` réalistes (variation heart_rate, quelques chutes, postures variées, timestamps sur 7 jours)
- Inclus dans `init.sql` via `\i` ou fusionné directement

**Résultat attendu :** Grafana affiche des courbes, des alertes, du mouvement — visuellement convaincant.

---

## EXT-03 — Script de démo live [ À FAIRE ]

**Pourquoi :** la soutenance a 15-20 min de démo live. Sans script bash, on improvise et on se plante.

**Ce qu'on fait :**
- `scripts/demo.sh` : script commenté, chaque étape numérotée, correspondant au scénario PLAN.md
- Étapes : gen-secrets → up → health → secrets check → nmap → login → token → sensors OK → IDOR 403 → SQLi 401 → CI → Grafana

**Résultat attendu :** `sh scripts/demo.sh` rejoue toute la démo en ~5 min, avec outputs colorés.

---

## EXT-04 — Proof nmap scripté [ À FAIRE ]

**Pourquoi :** le prof veut voir `nmap` en live. Si nmap n'est pas installé sur la VM le jour J = fail.

**Ce qu'on fait :**
- `scripts/nmap-proof.sh` : installe nmap si absent, scanne l'hôte, filtre le résultat, affiche "seuls 80/443 ouverts"
- Inclus dans `demo.sh` (étape 4)

---

## EXT-05 — Makefile [ À FAIRE ]

**Pourquoi :** interface unique pour toutes les commandes projet. Réduit les erreurs.

**Cibles :**
- `make secrets` → gen-secrets.sh
- `make up` → docker compose up -d --build
- `make test` → pytest thread-api/tests -q
- `make demo` → scripts/demo.sh
- `make nmap` → scripts/nmap-proof.sh
- `make down` → docker compose down
- `make clean` → docker compose down -v

---

## EXT-06 — Backup 3-2-1 [ À FAIRE ]

**Pourquoi :** le prof demande "la meilleure politique de backup possible" + preuve de drill de restauration.

**Ce qu'on fait :**
- `scripts/backup.sh` : dump PostgreSQL chiffré (openssl), copie locale + remote (rsync ou rclone)
- `scripts/restore-drill.sh` : restauration depuis le backup, vérification de l'intégrité
- `docs/backup-strategy.md` : doc 3-2-1 (3 copies, 2 supports, 1 hors-site)

---

## EXT-07 — Ansible playbook ESXi [ OPTIONNEL ]

**Pourquoi :** "déploiement reproductible" = le prof veut voir IaC, pas juste un script bash.
Optionnel car time-consuming et non bloquant pour la démo.

**Ce qu'on fait :**
- `ansible/deploy.yml` : playbook qui installe Docker, clone le repo, lance gen-secrets, docker compose up
- `ansible/inventory.yml` : IP de la VM ESXi

---

## Ordre de priorité pour la soutenance

```
EXT-01 (Grafana) → EXT-02 (dataset) → EXT-03 (demo script) → EXT-04 (nmap) → EXT-05 (Makefile)
puis EXT-06 (backup) si temps
puis EXT-07 (Ansible) si vraiment du temps
```

Le strict minimum pour une démo solide : EXT-01 + EXT-02 + EXT-03 + EXT-04.
