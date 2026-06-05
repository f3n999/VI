# Script de démo live — soutenance 7 juillet

> Durée cible : 15-20 min de démo + 5-10 min présentation préparée.
> Chaque étape a un résultat attendu précis. Si ça dérive → plan B (captures).

---

## Avant de rentrer dans la salle

- [ ] VM ESXi démarrée, IP connue
- [ ] `/etc/hosts` configuré sur le poste démo
- [ ] `docker compose ps` → tous `healthy`
- [ ] Navigateur ouvert sur `https://grafana.sl1p.local` (dashboard visible)
- [ ] Terminal prêt avec `scripts/demo.sh` sous la main
- [ ] Captures d'écran de secours dans `/plan-b/`

---

## Étape 0 — Pitch (30 sec)

> "On a récupéré une plateforme IoT déployée à la hâte avec des failles connues.
> On va vous montrer qu'on les a toutes fermées — et qu'on le prouve en live."

---

## Étape 1 — Reproductibilité (2 min)

```bash
git pull                         # repo à jour
sh scripts/gen-secrets.sh        # secrets + certificat TLS générés
docker compose up -d --build     # build + démarrage
docker compose ps                # tous running/healthy
```

**Résultat attendu :** tous les services en `healthy`.
**Angle :** "Aucun clic manuel. Git + une commande. Reproductible sur n'importe quelle VM."

---

## Étape 2 — Secrets non exposés (1 min)

```bash
docker compose exec thread-api env | grep -i -E 'PASSWORD|SECRET'
# Attendu : uniquement DB_PASSWORD_FILE et JWT_SECRET_FILE (pas les valeurs)
```

**Résultat attendu :** seuls les `_FILE` variables apparaissent, jamais les secrets en clair.
**Angle :** "Un `docker inspect` ou une fuite de logs ne révèle rien."

---

## Étape 3 — Isolation réseau : nmap (2 min)

```bash
sh scripts/nmap-proof.sh
# Attendu : seuls les ports 80 et 443 visibles depuis l'hôte
docker compose ps   # db-velvet et stitch-processor : colonne PORTS vide
curl http://localhost:5432   # connexion refusée
```

**Résultat attendu :** nmap ne voit que 80/443. PostgreSQL inaccessible depuis l'hôte.
**Angle :** "La base de données de santé n'est joignable nulle part depuis Internet."

---

## Étape 4 — Authentification + anti-IDOR (3 min)

```bash
# Sans token → 401
curl -k https://api.sl1p.local/api/sensors/3
# → {"error": "missing bearer token"}

# Login → token
TOKEN=$(curl -sk -X POST https://api.sl1p.local/api/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"jean.dupont@example.com","password":"password123"}' \
  | sed 's/.*"token":"\([^"]*\)".*/\1/')

# Ses propres données → 200
curl -k https://api.sl1p.local/api/sensors/3 \
  -H "Authorization: Bearer $TOKEN"

# Données d'un autre user → 403
curl -k https://api.sl1p.local/api/sensors/4 \
  -H "Authorization: Bearer $TOKEN"
```

**Résultat attendu :** 401 sans token, 200 sur /3, **403 sur /4**.
**Angle :** "L'IDOR est fermé. Un user ne peut accéder qu'à ses propres données de santé."

---

## Étape 5 — Rejeu de l'injection SQL (2 min) ← MOMENT CLÉ

```bash
# Le payload qui fonctionnait sur l'ancienne API
curl -sk -X POST https://api.sl1p.local/api/login \
  -H 'Content-Type: application/json' \
  -d '{"email":"'\'' OR '\''1'\''='\''1","password":"x"}'
# → {"error": "invalid credentials"}   (pas de 500, pas d'accès)

# Preuve : les tests le certifient
pytest thread-api/tests/test_api.py::TestLogin::test_injection_sql_bloquee -v
```

**Résultat attendu :** 401, pas de crash, pas d'accès illégitime.
**Angle :** "La faille SQL que vous avez subie — la voilà rejouée, et bloquée. Le test le prouve."

---

## Étape 6 — CI verts (1 min)

Montrer le dernier run GitHub Actions : hadolint ✅ · compose config ✅ · pytest 29/29 ✅ · trivy ✅

---

## Étape 7 — Supervision Grafana (2 min)

Ouvrir `https://grafana.sl1p.local` → dashboard IoT : courbes heart_rate, alertes falls, distribution postures.

**Angle :** "Supervision active, provisioning automatique — aucun clic pour configurer."

---

## Étape 8 — Résilience SLA (1 min)

```bash
docker kill $(docker compose ps -q thread-api)
watch docker compose ps   # thread-api repasse healthy en <30s
```

**Résultat attendu :** redémarrage automatique, SLA < 2 min respecté.

---

## Plan B (si la démo plante)

1. Captures PNG dans `/plan-b/` pour chaque étape
2. Vidéo de la démo complète (à enregistrer J-1)
3. Si la VM ESXi ne répond pas : local avec `localhost` (modifier /etc/hosts)
