# Plan d'action — Projet SL1PCONNECT

**Objectif :** présenter à la soutenance du **7 juillet** une infrastructure cible
hybride, virtualisée, conteneurisée, sécurisée et reproductible.
**Format :** ~5-10 min présentation préparée + 15-20 min démo live + 10-15 min questions.
**Acquis :** pilier *Conteneurisation* déjà livré (repo `VI`).

## Décisions cadrées (d'après les réponses du prof)

| Sujet | Décision | Justification |
|-------|----------|---------------|
| Modèle | **Hybride** on-prem (Nice) + cloud HDS (OVH) | « vive l'hybride » ; santé = Art.9 |
| Données de santé | **Garder l'hébergement HDS OVH** (ne pas internaliser) | certification HDS non atteignable en interne |
| Hyperviseur | ESXi (maquette) → cible **Proxmox VE** (open-source) | préférence open-source, budget 100 k€ |
| Orchestrateur | **k3s** (cible) / Compose durci (maquette) | open-source, NetworkPolicies (isolation Art.9), HA |
| À garder | **OpenBSD** (DNS NSD + DNSSEC), modèle 4 pare-feux | exigé par le prof |
| Legacy | **Windows XP non migré** → VLAN quarantaine isolé | imposé ; risque accepté documenté |
| ERP | **Sage → SaaS** | validé par le prof, retire un serveur legacy |
| Interco | **IPSec FW2FW** site-à-site | imposé ; SLA migration à respecter |
| Secrets | Docker secrets (maquette) → **Vault** (cible) | déjà en place dans `VI` |
| Données dev/preprod | **Synthétiques générées via LLM**, zéro donnée réelle | imposé |
| Chiffrement | BDD **chiffrée au repos** (gap actuel : non) + TLS partout | RGPD Art.9 |
| Sauvegarde | **3-2-1, chiffrée, restauration testée** | « la meilleure possible » |
| Budget | **≈ 0 € CapEx** : serveur Dell existant réutilisé + **100 % open-source** ; seuls coûts récurrents = HDS OVH + stockage backup + jours-homme. Enveloppe 100 k€ **largement respectée** | preuve de maîtrise des coûts |

## Grille implicite du prof (ses « tips » = à montrer en démo)

`Trivy` (CI ✓) · `hadolint` (CI ✓) · `healthcheck` (✓) · **`pydantic` strict (à ajouter)** ·
**tests « dans tous les sens » (à ajouter)** · **`nmap` scan (preuve d'exposition)** ·
`yaml strict` (compose config ✓) · **rejeu de la SQLi qu'ils ont subie (à scénariser)**.

---

## J1 — Architecture & dossier (la cible prend forme)

| Tâche | Livrable |
|-------|----------|
| Audit de l'existant mis au propre | `AUDIT.md` |
| Schéma cible hybride (Nice virtualisé + OVH HDS + DMZ + OT/Cerbère + boutiques IPSec) | schéma v1 |
| Plan d'adressage cible (segments .1/.2/.3/.111 + DMZ + IoT + quarantaine XP) | tableau |
| Comparatifs justifiés (hyperviseur, orchestrateur, backup, CI/CD) | sections dossier |
| Plan de migration (avec données, SLA <2 h, XP isolé, Sage→SaaS, OpenBSD gardé) | section dossier |
| Budget 100 k€ ventilé | tableau |

## J2 — Maquette & durcissement (la preuve technique)

| Tâche | Livrable |
|-------|----------|
| ESXi + VM, déploiement de la stack `VI` durcie | maquette qui tourne |
| **Ajouter `pydantic` (validation stricte `extra="forbid"`) à thread-api** | code + commit |
| **Suite de tests pytest** : authn obligatoire, IDOR→403, login PBKDF2 ok/ko, **rejeu SQLi bloquée**, rejet de champs inattendus | tests verts |
| **`nmap` du host** → seuls 80/443 ouverts ; db/stitch invisibles | capture |
| Supervision active (Grafana + healthchecks) | dashboard |
| Dataset synthétique généré via LLM (preprod) | `seed` preprod |

## J3 — Reproductibilité, démo & finalisation

| Tâche | Livrable |
|-------|----------|
| Déploiement reproductible (Git + CI ; option Ansible/Terraform vSphere) | pipeline |
| Stratégie de sauvegarde 3-2-1 chiffrée + **drill de restauration** | doc + preuve |
| Finalisation du dossier d'architecture | `dossier.pdf` |
| Slides (5-10 min) + **script de démo** + répétition + plan B (captures/vidéo) | support soutenance |

---

## Scénario de démo live (à répéter J3)

1. **Reproductibilité** : `git pull` → `sh scripts/gen-secrets.sh` → `docker compose up -d` → tout `healthy`.
2. **Secrets** : `docker compose exec thread-api env | grep -i secret` → rien en clair.
3. **Isolation** : `nmap` host → 80/443 only · `docker compose ps` → db/stitch non publiés.
4. **Auth / IDOR** : login → token → `/sensors/3` OK, `/sensors/4` → **403**, sans token → **401**.
5. **Rejeu de VOTRE SQLi** : injection sur le back-office → **bloquée** (requête préparée). « La faille que vous avez subie est fermée, et on le prouve. »
6. **Scans verts** : CI Trivy + hadolint + tests pytest.
7. **Supervision** : dashboard Grafana.
8. **Résilience** : `docker kill` d'un conteneur → redémarrage auto (SLA).

## Répartition suggérée (binômes)

- **Binôme A — Dossier/archi** : schéma, adressage, comparatifs, migration, budget.
- **Binôme B — Maquette/sécu** : ESXi+VM, pydantic, tests, nmap, supervision, démo.
- Mise en commun fin de chaque jour ; J3 = répétition commune.

## Risques & plan B

- Caps/non-root non testés runtime → valider au 1er `up` (J2 matin), ajuster.
- Démo live qui plante → **captures + vidéo de secours** (plan B obligatoire).
- Temps serré → la maquette **un service durci + supervision** suffit (exigence minimale), le reste = bonus.
