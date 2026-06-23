# Déploiement reproductible — Ansible

Playbook minimal qui amène une VM Ubuntu vierge (sur l'ESXi) à une stack SL1PCONNECT
durcie qui tourne, **sans clic manuel** : installe Docker, clone le repo, génère les
secrets, lance la stack (+ observabilité en option).

> C'est la brique « Infrastructure as Code » demandée pour le déploiement reproductible.
> Le même résultat que le `make up` manuel, mais piloté et rejouable depuis une machine de
> contrôle.

## Prérequis (machine de contrôle)

- Ansible ≥ 2.14 (`pipx install ansible` ou `apt install ansible`)
- Accès SSH à la VM cible (clé), utilisateur sudo

## Utilisation

```bash
cd ansible
cp inventory.ini.example inventory.ini    # renseigner l'IP / l'utilisateur SSH de la VM
ansible-playbook -i inventory.ini playbook.yml

# Avec la couche observabilité (Prometheus + Loki) :
ansible-playbook -i inventory.ini playbook.yml -e observability=true
```

## Ce que fait le playbook

1. Installe Docker Engine + plugin Compose v2 (dépôt officiel Docker).
2. Clone (ou met à jour) le dépôt `VI` sur la VM.
3. Exécute `scripts/gen-secrets.sh` (secrets + certificat TLS) — **idempotent**, ne réécrit
   pas des secrets existants.
4. `docker compose up -d --build` (+ override observabilité si `observability=true`).
5. Affiche l'état des conteneurs.

## Idempotence

Relançable sans danger : les secrets déjà générés ne sont pas écrasés, Docker n'est pas
réinstallé s'il est présent, et `git` fait un simple `pull` si le repo est déjà là.

## Sécurité

- Aucun secret n'est transporté par Ansible : ils sont **générés sur la VM** par
  `gen-secrets.sh`. Rien de sensible ne transite par la machine de contrôle ni le repo.
- L'URL du dépôt est une variable (`repo_url`) — utiliser un dépôt privé + clé de déploiement
  en contexte réel.
