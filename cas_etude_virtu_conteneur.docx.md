**CAS D’ÉTUDE**

**Conception et déploiement d’une infrastructure cible**

Virtualisation • Conteneurisation • Orchestration

**SL1PCONNECT S.A.S.**

*Sous-vêtements de luxe connectés  •  HealthTech / IoT*

| Module | Titre RNCP | Niveau |
| :---- | :---- | :---- |
| **Virtualisation & Conteneurisation** | RNCP39999 | Bac+5 — Niveau 7 |
| Format évaluation | Durée | Modalité |
| **Projet \+ soutenance (démo live)** | À définir par l’équipe pédagogique | Travail en équipe |

| ⚠  NOTICE PÉDAGOGIQUE Cas d’étude entièrement fictif. Toute ressemblance avec une entreprise existante est fortuite. Les noms d’hôtes, plages IP et configurations servent uniquement de support d’exercice. |
| :---- |

# **1\. Contexte de l’entreprise**

**SL1PCONNECT** conçoit et distribue des sous-vêtements de luxe connectés intégrant des micro-capteurs textiles (fréquence cardiaque, détection de chutes, posture, température). Les données remontent en BLE vers l’application mobile SL1P puis vers une plateforme cloud pour analyse et alertes. Clients B2C (grand public) et B2B médico-social (maisons de retraite, mutuelles).  
Scale-up créée en 2018 à Nice, \~666 collaborateurs, 42 M€ de CA, en levée de fonds Série B (24 M€). Croissance rapide : 4 nouvelles boutiques et une expansion européenne prévues sous 18 mois.

| Le problème L’infrastructure a grandi par accumulation, sans architecture cible : serveurs bare-metal hétérogènes au siège, plateforme cloud déployée à la hâte par un stagiaire (parti), conteneurs Docker mal configurés, déploiements manuels, aucune supervision centralisée ni reproductibilité. La direction technique veut une refonte complète, virtualisée et conteneurisée. |
| :---- |

# **2\. Infrastructure existante (à remplacer)**

L’existant s’articule autour de deux zones que vous devez reconstruire. Les autres sites (boutiques, Porto, Perpignan, Marseille) sont hors périmètre mais leurs interconnexions (IPSec / MPLS vers Nice) doivent rester prises en compte dans l’architecture cible.

## **2.1  Zone A — Siège Nice (on-premise)**

Serveurs bare-metal hétérogènes (pas de virtualisation, pas de consolidation). Liaison 10 Gbps, pare-feu Stormshield SN1100, switches FS S5850. Segmentation gérée par les firewalls.

| Hôte(s) | OS | Services | Ports | Notes |
| :---- | :---- | :---- | :---- | :---- |
| Boxer / Brief | Windows Server 2022 | AD DS, DFS, Print, NTP | LAN | PDC \+ RODC — 512 comptes, pas de MFA |
| Bjorn / Borg / Sloggi / Okaou | Debian 11 | Nginx — boutique en ligne | 80, 443 | TLS 1.2+, failover Marseille manuel |
| Dim / Eminence / Hom / Athena | OpenBSD 7.2 | DNS (NSD) | 53 | DNSSEC actif |
| Calecon1 / Calecon2 | OpenBSD 7.2 | MariaDB | 3306 (LAN) | BDD boutique \+ clients |
| Coton | Win Server 2019 | Gitea, WAMP préprod, fichiers | LAN | Données prod utilisées en recette |
| Lycra | Arch Linux | Mattermost, OwnCloud, SFTP | LAN | Docker dispo, peu supervisé |
| Satin | Win Server 2016 | Sage ERP | LAN | Admin distante prestataire (RustDesk) |
| Dentelle | FreeBSD 12.4 | SFTP | 22 | Home chroot par utilisateur |

**Segments :** DNS .100/24 · Web .101/24 · SFTP .102/24 · BDD .111/24 · AD .1/24 · Internes .2/24 · Métier .3/24 · Postes clients .4/24 (224 postes, dont 1 XP et 9 Win7 hors support).

## **2.2  Zone B — Plateforme IoT (Cloud OVH)**

VM Ubuntu déployées manuellement, hébergeant l’app mobile, l’API IoT et les données de santé. Pare-feu en configuration par défaut. DMZ 10.0.1.0/24, LAN interne 10.0.2.0/24, tunnel IPSec d’administration vers Nice.

| VM | OS | Rôle |
| :---- | :---- | :---- |
| web-cotton (10.0.1.10) | Ubuntu 22.04 | Nginx reverse proxy \+ front IoT, HTTPS Let’s Encrypt, exposé Internet |
| app-lycra (10.0.1.20) | Ubuntu 22.04 | Hôte Docker mono-machine — 4 conteneurs applicatifs |
| db-velvet (10.0.1.30) | Ubuntu 20.04 | PostgreSQL 12 — données de santé, comptes, tokens d’auth |
| nas-satin (10.0.2.10) | Ubuntu 20.04 | Partages SMB internes équipe dev |

**Conteneurs Docker sur app-lycra :**

| Conteneur | Port | Stack | Rôle |
| :---- | :---- | :---- | :---- |
| thread-api | 8080 | Python / Flask | API REST app mobile (auth, capteurs, alertes) |
| tailor-panel | 8081 | PHP / Apache | Back-office (gestion comptes, données santé, exports) |
| stitch-processor | 8082 | Node.js | Traitement des données de santé (posture, chutes) |
| fabric-watch | 9090 | Grafana | Supervision Docker et API |

