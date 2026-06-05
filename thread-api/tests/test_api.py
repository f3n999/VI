"""
Suite de tests thread-api.
Tous les tests mockent get_db — aucune base de données réelle requise.
"""
import base64
import hashlib
import os
from unittest.mock import MagicMock, patch

import pytest
from pydantic import ValidationError

import app as api_module
from app import LoginRequest, SensorPayload, app, make_token, verify_password


# ── helpers ───────────────────────────────────────────────────────────────────

def _hash(password: str) -> str:
    salt = os.urandom(16)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, 600000)
    return "pbkdf2_sha256$600000$%s$%s" % (
        base64.b64encode(salt).decode(),
        base64.b64encode(dk).decode(),
    )


def mock_conn(fetchone_return=None, fetchall_return=None):
    conn = MagicMock()
    cur = MagicMock()
    cur.fetchone.return_value = fetchone_return
    cur.fetchall.return_value = fetchall_return or []
    conn.cursor.return_value = cur
    return conn


@pytest.fixture
def client():
    api_module.app.config["TESTING"] = True
    with api_module.app.test_client() as c:
        yield c


# ── verify_password ───────────────────────────────────────────────────────────

class TestVerifyPassword:
    def test_bon_mot_de_passe(self):
        h = _hash("motdepasse")
        assert verify_password(h, "motdepasse") is True

    def test_mauvais_mot_de_passe(self):
        h = _hash("motdepasse")
        assert verify_password(h, "wrong") is False

    def test_hash_malformed(self):
        assert verify_password("ceci-nest-pas-un-hash", "anything") is False

    def test_hash_vide(self):
        assert verify_password("", "anything") is False

    def test_hash_none(self):
        assert verify_password(None, "anything") is False


# ── modèles pydantic ──────────────────────────────────────────────────────────

class TestLoginRequest:
    def test_valide(self):
        m = LoginRequest(email="a@b.com", password="secret")
        assert m.email == "a@b.com"

    def test_champ_inattendu_rejete(self):
        with pytest.raises(ValidationError):
            LoginRequest(email="a@b.com", password="secret", role="admin")

    def test_password_manquant(self):
        with pytest.raises(ValidationError):
            LoginRequest(email="a@b.com")

    def test_email_manquant(self):
        with pytest.raises(ValidationError):
            LoginRequest(password="secret")


class TestSensorPayload:
    def test_valide_complet(self):
        m = SensorPayload(heart_rate=72, fall_detected=False, posture="upright")
        assert m.heart_rate == 72

    def test_valide_minimal(self):
        m = SensorPayload()
        assert m.fall_detected is False

    def test_champ_inattendu_rejete(self):
        with pytest.raises(ValidationError):
            SensorPayload(heart_rate=72, evil="DROP TABLE users--")

    def test_mauvais_type_heart_rate(self):
        with pytest.raises(ValidationError):
            SensorPayload(heart_rate="vite")


# ── API : login ───────────────────────────────────────────────────────────────

class TestLogin:
    def test_login_ok(self, client):
        pw_hash = _hash("password123")
        conn = mock_conn(fetchone_return=(3, "user", pw_hash))
        with patch("app.get_db", return_value=conn):
            r = client.post("/api/login",
                            json={"email": "jean.dupont@example.com",
                                  "password": "password123"})
        assert r.status_code == 200
        assert "token" in r.get_json()

    def test_mauvais_mot_de_passe(self, client):
        pw_hash = _hash("password123")
        conn = mock_conn(fetchone_return=(3, "user", pw_hash))
        with patch("app.get_db", return_value=conn):
            r = client.post("/api/login",
                            json={"email": "jean.dupont@example.com",
                                  "password": "faux"})
        assert r.status_code == 401

    def test_email_inconnu(self, client):
        conn = mock_conn(fetchone_return=None)
        with patch("app.get_db", return_value=conn):
            r = client.post("/api/login",
                            json={"email": "personne@example.com", "password": "x"})
        assert r.status_code == 401

    def test_injection_sql_bloquee(self, client):
        """
        Rejoue l'injection SQL subie par le prof : payload ' OR '1'='1 dans email.
        Attendu : 401 (pas 500), et la requête SQL reste paramétrée — le payload
        est dans les arguments, jamais concaténé dans la chaîne SQL.
        """
        conn = mock_conn(fetchone_return=None)
        with patch("app.get_db", return_value=conn):
            r = client.post("/api/login",
                            json={"email": "' OR '1'='1", "password": "x"})
        assert r.status_code == 401

        call_args = conn.cursor.return_value.execute.call_args
        sql, params = call_args[0]
        assert "%s" in sql, "La requête doit être paramétrée"
        assert "OR" not in sql, "Le payload ne doit PAS être concaténé dans le SQL"
        assert "' OR '1'='1" in params, "Le payload doit être dans les paramètres"

    def test_champ_inattendu_rejete(self, client):
        r = client.post("/api/login",
                        json={"email": "a@b.com", "password": "x", "role": "admin"})
        assert r.status_code == 400

    def test_body_invalide(self, client):
        r = client.post("/api/login", data="pas du json",
                        content_type="application/json")
        assert r.status_code == 400


