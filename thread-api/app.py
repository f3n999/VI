import os
import time
import base64
import hashlib
import hmac
import datetime
from functools import wraps

from flask import Flask, request, jsonify, g
import jwt
import psycopg2


def read_secret(name, default=None):
    """Lit un secret depuis <NAME>_FILE (Docker secret) sinon depuis <NAME>."""
    path = os.environ.get(name + "_FILE")
    if path and os.path.exists(path):
        with open(path) as fh:
            return fh.read().strip()
    return os.environ.get(name, default)


JWT_SECRET = read_secret("JWT_SECRET")
if not JWT_SECRET:
    raise RuntimeError("JWT_SECRET absent (fournir JWT_SECRET_FILE ou JWT_SECRET)")

DB = dict(
    host=os.environ.get("DB_HOST", "db-velvet"),
    dbname=os.environ.get("DB_NAME", "velvet"),
    user=os.environ.get("DB_USER", "velvet"),
    password=read_secret("DB_PASSWORD"),
    port=int(os.environ.get("DB_PORT", "5432")),
)

app = Flask(__name__)


def get_db():
    last = None
    for _ in range(15):
        try:
            return psycopg2.connect(**DB)
        except psycopg2.OperationalError as exc:
            last = exc
            time.sleep(2)
    raise RuntimeError("base indisponible: %s" % last)


def verify_password(stored, password):
    """Verifie un hash 'pbkdf2_sha256$iter$salt_b64$hash_b64' en temps constant."""
    try:
        algo, iters, salt_b64, hash_b64 = stored.split("$")
    except (ValueError, AttributeError):
        return False
    if algo != "pbkdf2_sha256":
        return False
    salt = base64.b64decode(salt_b64)
    expected = base64.b64decode(hash_b64)
    dk = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, int(iters))
    return hmac.compare_digest(dk, expected)


def make_token(user_id, role):
    now = datetime.datetime.now(datetime.timezone.utc)
    payload = {
        "sub": str(user_id),
        "role": role,
        "iat": now,
        "exp": now + datetime.timedelta(hours=1),
    }
    return jwt.encode(payload, JWT_SECRET, algorithm="HS256")


def require_auth(fn):
    @wraps(fn)
    def wrapper(*args, **kwargs):
        header = request.headers.get("Authorization", "")
        if not header.startswith("Bearer "):
            return jsonify(error="missing bearer token"), 401
        try:
            claims = jwt.decode(header[7:], JWT_SECRET, algorithms=["HS256"])
        except jwt.ExpiredSignatureError:
            return jsonify(error="token expired"), 401
        except jwt.InvalidTokenError:
            return jsonify(error="invalid token"), 401
        g.user_id = int(claims["sub"])
        g.role = claims.get("role", "user")
        return fn(*args, **kwargs)

    return wrapper


@app.route("/health")
def health():
    return jsonify(status="ok", service="thread-api")


@app.route("/api/login", methods=["POST"])
def login():
    data = request.get_json(force=True, silent=True) or {}
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        "SELECT id, role, password_hash FROM users WHERE email=%s",
        (data.get("email", ""),),
    )
    row = cur.fetchone()
    cur.close()
    conn.close()
    if not row or not verify_password(row[2], data.get("password", "")):
        return jsonify(error="invalid credentials"), 401
    return jsonify(token=make_token(row[0], row[1]), user_id=row[0], role=row[1])


@app.route("/api/sensors", methods=["POST"])
@require_auth
def add_sensor():
    data = request.get_json(force=True, silent=True) or {}
    # Ecriture uniquement pour l'utilisateur authentifie (anti-IDOR).
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        "INSERT INTO health_data (user_id, heart_rate, fall_detected, posture) "
        "VALUES (%s, %s, %s, %s) RETURNING id",
        (g.user_id, data.get("heart_rate"),
         data.get("fall_detected", False), data.get("posture")),
    )
    new_id = cur.fetchone()[0]
    conn.commit()
    cur.close()
    conn.close()
    return jsonify(id=new_id, status="recorded")


@app.route("/api/sensors/<int:user_id>")
@require_auth
def get_sensors(user_id):
    if g.role != "admin" and g.user_id != user_id:
        return jsonify(error="forbidden"), 403
    conn = get_db()
    cur = conn.cursor()
    cur.execute(
        "SELECT id, heart_rate, fall_detected, posture, recorded_at "
        "FROM health_data WHERE user_id=%s ORDER BY id",
        (user_id,),
    )
    rows = cur.fetchall()
    cur.close()
    conn.close()
    return jsonify([
        dict(id=r[0], heart_rate=r[1], fall_detected=r[2],
             posture=r[3], recorded_at=str(r[4]))
        for r in rows
    ])


if __name__ == "__main__":
    # Dev local uniquement ; en conteneur c'est gunicorn (voir Dockerfile).
    app.run(host="127.0.0.1", port=8080, debug=False)