# **3\. Dette technique et limites de l’existant**

Éléments qui justifient une infrastructure de remplacement :

* Aucune virtualisation au siège : serveurs physiques hétérogènes, sous-utilisés, sans haute disponibilité ni snapshot.  
* Hôte Docker unique (app-lycra) : pas d’orchestration, pas de redondance, point de défaillance unique.  
* Conteneurs lancés en root, images non scannées depuis 6+ mois, réseau bridge partagé (lateral movement), docker.sock monté dans un conteneur.  
* Secrets (tokens, mots de passe BDD, clés) en clair dans les variables d’environnement et les docker-compose.yml.  
* Déploiements manuels le vendredi soir, sans fenêtre de maintenance, sans pipeline ni tests automatisés.  
* Environnements dev / préprod / prod mélangés ; données réelles utilisées en recette.  
* Pas d’Infrastructure-as-Code : rien n’est reproductible ni versionné.  
* Aucune supervision centralisée ni collecte de logs ; sauvegardes OVH non chiffrées.  
* Accès de l’ex-stagiaire (clés SSH, tokens) jamais révoqués ; clés SSH partagées entre admins.

# **4\. Contraintes à respecter**

| Thème | Exigence |
| :---- | :---- |
| Disponibilité | App mobile et boutique en ligne : pas de coupure \> 2 h. La cible doit prévoir la redondance des services critiques. |
| Données de santé | Données RGPD Art.9 (hébergement HDS) : isolation réseau, chiffrement au repos et en transit, séparation stricte dev/prod — à traduire dans l’architecture. |
| Interconnexions | Les liaisons IPSec / MPLS vers les sites distants (Porto, Perpignan, boutiques, Marseille) doivent rester fonctionnelles. |
| Reproductibilité | Tout déploiement doit être reproductible et versionné (IaC / pipeline). Aucun « clic manuel » non documenté. |
| Croissance | La cible doit absorber l’ouverture de nouvelles boutiques et l’expansion européenne (scalabilité). |

# **5\. Votre mission**

| CONSIGNE En équipe, vous incarnez le cabinet chargé de refondre l’infrastructure de SL1PCONNECT. Vous devez concevoir, justifier et déployer une infrastructure de remplacement, virtualisée et conteneurisée, couvrant la Zone A (siège Nice) et la Zone B (plateforme IoT). Vous êtes libres du choix des technologies : tout est permis, à condition de le justifier. |
| :---- |

**Attendus minimaux — votre proposition doit traiter :**

* Virtualisation : choix d’un hyperviseur, consolidation des serveurs Nice en VM, stratégie de snapshots / sauvegarde / haute disponibilité.  
* Conteneurisation : re-conteneurisation propre des 4 services IoT (Dockerfiles non-root, images optimisées et scannées), réseaux isolés, gestion des secrets, reverse proxy.  
* Orchestration : choisir et justifier le niveau adapté (Compose durci, Swarm, k3s, Kubernetes…) et l’appliquer.  
* Séparation des environnements dev / préprod / prod et reproductibilité (Infrastructure-as-Code).

**Briques complémentaires — à proposer librement (liste non exhaustive) :**  
forge logicielle et CI/CD (GitLab, Gitea…), registre d’images, supervision et métriques, centralisation des logs / SIEM, gestion de tickets et de projet (Jira, Redmine…), gestion des secrets, sauvegarde, annuaire, etc. Toute brique pertinente est bienvenue, à condition d’être justifiée et intégrée à l’architecture.

## **5.1  Livrables**

1. Un dossier d’architecture cible : schéma, choix techniques justifiés, comparatif des solutions étudiées, plan d’adressage, et plan de migration depuis l’existant.  
2. Une maquette fonctionnelle déployée : hyperviseur \+ VM \+ au moins un service IoT re-conteneurisé et orchestré, supervision active, déploiement reproductible.  
3. Une démonstration live en soutenance : déploiement / redémarrage d’un service via le pipeline ou l’IaC, preuve d’isolation réseau et de gestion des secrets.

# **Annexe — Synthèse de l’infrastructure existante**

INTERNET  
   |  
   |-- ISP pink \--------------- NICE (HQ)  \[Stormshield SN1100\]  
   |          .100/24 DNS  | .101/24 Web | .111/24 BDD  
   |          .1/24 AD     | .2/24 Internes | .3/24 Metier | .4/24 Postes  
   |  
   |-- OVH Cloud \-------------- PLATEFORME IoT  \[Firewall par defaut\]  
   |          DMZ 10.0.1.0/24 : web-cotton / app-lycra / db-velvet  
   |          LAN 10.0.2.0/24 : nas-satin  
   |          Conteneurs : thread-api:8080 | tailor-panel:8081  
   |                       stitch-processor:8082 | fabric-watch:9090  
   |  
   |-- IPSec \------------------ PORTO (atelier)      \[hors perimetre\]  
   |-- IPSec \------------------ PERPIGNAN (OT)       \[hors perimetre\]  
   |-- MPLS \+ IPSec \----------- PARIS V / PARIS XII  \[hors perimetre\]  
   |-- ISP \+ 4G \--------------- BOUTIQUES FR / NL    \[hors perimetre\]  
   '-- ISP green \-------------- MARSEILLE (DC TissuCloud) \[hors perimetre\]