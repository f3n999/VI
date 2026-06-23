# ⚠️ STACK « AVANT » — VOLONTAIREMENT VULNÉRABLE — NE PAS DÉPLOYER

> **Ce dossier est la photo de l'existant SL1PCONNECT, tel que reçu — non durci.**
> Il est conservé **uniquement comme référence « avant / après »** pour la soutenance :
> il montre d'où on part, et permet de prouver chaque faille fermée dans la stack durcie
> (à la racine du repo).
>
> **Ne jamais lancer cette stack en production ni l'exposer.** La version sécurisée est à
> la **racine du dépôt** (`../docker-compose.yml`).

---

## Pourquoi on la garde

Le prof a révélé avoir **subi une injection SQL sur cette API**. Garder l'original permet de
faire la démonstration la plus parlante : *« voici la faille que vous avez subie, voici la
même requête dans notre version durcie — elle est bloquée. »*

## Failles connues (volontaires) dans cette version

| Faille | Où | Corrigé dans la stack durcie (racine) |
|--------|-----|----------------------------------------|
| Injection SQL (concaténation) | `thread-api/app.py`, `tailor-panel/index.php` | Requêtes préparées partout |
| Secrets en clair (env vars) | `docker-compose.yml` | Docker secrets en fichiers `/run/secrets/*` |
| Base PostgreSQL exposée sur l'hôte | `docker-compose.yml` (`5432:5432`) | Réseau `data` `internal: true`, non publié |
| `docker.sock` monté dans Grafana | `docker-compose.yml` | Supprimé (lecture de logs par fichiers) |
| Debug Flask actif | `thread-api/app.py` | `debug=False`, gunicorn en conteneur |
| Conteneurs root, aucune limite | `docker-compose.yml` | non-root, `cap_drop: ALL`, `no-new-privileges` |
| Mots de passe faibles / non robustes | `db-velvet/init.sql` | PBKDF2-HMAC-SHA256 (600k itérations) |
| Pas de TLS | — | Reverse proxy nginx, TLS 1.2/1.3, HSTS |

## Lancer (audit uniquement, jamais en prod)

```bash
docker compose up --build
```

Voir la stack durcie et les preuves correspondantes dans le [`README.md` à la racine](../README.md).