# ── API : authentification obligatoire ───────────────────────────────────────

class TestAuth:
    def test_sans_token(self, client):
        r = client.get("/api/sensors/3")
        assert r.status_code == 401

    def test_token_invalide(self, client):
        r = client.get("/api/sensors/3",
                       headers={"Authorization": "Bearer ceci_nest_pas_un_token"})
        assert r.status_code == 401

    def test_token_expire(self, client):
        import datetime, jwt as pyjwt
        now = datetime.datetime.now(datetime.timezone.utc)
        payload = {
            "sub": "3", "role": "user",
            "iat": now - datetime.timedelta(hours=2),
            "exp": now - datetime.timedelta(hours=1),
        }
        expired = pyjwt.encode(payload, api_module.JWT_SECRET, algorithm="HS256")
        r = client.get("/api/sensors/3",
                       headers={"Authorization": f"Bearer {expired}"})
        assert r.status_code == 401


# ── API : sensors — IDOR ──────────────────────────────────────────────────────

class TestSensors:
    def _token(self, user_id=3, role="user"):
        return make_token(user_id, role)

    def test_acces_propres_donnees_ok(self, client):
        rows = [(1, 72, False, "upright", "2024-01-01 00:00:00")]
        conn = mock_conn(fetchall_return=rows)
        with patch("app.get_db", return_value=conn):
            r = client.get("/api/sensors/3",
                           headers={"Authorization": f"Bearer {self._token(3)}"})
        assert r.status_code == 200
        assert len(r.get_json()) == 1

    def test_idor_autre_utilisateur_interdit(self, client):
        """User 3 ne peut PAS lire les données du user 4."""
        r = client.get("/api/sensors/4",
                       headers={"Authorization": f"Bearer {self._token(3)}"})
        assert r.status_code == 403

    def test_admin_acces_tout(self, client):
        rows = [(2, 65, True, "lying", "2024-01-01 00:00:00")]
        conn = mock_conn(fetchall_return=rows)
        with patch("app.get_db", return_value=conn):
            r = client.get("/api/sensors/4",
                           headers={"Authorization": f"Bearer {self._token(1, 'admin')}"})
        assert r.status_code == 200


# ── API : add_sensor ──────────────────────────────────────────────────────────

class TestAddSensor:
    def _token(self, user_id=3):
        return make_token(user_id, "user")

    def test_ajout_valide(self, client):
        conn = mock_conn(fetchone_return=(42,))
        with patch("app.get_db", return_value=conn):
            r = client.post("/api/sensors",
                            json={"heart_rate": 72, "fall_detected": False,
                                  "posture": "upright"},
                            headers={"Authorization": f"Bearer {self._token()}"})
        assert r.status_code == 200
        assert r.get_json()["id"] == 42

    def test_champ_inattendu_rejete(self, client):
        r = client.post("/api/sensors",
                        json={"heart_rate": 72, "evil": "DROP TABLE users--"},
                        headers={"Authorization": f"Bearer {self._token()}"})
        assert r.status_code == 400

    def test_mauvais_type_rejete(self, client):
        r = client.post("/api/sensors",
                        json={"heart_rate": "rapide", "fall_detected": False},
                        headers={"Authorization": f"Bearer {self._token()}"})
        assert r.status_code == 400

    def test_sans_token(self, client):
        r = client.post("/api/sensors", json={"heart_rate": 72})
        assert r.status_code == 401
