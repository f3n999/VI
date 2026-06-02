-- Schema + seed. Mots de passe stockes en PBKDF2-HMAC-SHA256 (600k iterations).
-- Aucun mot de passe en clair. Comptes de demonstration uniquement.

CREATE TABLE users (
    id            SERIAL PRIMARY KEY,
    email         TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    role          TEXT NOT NULL DEFAULT 'user'
);

CREATE TABLE health_data (
    id            SERIAL PRIMARY KEY,
    user_id       INTEGER REFERENCES users(id),
    heart_rate    INTEGER,
    fall_detected BOOLEAN NOT NULL DEFAULT false,
    posture       TEXT,
    recorded_at   TIMESTAMP NOT NULL DEFAULT now()
);

INSERT INTO users (email, password_hash, role) VALUES
    ('admin@sl1pconnect.fr',        'pbkdf2_sha256$600000$Lzaxz3trOeVwJFAEi38T6Q==$begFw7tLfv6sBxXYCvCbZM9Z4VviIvgxtHzBUmu5T/U=', 'admin'),
    ('calvin.slipp@sl1pconnect.fr', 'pbkdf2_sha256$600000$fU35DPVgftf8CAqTMAixFg==$BzfydN51tFoJAlbWDgmnOMYw+lE+d5RRig/dLxDygfQ=', 'admin'),
    ('jean.dupont@example.com',     'pbkdf2_sha256$600000$sQcoMQNpE5dSZY2jRn5mRA==$z+Fnmr7XvAuIRgAMYt2k9KeghirJqw/UQVdK6qQILJw=', 'user'),
    ('marie.martin@example.com',    'pbkdf2_sha256$600000$VloahMznhiI7jF+9vlU2Pw==$82hbdyagRQXiWsMvZXA6X0ltmHY6vfBPa8SvU7GIF+o=', 'user');

INSERT INTO health_data (user_id, heart_rate, fall_detected, posture) VALUES
    (3,  72, false, 'upright'),
    (3, 112, false, 'walking'),
    (4,  65, true,  'lying'),
    (4,  88, false, 'sitting');
